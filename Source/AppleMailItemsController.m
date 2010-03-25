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

#import "AppleMailItemsController.h"
#import "EmUpConstants.h"
#import "EmUpUtilities.h"

@interface AppleMailItemsController (PrivateMethods)
- (void)loadMailItems;
- (NSArray *)propertiesForDictionary:(NSDictionary *)plist;
- (NSCharacterSet *)whitespaceAndNumbersSet;
- (GDataEntryMailItem *)mailItemEntryForAppleMailPath:(NSString *)path
                                          mailboxName:(NSString *)mailboxName
                                              message:(NSMutableString *)emlxString;
- (GDataEntryMailItem *)mailItemEntryForMaildirPath:(NSString *)path
                                        mailboxName:(NSString *)mailboxName
                                            message:(NSMutableString *)emlxString;
- (void)insertExternalPartFilesForMessagePath:(NSString *)path
                                  messageText:(NSMutableString *)emlxString
                                      headers:(NSString *)headers;  
- (void)setLastUploadedItem:(OutlineViewItemApple *)item;
@end


@implementation OutlineViewItemApple

- (void)dealloc {
  [emlxPaths_ release];
  [super dealloc]; 
}

- (void)setEmlxPaths:(NSArray *)paths {
  [emlxPaths_ autorelease];
  emlxPaths_ = [paths mutableCopy];
}

- (NSArray *)emlxPaths {
  return emlxPaths_;
}

- (void)addEmlxPath:(NSString *)path {
  if (emlxPaths_ == nil) {
    emlxPaths_ = [[NSMutableArray alloc] init];
  }
  [emlxPaths_ addObject:path];
}

@end

@implementation AppleMailItemsController

- (id)initWithMailFolderPath:(NSString *)path 
                    rootName:(NSString *)rootName
                   isMaildir:(BOOL)isMaildir {
  self = [super init];
  if (self) {
    mailFolderPath_ = [path copy];
    rootName_ = [rootName copy];
    isMaildir_ = isMaildir;

    [self loadMailItems];
  }
  return self;
}

- (void)dealloc {
  [mailFolderPath_ release];
  [rootName_ release];
  [rootItem_ release];
  [lastUploadedItem_ release];
  [super dealloc];
}

#pragma mark -

- (OutlineViewItem *)rootItem {
  return rootItem_;
}

- (NSString *)mailFolderPath {
  return mailFolderPath_; 
}

