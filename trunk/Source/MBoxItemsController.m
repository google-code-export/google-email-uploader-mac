/* Copyright (c) 2009 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "MBoxItemsController.h"
#import "EmUpUtilities.h"

static const char* memsearch(const char* needle, unsigned long long needleLen,
                      const char* haystack, unsigned long long haystackLen);

@interface MBoxItemsController (PrivateMethods)
- (void)loadMailItems;
- (NSString *)endOfLineForFileData:(NSData *)fileData;
- (NSString *)fromStringForFileData:(NSData *)fileData;
- (void)setLastUploadedItem:(OutlineViewItemMBox *)item;

- (NSString *)dateStringForMessageFirstLine:(NSString *)firstLine;
- (NSArray *)mailItemPropertiesForHeaders:(NSString *)message
                                endOfLine:(NSString *)endOfLine;
@end


@implementation OutlineViewItemMBox

- (void)dealloc {
  [messageOffsets_ release];
  [endOfLine_ release];
  [super dealloc];
}

- (void)setMessageOffsets:(NSArray *)array {
  [messageOffsets_ autorelease];
  messageOffsets_ = [array retain];
}

- (NSArray *)messageOffsets {
  return messageOffsets_;
}

- (void)setEndOfLine:(NSString *)str {
  [endOfLine_ autorelease];
  endOfLine_ = [str copy];
}

- (NSString *)endOfLine {
  return endOfLine_;
}
@end

@implementation MBoxItemsController

- (id)initWithMailFolderPath:(NSString *)path
                    rootName:(NSString *)rootName
{
  self = [super init];
  if (self) {
    mailFolderPath_ = [path copy];
    rootName_ = [rootName copy];

    [self loadMailItems];
  }
  return self;
}

- (void)dealloc {
  [mailFolderPath_ release];
  [rootName_ release];

  [rootItem_ release];
  [lastUploadedItem_ release];
  [uploadingData_ release];
  [super dealloc];
}

#pragma mark -

- (NSString *)defaultMailFolderPath {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (NSString *)defaultRootName {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (const char *)messagePrefix {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (OutlineViewItem *)rootItem {
  return rootItem_;
}

- (NSString *)mailFolderPath {
  return mailFolderPath_;
}

- (NSString *)byteStringReportForAddress:(const unsigned char *)ptr
                                  length:(unsigned long long)length {
  NSMutableString *resultStr = [NSMutableString string];

  const int charsPerLine = 16;

  BOOL isDone = NO;

  for (int lineNum = 0; lineNum < 20; lineNum++) {

    int lineOffset = lineNum * charsPerLine;

    NSMutableString *ascii = [NSMutableString string];
    NSMutableString *hex = [NSMutableString string];

    for (int charNum = 0; charNum < charsPerLine; charNum++) {

      if (lineOffset + charNum >= length) {
        isDone = YES;
      }

      if (!isDone) {
        // not done; create the ascii and hex parts
        if (*ptr >= 0x20 && *ptr <= 0x7f) {
          [ascii appendFormat:@"%c", *ptr];
        } else {
          [ascii appendString:@"."];
        }

        [hex appendFormat:@"%02X", *ptr];
        if (charNum % 2 == 1) [hex appendString:@" "];

        ++ptr;
      } else {
        // keep padding the ascii part
        [ascii appendString:@" "];
      }
    }

    [resultStr appendFormat:@"%04X: %@  %@\n", lineOffset, ascii, hex];
    if (isDone) break;
  }
  return resultStr;
}

- (void)loadMailItems {
  // build a dictionary for all mailboxes
  NSFileManager *fileMgr = [NSFileManager defaultManager];

  BOOL isDir = NO;
  if (![fileMgr fileExistsAtPath:mailFolderPath_ isDirectory:&isDir] || !isDir) {
    // no MBox mail folder found; leave the root item ivar nil
    return;
  }

  NSDirectoryEnumerator *enumerator = [fileMgr enumeratorAtPath:mailFolderPath_];

  rootItem_ = [[OutlineViewItemMBox itemWithName:rootName_
                level:0] retain];

  NSString *partialPath;
  OutlineViewItemMBox *lastOutlineItem = rootItem_;

  NSDate *lastDisplayDate = [NSDate date];

  // all messages begin with "\nFrom " or "\rFrom ", except the first
  // message in the file
  const char *kFrom = "From ";
  const int kFromLen = strlen(kFrom);

  // make a map of partial paths to created outline items
  NSMutableDictionary *itemMap = [NSMutableDictionary dictionaryWithObject:rootItem_
                                                                    forKey:@""];

  while ((partialPath = [enumerator nextObject]) != nil) {

    NSDictionary *pathAttrs = [enumerator fileAttributes];

    NSString *fullPath = [mailFolderPath_ stringByAppendingPathComponent:partialPath];
    NSString *partialPathParent = [partialPath stringByDeletingLastPathComponent];
    NSString *pathExtension = [partialPath pathExtension];
    NSString *lastPathComponent = [partialPath lastPathComponent];

    // display the path periodically when stepping through mailboxes so the user
    // knows we're making progress
    if ([lastDisplayDate timeIntervalSinceNow] < -0.2) {
      lastDisplayDate = [NSDate date];
      [[NSNotificationCenter defaultCenter] postNotificationName:kEmUpLoadingMailbox
                                                          object:fullPath];
    }

    BOOL isDir = [[pathAttrs objectForKey:NSFileType] isEqual:NSFileTypeDirectory];

    // skip invisible files and dirs
    if ([lastPathComponent hasPrefix:@"."]) {
      if (isDir) [enumerator skipDescendents];
      continue;
    }

    NSArray *partialPathParts = [partialPath componentsSeparatedByString:@"/"];

    if (isDir) {
      // add this directory path to the tree
      OutlineViewItemMBox *dirItem = [itemMap objectForKey:partialPath];
      if (dirItem == nil) {

        // new directory; create the outline item, store it in the map,
        // and save it as a child of its parent
        int level = [partialPathParts count];

        dirItem = [OutlineViewItemMBox itemWithName:lastPathComponent
                                              level:level];
        [itemMap setObject:dirItem forKey:partialPath];

        OutlineViewItemMBox *parentItem = [itemMap objectForKey:partialPathParent];

        NSAssert1(parentItem != nil, @"missing parent for %@", partialPath);
        [parentItem addChild:dirItem];
      } else {
       // we've seen this directory before
      }

    } else if (![pathExtension isEqual:@"toc"] // Eudora metadata
               && ![pathExtension isEqual:@"msf"]) { // Tbird metadata

      // we'll try to count the messages in files without blowing chunks on
      // gigabyte-size mbox files

      // make a no-copy NSString from a memory-mapped NSData
      //
      // hopefully, this will let us access huge files without killing
      // the machine

      // we'll explicitly release fileData below to free up the memory-mapped
      // file
      NSData *fileData = [[NSData alloc] initWithContentsOfMappedFile:fullPath];
      unsigned int dataLen = [fileData length];
      const char *fileDataPtr = [fileData bytes];

      // before attempting to use the file, check its first bytes are "From"
      if (dataLen > kFromLen
          && strncmp(fileDataPtr, kFrom, kFromLen) == 0) {

        // figure out the line endings for this mbox file
        NSString *endOfLine = [self endOfLineForFileData:fileData];
        if (endOfLine == nil) {
          NSLog(@"could not determine eol for file: %@", fullPath);
          endOfLine = @"\n";
        }
        unsigned int eolLen = [endOfLine length];
        
        // get the "From " string we'll use as a message separator for this file
        NSString *fromString = [self fromStringForFileData:fileData];

        const char *fromAfterReturn = [[NSString stringWithFormat:@"%@%@",
                                        endOfLine, fromString] UTF8String];
        size_t fromAfterReturnLen = strlen(fromAfterReturn);

        // locate the message separators; the first one is at byte zero
        unsigned long long offset = 0;

        NSNumber *offset0 = [NSNumber numberWithUnsignedLongLong:0];
        NSMutableArray *offsetsArray = [NSMutableArray arrayWithObject:offset0];

        while (1) {
          // display the path periodically when stepping through messages of a
          // mailbox so we look busy
          if ([lastDisplayDate timeIntervalSinceNow] < -0.2) {
            lastDisplayDate = [NSDate date];
            [[NSNotificationCenter defaultCenter] postNotificationName:kEmUpLoadingMailbox
                                                                object:fullPath];
          }

          // we use our own memsearch rather than strnstr in case messages
          // contain nulls
          const char *foundPtr = memsearch(fromAfterReturn, fromAfterReturnLen,
                                       fileDataPtr + offset, dataLen - offset);
          if (!foundPtr) break;

          // skip the initial return or newline char when calculating the
          // offset of each message
          offset = foundPtr + eolLen - fileDataPtr;

          // add the offset of this message to our array
          [offsetsArray addObject:[NSNumber numberWithUnsignedLongLong:offset]];

          // search again from after the last found "\rFrom" prefix
          offset += fromAfterReturnLen;
        }

        // add this mailbox to the outline view
        unsigned int level = [partialPathParts count];

        OutlineViewItemMBox *childItem
          = [OutlineViewItemMBox itemWithName:lastPathComponent
                                        level:level];

        [childItem setNumberOfMessages:[offsetsArray count]];
        [childItem setMessageOffsets:offsetsArray];
        [childItem setPath:fullPath];
        [childItem setEndOfLine:endOfLine];

        // add this new item as a child of the most recently-visited folder
        OutlineViewItemMBox *parentItem = [itemMap objectForKey:partialPathParent];

        NSAssert1(parentItem != nil, @"missing parent for %@", partialPath);
        [parentItem addChild:childItem];

        // add this to the linked list of outline items to be uploaded
        [lastOutlineItem setNextOutlineItem:childItem];
        lastOutlineItem = childItem;

        [itemMap setObject:childItem forKey:partialPath];
      }

      [fileData release];
      fileData = nil;
    }
  }

  [rootItem_ setState:NSOnState];

  // clear the name of the mailbox being loaded
  [[NSNotificationCenter defaultCenter] postNotificationName:kEmUpLoadingMailbox
                                                      object:@""];
}

- (NSString *)endOfLineForFileData:(NSData *)fileData {

  // since an mbox file should start with a header, scan until we find
  // a \r, \n, or \r\n, and assume that end-of-line marker applies for the
  // whole file
  //
  // as a sanity check, limit our scan to 1000 chars

  unsigned int numberOfBytesToTest = MIN([fileData length], 1000);
  char *fileBytes = (char *) [fileData bytes];

  for (unsigned int idx = 0; idx < numberOfBytesToTest; idx++) {
    char c = fileBytes[idx];

    if (c == '\n') {
      return @"\n";
    }

    if (c == '\r') {

      // check if the next character after this return is a newline
      if (idx + 1 < numberOfBytesToTest
          && fileBytes[idx+1] == '\n') {
        return @"\r\n";
      } else {
        return @"\r";
      }
    }
  }

  return nil;
}

- (NSString *)fromStringForFileData:(NSData *)fileData {

  // Eudora mbox files may not reliably change From strings at the beginning
  // of lines inside message bodies to >From, leading to mistakes in determining
  // where messages end.  So if the first message in the file is From ???@???
  // we'll use that as the From string.
  const char *const kEudoraFromBytes = "From ???@???";
  int eudoraFromLen = strlen(kEudoraFromBytes);

  if ([fileData length] > eudoraFromLen) {
    if (memcmp(kEudoraFromBytes, [fileData bytes], eudoraFromLen) == 0) {
      // this file starts with the Eudora-style From
      return @"From ???@???";
    }
  }

  // for generic mbox, we'll just search for the traditional "From "
  return @"From ";
}

- (unsigned int)countSelectedMessages {

  unsigned int count = [rootItem_ recursiveNumberOfCheckedMessages];
  return count;
}

- (void)resetUpload {
  [self setLastUploadedItem:nil];
}

- (void)failUploadWithMessageIndex:(unsigned int)index
                              path:(NSString *)path
                             range:(NSRange)range
                       errorString:(NSString *)errorStr {
  
  // report an upload failure to the user by notifying the main controller
  NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                        path, kEmUpMessagePathKey,
                        [NSNumber numberWithInt:index], kEmUpMessageIndexKey,
                        [NSValue valueWithRange:range], kEmUpMessageRangeKey,
                        errorStr, kEmUpMessageErrorStringKey,
                        nil];
  
  [[NSNotificationCenter defaultCenter] postNotificationName:kEmUpMessageParsingFailed
                                                      object:dict];
}

- (GDataEntryMailItem *)nextUploadItem {
  // find the next view item to upload

  if (lastUploadedItem_ == nil) {
    // starting from scratch
    [self setLastUploadedItem:[rootItem_ nextOutlineItem]];
    lastUploadedIndex_ = -1;
  }

  while (lastUploadedItem_ != nil) {

    ++lastUploadedIndex_;

    NSArray *messageOffsets = [lastUploadedItem_ messageOffsets];

    unsigned int numberOfMessages = [messageOffsets count];

    NSString *endOfLine = [lastUploadedItem_ endOfLine];
    const char* utf8EndOfLine = [endOfLine UTF8String];

    BOOL didExhaustFolder = (lastUploadedIndex_ >= numberOfMessages);
    if (didExhaustFolder) {
      // move to next upload item (the next mbox)
      [self setLastUploadedItem:[lastUploadedItem_ nextOutlineItem]];
      lastUploadedIndex_ = -1;

      // immediately free the memory from the last mbox file
      [uploadingData_ release];
      uploadingData_ = nil;

    } else {
      OutlineViewItemMBox *thisUploadItem = lastUploadedItem_;
      int thisUploadIndex = lastUploadedIndex_;

      NSCellStateValue state = [thisUploadItem state];
      if (state != NSOffState) {

        NSString *mboxPath = [thisUploadItem path];

        // if we've not yet opened this mbox file, do it now
        if (uploadingData_ == nil) {

          // read in the file memory-mapped in case it's huge
          uploadingData_ = [[NSData alloc] initWithContentsOfMappedFile:mboxPath];
          if (uploadingData_ == nil) {

            [self failUploadWithMessageIndex:thisUploadIndex
                                        path:mboxPath
                                       range:NSMakeRange(0, 0)
                                 errorString:@"Could not open MBox file"];
            continue;
          }
        }

        unsigned int dataLen = [uploadingData_ length];
        const char *fileDataPtr = [uploadingData_ bytes];

        NSNumber *thisMessageOffsetNum = [messageOffsets objectAtIndex:thisUploadIndex];
        unsigned long long thisMessageOffset = [thisMessageOffsetNum unsignedLongLongValue];

        unsigned long long nextMessageOffset;

        BOOL isLastMessage = (thisUploadIndex + 1 == numberOfMessages);
        if (isLastMessage) {
          nextMessageOffset = dataLen;
        } else {
          NSNumber *nextMessageOffsetNum = [messageOffsets objectAtIndex:(1 + thisUploadIndex)];
          nextMessageOffset = [nextMessageOffsetNum unsignedLongLongValue];
        }

        // skip the first line in the message, containing the false From ???@???
        // and date, and get a "real" pointer to the start of the actual message
        // text
        unsigned long long thisMessageLength = nextMessageOffset - thisMessageOffset;

        const char *thisMessagePtr = fileDataPtr + thisMessageOffset;
        char *realMessagePtr = strnstr(thisMessagePtr, utf8EndOfLine,
                                       thisMessageLength);

        NSRange messageRange = NSMakeRange(thisMessageOffset, thisMessageLength);

        if (realMessagePtr == NULL) {
          // something is really wrong if we can't find the expected kind of
          // end-of-line string
          NSString *report = [self byteStringReportForAddress:(const unsigned char *)thisMessagePtr
                                                       length:thisMessageLength];
          NSLog(@"could not find first return in message (%d-%d) from file: %@\n%@",
                (int)thisMessageOffset, (int)nextMessageOffset-1, mboxPath,
                report);

          NSString *template = @"Could not find opening line (bytes %d-%d)";
          NSString *errMsg = [NSString stringWithFormat:template,
                              (int)thisMessageOffset, (int)nextMessageOffset-1];

          [self failUploadWithMessageIndex:thisUploadIndex
                                      path:mboxPath
                                     range:messageRange
                               errorString:errMsg];
          continue;
        }

        realMessagePtr += [endOfLine length]; // skip return char

        unsigned long long skippedLineLength = realMessagePtr - thisMessagePtr;
        unsigned long long realMessageLength = thisMessageLength - skippedLineLength;

        // read the message into a string
        //
        // Try UTF-8 first, since that's well-defined, unlike other encodings
        NSStringEncoding encoding = NSUTF8StringEncoding;
        NSString *messageText = [[[NSString alloc] initWithBytesNoCopy:realMessagePtr
                                                                length:realMessageLength
                                                              encoding:encoding
                                                          freeWhenDone:NO] autorelease];
        if (messageText == nil) {
          // try MacRoman encoding
          encoding = NSMacOSRomanStringEncoding;
          messageText = [[[NSString alloc] initWithBytesNoCopy:realMessagePtr
                                                        length:realMessageLength
                                                      encoding:encoding
                                                  freeWhenDone:NO] autorelease];
        }

        if (messageText == nil) {
          // try WinLatin encoding
          encoding = NSWindowsCP1252StringEncoding;
          messageText = [[[NSString alloc] initWithBytesNoCopy:realMessagePtr
                                                        length:realMessageLength
                                                      encoding:encoding
                                                  freeWhenDone:NO] autorelease];
        }

        if (messageText == nil) {
          NSLog(@"could not read message (%d-%d) from file: %@",
                (int)thisMessageOffset, (int)nextMessageOffset-1, mboxPath);

          NSString *template = @"Could not interpret message (bytes %d-%d)";
          NSString *errMsg = [NSString stringWithFormat:template,
                              (int)thisMessageOffset, (int)nextMessageOffset-1];

          [self failUploadWithMessageIndex:thisUploadIndex
                                      path:mboxPath
                                     range:messageRange
                               errorString:errMsg];
          continue;
        }

        // uploads limited to 31 megs
        if ([messageText length] < kMaxMesssageSize) {

          // fix up message headers, if necessary
          messageText = [EmUpUtilities messageTextWithAlteredHeadersForMessageText:messageText
                                                                         endOfLine:endOfLine];

          NSString *headers = [EmUpUtilities headersForMessageText:messageText
                                                         endOfLine:endOfLine];
          if (headers == nil) {
            NSLog(@"could not find headers in message (bytes %d-%d) from file: %@",
                  (int)thisMessageOffset, (int)nextMessageOffset-1, mboxPath);
          }

          // some old eudora mail lacks a Date header; for those, we'll make
          // one from the initial From line.  The From line represents the
          // time the message was written, so we'll use the local time
          // zone
          NSString *dateStr = [EmUpUtilities stringForHeader:@"Date"
                                                 fromHeaders:headers
                                                   endOfLine:endOfLine];
          if ([dateStr length] == 0) {
            NSString *firstLine =
              [[[NSString alloc] initWithBytesNoCopy:(void *)thisMessagePtr
                                              length:skippedLineLength
                                            encoding:encoding
                                        freeWhenDone:NO] autorelease];

            NSString *newDateStr = [self dateStringForMessageFirstLine:firstLine];
            if ([newDateStr length] > 0) {
              // insert a date header at the beginning of the message
              messageText = [NSString stringWithFormat:@"Date: %@%@%@",
                             newDateStr, endOfLine, messageText];
            }
          }

          if (![endOfLine isEqual:@"\n"]) {
            // The server's header parsing code doesn't respect \r\r as ending a
            // header block, so it tends to find "invalid headers" in the body
            // of messages using returns as line separators. So we'll change
            // returns to newlines before encoding the message.
            NSMutableString *mutable = [NSMutableString stringWithString:messageText];
            [mutable replaceOccurrencesOfString:@"\r\n"
                                     withString:@"\n"
                                        options:0
                                          range:NSMakeRange(0, [mutable length])];
            [mutable replaceOccurrencesOfString:@"\r"
                                     withString:@"\n"
                                        options:0
                                          range:NSMakeRange(0, [mutable length])];
            endOfLine = @"\n";
            messageText = mutable;
          }

          GDataEntryMailItem *newEntry = [GDataEntryMailItem mailItemWithRFC822String:messageText];

          [newEntry setProperty:[thisUploadItem name]
                         forKey:kEmUpMailboxNameKey];

          [newEntry setProperty:mboxPath
                         forKey:kEmUpMessagePathKey];

          [newEntry setProperty:[NSNumber numberWithInt:thisUploadIndex]
                         forKey:kEmUpMessageIndexKey];

          [newEntry setProperty:[NSValue valueWithRange:messageRange]
                         forKey:kEmUpMessageRangeKey];


          NSString *messageID = [EmUpUtilities stringForHeader:@"Message-ID"
                                                   fromHeaders:headers
                                                     endOfLine:endOfLine];
          if (messageID) {
            [newEntry setProperty:messageID
                           forKey:kEmUpMessageIDKey];
          }

          // add message properties
          NSArray *props = [self mailItemPropertiesForHeaders:headers
                                                    endOfLine:endOfLine];
          for (NSString *property in props) {
            GDataMailItemProperty *prop = [GDataMailItemProperty valueWithString:property];
            [newEntry addMailItemProperty:prop];
          }

          return newEntry;

        } else {
          NSString *template = @"Message too big (bytes %d-%d)";
          NSString *errMsg = [NSString stringWithFormat:template,
                              (int)thisMessageOffset, (int)nextMessageOffset-1];

          [self failUploadWithMessageIndex:thisUploadIndex
                                      path:mboxPath
                                     range:messageRange
                               errorString:errMsg];
        }
      }
    }
  }

  return nil;
}

- (NSString *)dateStringForMessageFirstLine:(NSString *)firstLine {

  if (firstLine == nil) return nil;

  // look for the characteristic Eudora new-message From line, like
  //
  //   From ???@??? Thu Feb 27 20:43:33 2003
  //
  // which unfortunately isn't in the date format needed for mail headers

  NSScanner *scanner = [NSScanner scannerWithString:firstLine];
  NSString *dateStr = nil;

  if ([scanner scanString:@"From ???@???" intoString:nil]
      && [scanner scanUpToString:@"\r" intoString:&dateStr]) {

    NSCalendarDate *parsedDate = [NSCalendarDate dateWithString:dateStr
                                                 calendarFormat:@"%a %b %d %H:%M:%S %Y"];
    if (parsedDate) {
      // regenerate the date in the proper format, like
      //   3 Apr 1995 16:38:24 -0700
      // per http://www.w3.org/Protocols/rfc822/#z28

      NSString *newDateStr = [parsedDate descriptionWithCalendarFormat:@"%d %b %Y %H:%M:%S %z"];
      return newDateStr;
    }
  }
  return nil;
}

- (NSArray *)mailItemPropertiesForHeaders:(NSString *)headers
                                endOfLine:(NSString *)endOfLine {

  NSMutableArray *props = [NSMutableArray array];

  NSString *mozStatus = [EmUpUtilities stringForHeader:@"X-Mozilla-Status"
                                           fromHeaders:headers
                                             endOfLine:endOfLine];
  if (mozStatus) {
    // convert from hex
    NSScanner *scanner = [NSScanner scannerWithString:mozStatus];

    unsigned int hexInt = 0;
    if ([scanner scanHexInt:&hexInt]) {

      BOOL isRead = ((hexInt & 0x0001) != 0);
      if (!isRead) [props addObject:kGDataMailItemIsUnread];

      BOOL isFlagged = ((hexInt & 0x0004) != 0);
      if (isFlagged) [props addObject:kGDataMailItemIsStarred];

      BOOL isDeleted = ((hexInt & 0x0008) != 0);
      if (isDeleted) [props addObject:kGDataMailItemIsTrash];

      // is draft status available in Thunderbird headers?
    }
  } else {
    // eudora status
    NSString *status = [EmUpUtilities stringForHeader:@"Status"
                                          fromHeaders:headers
                                            endOfLine:endOfLine];
    if (status) {
      BOOL isUnread = ([status rangeOfString:@"U"].location != NSNotFound);
      if (isUnread) [props addObject:kGDataMailItemIsUnread];
    }

    // other mobx status per http://wiki.dovecot.org/MailboxFormat/mbox
    NSString *xstatus = [EmUpUtilities stringForHeader:@"X-Status"
                                           fromHeaders:headers
                                             endOfLine:endOfLine];
    if (xstatus) {
      BOOL isFlagged = ([xstatus rangeOfString:@"F"].location != NSNotFound);
      if (isFlagged) [props addObject:kGDataMailItemIsStarred];

      BOOL isDeleted = ([xstatus rangeOfString:@"D"].location != NSNotFound);
      if (isDeleted) [props addObject:kGDataMailItemIsTrash];

      BOOL isDraft = ([xstatus rangeOfString:@"T"].location != NSNotFound);
      if (isDraft) [props addObject:kGDataMailItemIsDraft];
    }
  }

  if ([props count] > 0) return props;
  return nil;
}

- (void)setLastUploadedItem:(OutlineViewItemMBox *)item {
  [lastUploadedItem_ autorelease];
  lastUploadedItem_ = [item retain];
}

@end


// cribbed from GDataMIMEDocument
const char* memsearch(const char* needle, unsigned long long needleLen,
                      const char* haystack, unsigned long long haystackLen) {

  // This is a simple approach.  We start off by assuming that both memchr() and
  // memcmp are implemented efficiently on the given platform.  We search for an
  // instance of the first char of our needle in the haystack.  If the remaining
  // size could fit our needle, then we memcmp to see if it occurs at this point
  // in the haystack.  If not, we move on to search for the first char again,
  // starting from the next character in the haystack.
  const char* ptr = haystack;
  unsigned long long remain = haystackLen;
  while ((ptr = memchr(ptr, needle[0], remain)) != 0) {
    remain = haystackLen - (ptr - haystack);
    if (remain < needleLen) {
      return NULL;
    }
    if (memcmp(ptr, needle, needleLen) == 0) {
      return ptr;
    }
    ptr++;
    remain--;
  }
  return NULL;
}