- (void)loadMailItems {
  // build a dictionary for all mailboxes
  NSFileManager *fileMgr = [NSFileManager defaultManager];

  // mailFolderPath_ is typically @"~/Library/Mail"
  NSString *appleMailPath = [mailFolderPath_ stringByStandardizingPath];

  BOOL isDir = NO;
  if (![fileMgr fileExistsAtPath:appleMailPath isDirectory:&isDir] || !isDir) {
    // no Mail.app mail folder found, so leave the root item ivar nil
    return;
  }

  rootItem_ = [[OutlineViewItemApple itemWithName:rootName_
                                            level:0] retain];
  OutlineViewItemApple *lastOutlineItem = rootItem_;

  // every 0.2 seconds we'll send a notification with the name of the mailbox
  // being parsed so the user knows we're making progress
  NSDate *lastDisplayDate = [NSDate date];

  // make a map of partial mailbox folder paths to already-created outline items
  NSMutableDictionary *itemMap = [NSMutableDictionary dictionaryWithObject:rootItem_
                                                                    forKey:@""];

  // step through all files and directories
  NSDirectoryEnumerator *enumerator = [fileMgr enumeratorAtPath:appleMailPath];
  NSString *partialPath;
  while ((partialPath = [enumerator nextObject]) != nil) {

    // only look in IMAP, POP, and Mailboxes for Mail.app
    if (!isMaildir_
        && ![partialPath hasPrefix:@"IMAP-"]
        && ![partialPath hasPrefix:@"POP-"]
        && ![partialPath hasPrefix:@"Exchange IMAP-"]
        && ![partialPath hasPrefix:@"EWS-"]
        && ![partialPath hasPrefix:@"Mailboxes"]) {

      [enumerator skipDescendents];
      continue;
    }

    NSDictionary *pathAttrs = [enumerator fileAttributes];

    NSString *fullPath = [appleMailPath stringByAppendingPathComponent:partialPath];

    NSString *partialPathParent = [partialPath stringByDeletingLastPathComponent];

    BOOL isDir = [[pathAttrs objectForKey:NSFileType] isEqual:NSFileTypeDirectory];

    NSString *lastPathComponent = [partialPath lastPathComponent];

    // skip invisible items for Mail.app
    if (!isMaildir_
        && [lastPathComponent hasPrefix:@"."]) {
      if (isDir) [enumerator skipDescendents];
      continue;
    }

    // only look in cur, new, and . (invisible) directories for Maildir
    if (isMaildir_
        && isDir
        && ![lastPathComponent isEqual:@"cur"]
        && ![lastPathComponent isEqual:@"new"]
        && ![lastPathComponent hasPrefix:@"."]) {
      [enumerator skipDescendents];
      continue;
    }

    if (isDir && ![[partialPath lastPathComponent] isEqual:@"Messages"]) {
      // this is a folder (but not a Messages folder containing actual message
      // files) inside of the user-visible mailbox folders; add this path to the
      // tree as an outline item

      OutlineViewItemApple *dirItem = [itemMap objectForKey:partialPath];
      if (dirItem == nil) {

        // new (not before seen) directory; create the outline item, store it in
        // the map, and save it as a child of its parent

        NSArray *partialPathParts = [partialPath componentsSeparatedByString:@"/"];
        int level = [partialPathParts count];

        NSString *partName = [partialPath lastPathComponent];

        if (isMaildir_) {
          // the Maildir mailbox named "cur" should have its parent
          // directory name; the one named "new" we'll call "mailbox-new"
          // to distinguish it from the cur mailbox
          //
          // Use the full path's parent, since the partial path will have
          // no parent above the top-level "cur" and "new"
          NSString *mailboxName = [[fullPath stringByDeletingLastPathComponent] lastPathComponent];

          if ([mailboxName length] == 0) {
            // top-level of hard drive; avoid an empty mailbox name
            mailboxName = @"Maildir";
          }
          
          if ([partName isEqual:@"cur"]) {
            partName = mailboxName;
          } else if ([partName isEqual:@"new"]) {
            partName = [NSString stringWithFormat:@"%@-%@",
                        mailboxName, @"new"];
          }

          // maildir++ mailboxes may begin with dots, which is ugly, so
          // remove the leading dot
          if ([partName hasPrefix:@"."]) {
            partName = [partName substringFromIndex:1];
          }
        } else {
          // Apple Mail

          // when we display the name or make a label, we don't want the
          // mbox or imapmbox filename extensions shown
          NSString *partExtn = [partName pathExtension];
          if ([partExtn isEqual:@"imapmbox"] || [partExtn isEqual:@"mbox"]) {
            partName = [partName stringByDeletingPathExtension];
          }
        }

        dirItem = [OutlineViewItemApple itemWithName:partName level:level];
        [itemMap setObject:dirItem forKey:partialPath];

        OutlineViewItemApple *parentItem = [itemMap objectForKey:partialPathParent];

        NSAssert1(parentItem != nil, @"missing parent for %@", partialPath);
        [parentItem addChild:dirItem];

        // add this to the linked list of outline items
        [lastOutlineItem setNextOutlineItem:dirItem];
        lastOutlineItem = dirItem;

      } else {
        // we've seen this directory before; no need to create another outline
        // item for it
      }
    } else if (!isDir
           && ![lastPathComponent isEqual:@".DS_Store"]
           && (isMaildir_ || [[partialPath pathExtension] isEqual:@"emlx"])) {
      // this is an e-mail message file; for Mail.app, it's inside a Messages
      // folder and has the emlx extension

      // skip misc non-message Maildir files, including invisible files
      if (isMaildir_
          && ([lastPathComponent isEqual:@"bulletintime"]
              || [lastPathComponent isEqual:@"bulletinlock"]
              || [lastPathComponent isEqual:@"seriallock"]
              || [lastPathComponent isEqual:@"courierimapacl"]
              || [lastPathComponent isEqual:@"courierimapuiddb"]
              || [lastPathComponent hasPrefix:@"."])) {
        continue;
      }

      // display the partialPath of the folder containing these email addresses
      // if it's it's been 0.2 seconds since the last display
      if ([lastDisplayDate timeIntervalSinceNow] < -0.2) {
        lastDisplayDate = [NSDate date];
        [[NSNotificationCenter defaultCenter] postNotificationName:kEmUpLoadingMailbox
                                                            object:fullPath];
      }

      // add this message file path to its parent's list of messages, and update
      // the parent's count of messages
      OutlineViewItemApple *parentItem;
      if (isMaildir_) {
        parentItem = [itemMap objectForKey:partialPathParent];
      } else {
        // ignore the Messages folder in Apple Mail's path
        NSString *parentPartialPathWithoutMessages = [partialPathParent stringByDeletingLastPathComponent];
        parentItem = [itemMap objectForKey:parentPartialPathWithoutMessages];
      }

      NSAssert1(parentItem != nil, @"missing parent for %@", partialPath);

      [parentItem addEmlxPath:fullPath];
      [parentItem setNumberOfMessages:[[parentItem emlxPaths] count]];
    }
  }

  // default all found mailboxes to be checked
  [rootItem_ setState:NSOnState];

  // clear the name of the mailbox being loaded
  [[NSNotificationCenter defaultCenter] postNotificationName:kEmUpLoadingMailbox
                                                      object:@""];
}

- (unsigned int)countSelectedMessages {
  
  unsigned int count = [rootItem_ recursiveNumberOfCheckedMessages];  
  return count;
}


- (void)resetUpload {
  [self setLastUploadedItem:nil];
}

- (GDataEntryMailItem *)nextUploadItem {
  // find the next view item to upload


  if (lastUploadedItem_ == nil) {
    // starting from scratch
    [self setLastUploadedItem:[rootItem_ nextOutlineItem]];
    lastUploadedIndex_ = -1;
  }

  while (lastUploadedItem_ != nil) {

    NSString *mailboxName = [lastUploadedItem_ name];

    // each item has an array of message file paths (emlx files)
    NSArray *emlxPaths = [lastUploadedItem_ emlxPaths];
    ++lastUploadedIndex_;

    BOOL didExhaustFolder = (lastUploadedIndex_ >= [emlxPaths count]);
    if (didExhaustFolder) {
      // move to next folder item
      [self setLastUploadedItem:[lastUploadedItem_ nextOutlineItem]];
      lastUploadedIndex_ = -1;

    } else {

      NSCellStateValue state = [lastUploadedItem_ state];
      if (state != NSOffState) {

        // there's a message path; read in the e-mail message
        NSError *error = nil;
        NSString *errorMsg = nil;

        NSString *path = [emlxPaths objectAtIndex:lastUploadedIndex_];

        // the message path-index property will have the message path and
        // index, but there's only one message per file for Mail.app, so the
        // index is always zero

        NSMutableString *emlxString;
        emlxString = [NSMutableString stringWithContentsOfFile:path
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
        if ([error code] == NSFileReadInapplicableStringEncodingError
            && [[error domain] isEqual:NSCocoaErrorDomain]) {

          // try another encoding. I'm not sure why it's sometimes Latin-1
          emlxString = [NSMutableString stringWithContentsOfFile:path
                                                        encoding:NSISOLatin1StringEncoding
                                                           error:&error];
        }

        if (!emlxString) {
          // can't allocate string
          errorMsg = [error description];
        } else if ([emlxString length] == 0
                   || [emlxString length] >= kMaxMesssageSize) {
          errorMsg = @"message size invalid";
        } else if (isMaildir_) {

          GDataEntryMailItem *entry;
          entry = [self mailItemEntryForMaildirPath:path
                                        mailboxName:mailboxName
                                            message:emlxString];
          return entry;

        } else {

          GDataEntryMailItem *entry;
          entry = [self mailItemEntryForAppleMailPath:path
                                          mailboxName:mailboxName
                                              message:emlxString];
          return entry;
        }

        // report that we had to skip this message, then continue on to find
        // another
        NSRange msgRange = NSMakeRange(0, [emlxString length]);

        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                              path, kEmUpMessagePathKey,
                              [NSNumber numberWithInt:0], kEmUpMessageIndexKey,
                              [NSValue valueWithRange:msgRange], kEmUpMessageRangeKey,
                              errorMsg, kEmUpMessageErrorStringKey,
                              nil];

        [[NSNotificationCenter defaultCenter] postNotificationName:kEmUpMessageParsingFailed
                                                            object:dict];
      }
    }
  }

  return nil;
}

- (GDataEntryMailItem *)mailItemEntryForAppleMailPath:(NSString *)path
                                          mailboxName:(NSString *)mailboxName
                                              message:(NSMutableString *)emlxString {
  // we'll consider a message to be Apple Mail style if the first
  // line is just length and whitespace
  BOOL isAppleMailMessage = NO;

  NSRange completeMsgRange = NSMakeRange(0, [emlxString length]);

  // delete the body length numbers, up to the first newline. The body
  // length number is in terms of bytes rather than characters, so it's
  // not useful in navigating a unicode string, anyway
  NSRange firstNewlineRange = [emlxString rangeOfString:@"\n"];
  if (firstNewlineRange.length > 0) {
    NSRange prefixRange = NSMakeRange(0, firstNewlineRange.location + 1);

    // ensure that the first line is only whitespace and numbers; if it's
    // not, this isn't really an Apple mail message, so we'll treat it
    // more generically
    NSCharacterSet *wsNumSet = [self whitespaceAndNumbersSet];
    NSString *firstLine = [emlxString substringWithRange:prefixRange];

    // trimming is a convenient way to determine if the line has
    // any characters not in the set
    NSString *trimmedFirstLine = [firstLine stringByTrimmingCharactersInSet:wsNumSet];
    if ([trimmedFirstLine length] == 0) {
      // delete the first line, including the trailing return
      [emlxString deleteCharactersInRange:prefixRange];
      isAppleMailMessage = YES;
    }
  }

  // save the plist at the end, and delete it from the message string
  NSString *plistStr = nil;
  if (isAppleMailMessage) {
    NSString *const suffix = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>";
    NSRange suffixRange = [emlxString rangeOfString:suffix
                                            options:NSBackwardsSearch];
    if (suffixRange.length > 0) {
      unsigned int loc = suffixRange.location;
      NSRange fullSuffixRange = NSMakeRange(loc, [emlxString length] - loc);
      plistStr = [emlxString substringWithRange:fullSuffixRange];
      [emlxString deleteCharactersInRange:fullSuffixRange];
    }

    // something's wrong if we don't have a plist
    if ([plistStr length] == 0) {
      NSLog(@"cannot find message properties for %@", path);
    }
  }

  // fix up message headers, if necessary
  NSString *newStr;
  newStr = [EmUpUtilities messageTextWithAlteredHeadersForMessageText:emlxString
                                                            endOfLine:@"\n"];
  [emlxString setString:newStr];
  
  NSString *headers = [EmUpUtilities headersForMessageText:emlxString
                                                 endOfLine:@"\n"];
  if (headers == nil) {
    NSLog(@"could not find headers in message file: %@", path);
  } else {
    // add emlxpart files where the enclosures are missing from the emlx file
    [self insertExternalPartFilesForMessagePath:path
                                    messageText:emlxString
                                        headers:headers];  
  }
  
  GDataEntryMailItem *entry = [GDataEntryMailItem mailItemWithRFC822String:emlxString];

  [entry setProperty:mailboxName
              forKey:kEmUpMailboxNameKey];

  [entry setProperty:path
              forKey:kEmUpMessagePathKey];

  [entry setProperty:[NSNumber numberWithInt:0]
              forKey:kEmUpMessageIndexKey];

  [entry setProperty:[NSValue valueWithRange:completeMsgRange]
              forKey:kEmUpMessageRangeKey];

  NSString *messageID = [EmUpUtilities stringForHeader:@"Message-ID"
                                           fromHeaders:headers
                                             endOfLine:@"\n"];
  if (messageID) {
    [entry setProperty:messageID
                forKey:kEmUpMessageIDKey];
  }

  // emlx flags: http://mike.laiosa.org/blog/emlx.html
  if (plistStr != nil) {
    NSDictionary *plist = nil;
    @try {
      plist = [plistStr propertyList]; // throws when cranky
    }
    @catch (NSException *exception) {
      NSLog(@"Property list parsing: %@\nException: %@\n%@",
            path, exception, plistStr);
    }

    if (plist) {
      NSArray *props = [self propertiesForDictionary:plist];
      if ([props count] > 0) {
        [entry setProperty:props
                    forKey:kEmUpMailboxPropertiesKey];
      }
    }
  }

  // done
  return entry;
}

- (NSArray *)propertiesForDictionary:(NSDictionary *)plist {

  NSMutableArray *props = [NSMutableArray array];

  NSNumber *flagsNum = [plist objectForKey:@"flags"];

  if (flagsNum != nil) {
    unsigned long flags = [flagsNum unsignedIntValue];

    BOOL isRead = ((flags & (1L << 0)) != 0);
    if (!isRead) [props addObject:kGDataMailItemIsUnread];

    BOOL isDeleted = ((flags & (1L << 1)) != 0);
    if (isDeleted) [props addObject:kGDataMailItemIsTrash];

    BOOL isFlagged = ((flags & (1L << 4)) != 0);
    if (isFlagged) [props addObject:kGDataMailItemIsStarred];

    BOOL isDraft = ((flags & (1L << 6)) != 0);
    if (isDraft) [props addObject:kGDataMailItemIsDraft];
  }
  return props;
}


- (GDataEntryMailItem *)mailItemEntryForMaildirPath:(NSString *)path
                                        mailboxName:(NSString *)mailboxName
                                            message:(NSMutableString *)emlxString {

  // fix up message headers if necessary
  NSString *newStr;
  newStr = [EmUpUtilities messageTextWithAlteredHeadersForMessageText:emlxString
                                                            endOfLine:@"\n"];
  [emlxString setString:newStr];

  GDataEntryMailItem *entry = [GDataEntryMailItem mailItemWithRFC822String:emlxString];

  [entry setProperty:mailboxName
              forKey:kEmUpMailboxNameKey];

  [entry setProperty:path
              forKey:kEmUpMessagePathKey];

  [entry setProperty:[NSNumber numberWithInt:0]
              forKey:kEmUpMessageIndexKey];

  NSRange msgRange = NSMakeRange(0, [emlxString length]);
  [entry setProperty:[NSValue valueWithRange:msgRange]
              forKey:kEmUpMessageRangeKey];

  NSString *headers = [EmUpUtilities headersForMessageText:emlxString
                                                 endOfLine:@"\n"];
  if (headers == nil) {
    NSLog(@"could not find headers in message file: %@", path);
  }

  NSString *messageID = [EmUpUtilities stringForHeader:@"Message-ID"
                                           fromHeaders:headers
                                             endOfLine:@"\n"];
  if (messageID) {
    [entry setProperty:messageID
                forKey:kEmUpMessageIDKey];
  }

  // Maildir flags follow the "2," in the message filename, per
  // http://cr.yp.to/proto/maildir.html
  //
  // for example: 1146378234.000029.mbox:2,RS
  NSString *filename = [path lastPathComponent];
  NSRange flagsStartRange = [filename rangeOfString:@"2,"
                                            options:NSBackwardsSearch];

  if (flagsStartRange.location != NSNotFound) {
    unsigned int flagsOffset = NSMaxRange(flagsStartRange);
    if (flagsOffset < [filename length]) {

      // make a string with just the flags
      NSString *flagsStr = [filename substringFromIndex:flagsOffset];

      NSMutableArray *props = [NSMutableArray array];

      BOOL isSeen = ([flagsStr rangeOfString:@"S"].location != NSNotFound);
      if (!isSeen) [props addObject:kGDataMailItemIsUnread];

      BOOL isTrashed = ([flagsStr rangeOfString:@"T"].location != NSNotFound);
      if (isTrashed) [props addObject:kGDataMailItemIsTrash];

      BOOL isFlagged = ([flagsStr rangeOfString:@"F"].location != NSNotFound);
      if (isFlagged) [props addObject:kGDataMailItemIsStarred];

      BOOL isDraft = ([flagsStr rangeOfString:@"D"].location != NSNotFound);
      if (isDraft) [props addObject:kGDataMailItemIsDraft];

      if ([props count] > 0) {
        [entry setProperty:props forKey:kEmUpMailboxPropertiesKey];
      }
    }
  }

  // done
  return entry;
}

// this method scans multipart Mail.app emlx messages looking for parts
// lacking bodies but with non-zero X-Apple-Content-Length headers,
// and tries to read in a separate emlxpart file and insert
// it into emlxString as the missing part's body
//
// open question: does this apply only to message files ending in .partial.emlx
// or to all emlx files?
- (void)insertExternalPartFilesForMessagePath:(NSString *)path
                                  messageText:(NSMutableString *)emlxString
                                      headers:(NSString *)headers {

  // we care about files with content type multipart/mixed
  NSString *contentType = [EmUpUtilities stringForHeader:@"Content-Type"
                                             fromHeaders:headers
                                               endOfLine:@"\n"];
  if ([contentType hasPrefix:@"multipart/mixed;"]) {

    // scan to find the boundary separator of the emlx file's body parts
    NSString *boundary = nil;
    NSScanner *headerScanner = [NSScanner scannerWithString:contentType];
    if ([headerScanner scanUpToString:@"boundary=" intoString:nil]
        && [headerScanner scanString:@"boundary=" intoString:nil]
        && [headerScanner scanUpToString:@"\n" intoString:&boundary]) {

      // there is a boundary; search for a section which has no header
      //
      // boundaries start with -- and end with \n (or --\n at the end of file)
      NSString *normalBoundary = [NSString stringWithFormat:@"--%@", boundary];

      NSCharacterSet *wsSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];

      NSScanner *bodyScanner = [NSScanner scannerWithString:emlxString];
      [bodyScanner setScanLocation:[headers length]];

      unsigned int partCounter = 0;

      while (1) {
        // find the start of the next part
        partCounter++;

        if ([bodyScanner scanString:normalBoundary intoString:nil]) {

          // the last boundary is followed by "--" rather than a newline
          if ([bodyScanner scanString:@"--" intoString:nil]) {
            // we're done with this message
            break;
          }

          // scan up to the next boundary to suck in all of this part
          NSString *partStr = nil;
          unsigned int partLocation = [bodyScanner scanLocation];

          if ([bodyScanner scanUpToString:normalBoundary intoString:&partStr]) {
            // make a "message" from this part's headers and body, and
            // determine if Apple's header says the content has a length but
            // the body is empty
            NSString *partHeaders;
            NSString *appleContentLen;

            partHeaders = [EmUpUtilities headersForMessageText:partStr
                                                     endOfLine:@"\n"];
            appleContentLen = [EmUpUtilities stringForHeader:@"X-Apple-Content-Length"
                                                 fromHeaders:partHeaders
                                                   endOfLine:@"\n"];
            if ([appleContentLen intValue] > 0) {

              // determine if the body is empty
              unsigned int partHeaderLen = [partHeaders length];
              NSString *partBody = [partStr substringFromIndex:partHeaderLen];

              partBody = [partBody stringByTrimmingCharactersInSet:wsSet];
              if ([partBody length] == 0) {

                // this body is empty; determine if there's a emlxpart file
                // for this emlx file's missing part, like
                //
                //   emlx name:     9131.partial.emlx
                //   emlxpart name: 9131.4.emlxpart

                // get the first part of the emlxfile's name
                NSString *fileName = [path lastPathComponent];
                NSArray *fileNameParts = [fileName componentsSeparatedByString:@"."];
                if ([fileNameParts count] > 1) {
                  // form the part file name
                  NSString *baseName = [fileNameParts objectAtIndex:0];
                  NSString *const template = @"%@.%u.emlxpart";
                  NSString *partFileName = [NSString stringWithFormat:template,
                                            baseName, partCounter];
                  NSString *dirPath = [path stringByDeletingLastPathComponent];
                  NSString *partFilePath = [dirPath stringByAppendingPathComponent:partFileName];

                  // read in the part's enclosure file, if it's present
                  NSError *error = nil;
                  NSString *fileContents = [[[NSString alloc] initWithContentsOfFile:partFilePath
                                                                            encoding:NSUTF8StringEncoding
                                                                               error:&error] autorelease];
                  unsigned int partFileLen = [fileContents length];
                  if (partFileLen > 0
                    && ([emlxString length] + partFileLen) < kMaxMesssageSize) {
                    // insert the emlxpart as the body of the part's message
                    // (following the part's header and extra newline)
                    [emlxString insertString:fileContents
                                     atIndex:(partLocation + partHeaderLen + 1)];

                    // replace the scanner with one representing the overall
                    // message with the additional enclosure inserted
                    unsigned int oldLoc = [bodyScanner scanLocation];
                    unsigned int newLoc = oldLoc + partFileLen;

                    bodyScanner = [NSScanner scannerWithString:emlxString];
                    [bodyScanner setScanLocation:newLoc];
                  }
                }
              }
            }
          } else {
            // could not find the part end boundary; bail
            break;
          }
        } else {
          // could not find the part start boundary; bail
          break;
        }
      }
    }
  }
}

- (NSCharacterSet *)whitespaceAndNumbersSet {
  // make a set consisting only of numbers and whitespace, which we'll
  // use to test if the first line is Apple's message body length string
  static NSCharacterSet *wsAndNumbersSet = nil;
  if (wsAndNumbersSet == nil) {
    NSMutableCharacterSet *mutable = [[[NSMutableCharacterSet alloc] init] autorelease];

    [mutable formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [mutable formUnionWithCharacterSet:[NSCharacterSet decimalDigitCharacterSet]];
    wsAndNumbersSet = [mutable copy]; // make immutable for performance
  }
  return wsAndNumbersSet;
}

- (void)setLastUploadedItem:(OutlineViewItemApple *)item {
  [lastUploadedItem_ autorelease];
  lastUploadedItem_ = [item retain];
}

@end
