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

//
//  EmUpWindowController.m
//

#include <Carbon/Carbon.h>

#import "EmUpWindowController.h"
#import "GDataEntryMailItem.h"
#import "EmUpConstants.h"

NSString *const kTabViewItemSelection = @"Selection";
NSString *const kTabViewItemProgress = @"Progress";
NSString *const kTabViewItemSkipped = @"Skipped";

@interface EmUpWindowController (PrivateMethods)
- (GDataServiceGoogle *)service;

- (void)updateUI;
- (NSString *)displayTimeForSeconds:(unsigned int)seconds;

// "backing off" happens when we get a status 503 on an entry;
// delays happen normally to keep our upload throttled to
// 1 message per second (in slow upload mode)
- (void)uploadNow;
- (void)uploadMoreMessages;
- (void)uploadMoreMessagesAfterBackingOff;
- (void)uploadMoreMessagesAfterDelay:(NSTimeInterval)delay;
- (void)cancelUploadMoreMessagesAfterDelay;

- (void)uploadEntry:(GDataEntryMailItem *)entry;

// report one or many failues
- (void)handleFailedMessageForProperties:(NSDictionary *)propertyDicts;

- (NSString *)messageDisplayIDFromProperties:(NSDictionary *)properties;

- (void)rememberSkippedMessageWithProperties:(NSDictionary *)propertyDict;

- (void)resetUploading;
- (void)stopUploading;

- (GDataEntryMailItem *)nextEntryFromController:(id<MailItemController>)controller;

- (void)loadMailboxesForApplication;
- (unsigned int)countSelectedMessages;

// setters and getters for refcounted ivars
- (NSMutableArray *)uploadTickets;
- (void)setUploadTickets:(NSMutableArray *)array;

- (void)reportProgress:(NSString *)reportStr;
- (void)reportProgressWithTimestamp:(NSString *)reportStr;

- (NSString *)currentUploadingMailboxName;
- (void)setCurrentUploadingMailboxName:(NSString *)str;

- (void)setLastUploadDate:(NSDate *)date;

@end

@implementation EmUpWindowController

static EmUpWindowController* gEmUpWindowController = nil;

+ (EmUpWindowController *)sharedEmUpWindowController {

  if (!gEmUpWindowController) {
    gEmUpWindowController = [[EmUpWindowController alloc] init];
  }
  return gEmUpWindowController;
}


- (id)init {
  self = [self initWithWindowNibName:@"EmUpWindow"];
  if (self != nil) {
    entriesToRetry_ = [[NSMutableArray alloc] init];
    messageIDsUploaded_ = [[NSMutableDictionary alloc] init];
    uploadTickets_ = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)windowDidLoad {

  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self
         selector:@selector(mailboxLoadingNotification:)
             name:kEmUpLoadingMailbox
           object:nil];

  [nc addObserver:self
         selector:@selector(messageParsingFailedNotification:)
             name:kEmUpMessageParsingFailed
           object:nil];

  [self updateUI];

  // load standard mailboxes unless shift key is down
  UInt32 currentModifiers = GetCurrentKeyModifiers();
  BOOL isShiftKeyDown = ((currentModifiers & shiftKey) != 0);

  if (!isShiftKeyDown) {
    [self performSelector:@selector(loadMailboxesForApplication)
               withObject:nil
               afterDelay:0.1];
  }
}

- (void)awakeFromNib {
  [tabView_ selectTabViewItemWithIdentifier:kTabViewItemSelection];

  // Make a suggested custom e-mail label of "Uploaded 1/2/34" with today's
  // date, which is useful if the user wants to be able to select & delete these
  // uploads
  NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
  [dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];

  [dateFormatter setDateStyle:NSDateFormatterShortStyle];
  [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
  NSString *dateStr = [dateFormatter stringFromDate:[NSDate date]];

  NSString *template = NSLocalizedString(@"UploadDateTemplate", nil); // "Uploaded %@"
  NSString *suggestedLabel = [NSString stringWithFormat:template, dateStr];
  [additionalLabelField_ setStringValue:suggestedLabel];

  // normally we reset just before a new upload, but calling this from
  // awakeFromNib now will clear the skipped files pop-up menu of its nib-loaded
  // item
  [self resetUploading];

  [self updateUI];
}

- (void)dealloc {

  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [itemsControllers_ release];
  [currentUploadingMailboxName_ release];
  [entriesToRetry_ release];
  [messageIDsUploaded_ release];
  [lastUploadDate_ release];
  [uploadTickets_ release];
  [super dealloc];
}

#pragma mark -

// mailboxLoadingNotification: is invoked periodically when a mailbox item
// controller is reading in mail.  They post the notification about every 0.2
// seconds so the user can see roughly what's happening.
- (void)mailboxLoadingNotification:(NSNotification *)note {
  NSString *path = [note object];
  NSString *str = @"";
  if ([path length] > 0) {
    NSString *template = NSLocalizedString(@"LoadingTemplate", nil); // "Loading %@"
    str = [NSString stringWithFormat:template, path];
  }

  if (![[messagesTransferredField_ stringValue] isEqual:str]) {
    [messagesTransferredField_ setStringValue:str];
    [messagesTransferredField_ display];
  }
}

- (void)messageParsingFailedNotification:(NSNotification *)note {
  // this handles notifications from the item controllers when they
  // have to skip a message during uploading
  NSDictionary *propertyDict = [note object];

  [self handleFailedMessageForProperties:propertyDict];
}

- (void)updateUI {
  NSString *template = NSLocalizedString(@"MessagesSelectedTemplate", nil);
  unsigned int numberOfSelectedMessages = [self countSelectedMessages];
  NSString *str = [NSString stringWithFormat:template,
                   numberOfSelectedMessages];
  [messagesSelectedNumField_ setStringValue:str];

  BOOL hasStoppedUploading = (!isUploading_ && messagesUploadedCount_ > 0);

  if (isUploading_) {
    // we're uploading now
    unsigned int retryCount = [entriesToRetry_ count];
    template = NSLocalizedString(@"MessagesTransferredTemplate", nil); // "Messages transferred: %u/%u (%u to retry, %u skipped)"
    str = [NSString stringWithFormat:template,
           messagesUploadedCount_, numberOfSelectedMessages,
           retryCount, messagesSkippedCount_];

    [progressIndicator_ setMaxValue:(double)numberOfSelectedMessages];
    [progressIndicator_ setDoubleValue:(double)messagesUploadedCount_];
  } else {
    // not uploading
    str = @"";
  }
  [messagesTransferredField_ setStringValue:str];

  if (!isUploading_) {
    // once uploading is done, we leave visible the text indicating how much was
    // uploaded, but hide the progress indicator
    [progressIndicator_ stopAnimation:self];
    [progressIndicator_ setHidden:YES];
  } else {
    [progressIndicator_ startAnimation:self];
    [progressIndicator_ setHidden:NO];
  }

  // enable and disable UI controls
  BOOL hasEmail = [[usernameField_ stringValue] length] > 0;
  BOOL hasPassword = [[passwordField_ stringValue] length] > 0;

  BOOL isReadyToUpload = (!isLoadingMailboxes_ && (isPaused_ || !isUploading_));

  [uploadButton_ setEnabled:(isReadyToUpload && hasEmail && hasPassword)];
  [stopButton_ setEnabled:isUploading_];
  [pauseButton_ setEnabled:isUploading_ && !isPaused_];

  [outlineView_ setEnabled:!isUploading_];

  [maiboxNamesAsLabelsCheckbox_ setEnabled:(!isUploading_)];
  [preserveMailPropertiesCheckbox_ setEnabled:(!isUploading_)];
  [putAllMailInInboxCheckbox_ setEnabled:(!isUploading_)];
  [assignAdditionalLabelCheckbox_ setEnabled:(!isUploading_)];
  [additionalLabelField_ setEnabled:(!isUploading_)];

  [usernameField_ setEnabled:(!isUploading_)];
  [passwordField_ setEnabled:(!isUploading_)];

  [pausedMessageField_ setHidden:(!isPaused_)];
  if (isUploading_ && !isPaused_) {
    [spinner_ startAnimation:self];
  } else {
    [spinner_ stopAnimation:self];
  }

  // if there are no outline item controllers, tell the user to
  // pick a mail folder from the File menu
  template = NSLocalizedString(@"SelectMailboxes", nil); // "Select mailboxes to upload"
  NSString *outlineTitle = @"Select mailboxes to upload";
  if ([itemsControllers_ count] == 0) {
    outlineTitle = @"To select mailboxes to upload, choose \"Add Folder\" from the File menu";
  }
  [outlineViewTitle_ setStringValue:outlineTitle];
  [outlineViewTitle_ setHidden:isLoadingMailboxes_];

  // display the time estimate, assuming 1 second per 5 messages in
  // fast upload mode, with up to 500 messages uploaded in fast mode,
  // and 1 second per 1 message in slow upload mode
  //
  // The upload rate is a somewhat pessimistic wild guess, but trying to
  // measure and extrapolate based on uploads so far would be hard
  // (dealing with pauses and so forth), and for any substantial uploads
  // the slow upload rate will dominate the total anyway.

  unsigned int fastMsgs = MIN(numberOfSelectedMessages, kFastModeMaxMessages);
  unsigned int fastMsgsRemaining = isSlowUploadMode_ ? 0 : (fastMsgs - messagesUploadedCount_);

  unsigned int fastSeconds = (unsigned int) ((NSTimeInterval)fastMsgsRemaining * kFastUploadInterval);

  unsigned int slowMsgs = MAX(numberOfSelectedMessages - fastMsgs, 0);
  unsigned int slowMsgsRemaining = !isSlowUploadMode_ ?
    slowMsgs : MAX((slowMsgs - (messagesUploadedCount_ - fastMsgs)), 0);

  unsigned int totalSeconds = fastSeconds + slowMsgsRemaining;
  NSString *estTimeStr = [self displayTimeForSeconds:totalSeconds];
  NSString *estKey = isUploading_ ? 
    @"TimeRemainingTemplate" // "Estimated time remaining: %@"
    :  @"TimeToUploadTemplate"; // "Estimated time to upload: %@"
  template = NSLocalizedString(estKey, nil);
  NSString *estDisplayStr = [NSString stringWithFormat:template, estTimeStr];

  [uploadTimeEstimateField_ setStringValue:estDisplayStr];
  [uploadTimeEstimateField_ setHidden:(hasStoppedUploading || numberOfSelectedMessages == 0)];

  // set the number of skipped messages into the tab title so it's more obvious
  // to users when it's useful to look at the tab
  int numberOfSkippedMenuItems = [skippedMessagePopup_ numberOfItems];
  int skippedTabItemIndex = [tabView_ indexOfTabViewItemWithIdentifier:kTabViewItemSkipped];
  NSTabViewItem *skippedTabItem = [tabView_ tabViewItemAtIndex:skippedTabItemIndex];
  NSString *skippedTitle = NSLocalizedString(@"SkippedMessages", nil);
  if (numberOfSkippedMenuItems > 0) {
    template = NSLocalizedString(@"SkippedMessagesNum", nil);
    skippedTitle = [NSString stringWithFormat:template,
                    numberOfSkippedMenuItems];
  }
  [skippedTabItem setLabel:skippedTitle];
}

- (NSString *)displayTimeForSeconds:(unsigned int)seconds {
  NSString *template;

  if (seconds < 45) {
    // "Under a minute"
    template = NSLocalizedString(@"TimeRemainingUnderAMinute", nil);
    return template;
  }

  if (seconds < 120) {
    // "About a minute"
    template = NSLocalizedString(@"TimeRemainingAboutAMinute", nil);
    return template;
  }

  unsigned int min = seconds / 60;
  if (min < 60) {
    // minutes, "%um"
    template = NSLocalizedString(@"TimeRemainingMinutes", nil);
    return [NSString stringWithFormat:template, min];
  }

  // hours minutes, "%uh %um"
  unsigned int hours = min / 60;
  unsigned int minRemainder = min - hours * 60;
  template = NSLocalizedString(@"TimeRemainingHoursMins", nil);
  return [NSString stringWithFormat:template, hours, minRemainder];
}

- (unsigned int)countSelectedMessages {
  unsigned int count = 0;

  id<MailItemController> itemController;

  GDATA_FOREACH(itemController, itemsControllers_) {
    count += [itemController countSelectedMessages];
  }
  return count;
}

// beginningLoadingMailboxes and endingLoadingMailboxes are called before and
// after each top-level outline view item controller (like for Apple Mail or
// Eudora) parses the mail in its folder
- (void)beginningLoadingMailboxes {
  isLoadingMailboxes_ = YES;
  [self updateUI];

  [progressIndicator_ setIndeterminate:YES];
  [progressIndicator_ setHidden:NO];
  [progressIndicator_ setUsesThreadedAnimation:YES];
  [progressIndicator_ startAnimation:self];

  // disable all the controls while we load the mailboxes
  [[self window] display];
}

- (void)endingLoadingMailboxes {
  [progressIndicator_ stopAnimation:self];
  [progressIndicator_ setHidden:YES];
  [progressIndicator_ setIndeterminate:NO];

  isLoadingMailboxes_ = NO;

  [self updateUI];
}

// loadMailboxesForApplication steps through the standard mailboxes (Apple Mail,
// Eudora, and each profile for Thunderbird), creates an outline item controller
// for each, and begins them loading mail
- (void)loadMailboxesForApplication {

  NSFileManager *fileMgr = [NSFileManager defaultManager];

  NSAssert(itemsControllers_ == nil, @"app mailboxes reloaded");

  itemsControllers_ = [[NSMutableArray alloc] init];

  // set up the UI
  [self beginningLoadingMailboxes];

  // create an item controller for Mail.app
  NSString *appleMailPath = [@"~/Library/Mail" stringByStandardizingPath];
  NSString *rootNameStr;
  if ([fileMgr fileExistsAtPath:appleMailPath]) {

    AppleMailItemsController *appleMail;
    rootNameStr = NSLocalizedString(@"AppleMail", nil); // "Apple Mail"
    appleMail = [[[AppleMailItemsController alloc] initWithMailFolderPath:appleMailPath
                                                                 rootName:rootNameStr
                                                                isMaildir:NO] autorelease];
    [itemsControllers_ addObject:appleMail];

    [outlineView_ reloadData];
    [outlineView_ display];
  }

  // make a controller for the Eudora folder
  NSString *eudoraPath = [@"~/Eudora Folder/Mail Folder" stringByStandardizingPath];
  MBoxItemsController *mbox;
  if ([fileMgr fileExistsAtPath:eudoraPath]) {

    rootNameStr = NSLocalizedString(@"Eudora", nil); // "Eudora"
    mbox = [[[MBoxItemsController alloc] initWithMailFolderPath:eudoraPath
                                                       rootName:rootNameStr] autorelease];
    [itemsControllers_ addObject:mbox];

    [outlineView_ reloadData];
    [outlineView_ display];
  }

  // make a controller for each thunderbird profile
  NSString *tbirdProfilesPath = [@"~/Library/Thunderbird/Profiles" stringByStandardizingPath];
  NSArray *tbirdProfiles = [fileMgr directoryContentsAtPath:tbirdProfilesPath];

  NSString *profileName;
  GDATA_FOREACH(profileName, tbirdProfiles) {
    if (![profileName hasPrefix:@"."]) {
      // thunderbird profiles are eight gibberish characters and a dot before
      // the profile name
      NSString *displayName = profileName;
      NSString *shorterName = nil;

      NSScanner *scanner = [NSScanner scannerWithString:profileName];
      if ([scanner scanUpToString:@"." intoString:nil]
          && [scanner scanString:@"." intoString:nil]
          && [scanner scanUpToString:@"\n" intoString:&shorterName]
          && [shorterName length] > 0) {

        displayName = shorterName;
      }

      rootNameStr = NSLocalizedString(@"ThunderbirdTemplate", nil);
      NSString *tbirdRootName = [NSString stringWithFormat:rootNameStr,
                                 displayName];
      NSString *tbirdProfilePath = [tbirdProfilesPath stringByAppendingPathComponent:profileName];

      // inside the profile directory is a Mail directory
      NSString *tbirdMailPath = [tbirdProfilePath stringByAppendingPathComponent:@"Mail"];
      if ([fileMgr fileExistsAtPath:tbirdMailPath]) {

        mbox = [[[MBoxItemsController alloc] initWithMailFolderPath:tbirdMailPath
                                                           rootName:tbirdRootName] autorelease];
        [itemsControllers_ addObject:mbox];

        [outlineView_ reloadData];
        [outlineView_ display];
      }
    }
  }

  [self endingLoadingMailboxes];
}

// addMailboxes is sent by menu items with a tag of 0 (Apple) or 1 (mbox)
- (IBAction)addMailboxes:(id)sender {

  if (isUploading_) return;

  int tag = [sender tag];

  NSOpenPanel *panel = [NSOpenPanel openPanel];

  [panel setCanChooseDirectories:YES];
  [panel setCanChooseFiles:NO];
  [panel setPrompt:NSLocalizedString(@"SelectButton", nil)]; // "Select"
  [panel setMessage:NSLocalizedString(@"SelectTitle", nil)]; // "Select Mail Directory"

  [panel beginSheetForDirectory:nil
                           file:nil
                 modalForWindow:[self window]
                  modalDelegate:self
                 didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:)
                    contextInfo:(void *)tag];
}

- (void)openPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode  contextInfo:(void  *)contextInfo {

  if (returnCode != NSOKButton) return;

  enum {
    // kinds of mail folders
    kAppleMailTag = 0,
    kMBoxTag = 1,         // mbox files
    kMaildirTag = 2       // Maildir directories and dot subdirectories
  };

  int tag = (int)contextInfo;

  NSString *path = [panel filename];
  NSString *shortPath = [path stringByAbbreviatingWithTildeInPath];
  NSString *longPath = [path stringByStandardizingPath];

  [self beginningLoadingMailboxes];

  // the user picked a menu item for adding new mail directories to scan
  NSString *template;
  switch(tag) {

    case kAppleMailTag: {
      template = NSLocalizedString(@"AppleMailPathTemplate", nil); // "Apple Mail - %@"
      NSString *appleRootName = [NSString stringWithFormat:template, shortPath];

      AppleMailItemsController *appleMail;
      appleMail = [[[AppleMailItemsController alloc] initWithMailFolderPath:longPath
                                                                   rootName:appleRootName
                                                                  isMaildir:NO] autorelease];
      [itemsControllers_ addObject:appleMail];
      break;
    }

    case kMBoxTag: {
      template = NSLocalizedString(@"MBoxPathTemplate", nil); // "MBox - %@"
      NSString *macRootName = [NSString stringWithFormat:template, shortPath];
      MBoxItemsController *mbox;
      mbox = [[[MBoxItemsController alloc] initWithMailFolderPath:longPath
                                                         rootName:macRootName] autorelease];
      [itemsControllers_ addObject:mbox];
      break;
    }

    case kMaildirTag: {
      template = NSLocalizedString(@"MaildirPathTemplate", nil); // "Maildir - %@"
      NSString *appleRootName = [NSString stringWithFormat:template, shortPath];

      AppleMailItemsController *maildirController;
      maildirController = [[[AppleMailItemsController alloc] initWithMailFolderPath:longPath
                                                                           rootName:appleRootName
                                                                          isMaildir:YES] autorelease];
      [itemsControllers_ addObject:maildirController];
      break;
    }

    default:
      break;
  }

  [outlineView_ reloadData];
  [outlineView_ display];

  [self endingLoadingMailboxes];
}

#pragma mark IBActions

- (IBAction)uploadClicked:(id)sender {

  NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

  // normalize the username field
  NSString *username = [usernameField_ stringValue];
  username = [username stringByTrimmingCharactersInSet:whitespace];

  [usernameField_ setStringValue:username];

  // reset first responder to lock in changes to the "additional label" field's
  // text before the field is disabled, as disabling causes changes to be
  // discarded if the text field is active
  [[self window] makeFirstResponder:nil];
  
  NSString *lowercaseName = [username lowercaseString];
  if ([lowercaseName hasSuffix:@"gmail.com"]
      || [lowercaseName hasSuffix:@"@googlemail.com"]) {

    // "Uploading to Gmail accounts is not supported"
    NSString *errorMsg = NSLocalizedString(@"GmailAcctErr", nil);
    NSString *errorTitle = NSLocalizedString(@"ErrorTitle", nil); // "Error"

    NSBeginAlertSheet(errorTitle, nil, nil, nil,
                      [self window], self, NULL,
                      nil, nil, errorMsg);
  } else {
    [self uploadNow];
  }
}

- (IBAction)stopClicked:(id)sender {
  // "Messages transferred: %u/%u  Skipped: %u"
  NSString *template = NSLocalizedString(@"UploadingEndCountTemplate", nil);
  NSString *str = [NSString stringWithFormat:template,
                   messagesUploadedCount_, [self countSelectedMessages],
                   messagesSkippedCount_];
  [self reportProgress:str];

  str = NSLocalizedString(@"UploadingStopped", nil);
  NSString *separator = NSLocalizedString(@"StatusSeparator", nil);
  [self reportProgressWithTimestamp:str];
  [self reportProgress:separator];
  [self stopUploading];
}

- (IBAction)pauseClicked:(id)sender {
  NSString *str = NSLocalizedString(@"UploadingPaused", nil);
  [self reportProgressWithTimestamp:str];
  isPaused_ = YES;

  // purge any pending upload invocation
  [self cancelUploadMoreMessagesAfterDelay];

  [self updateUI];
}

- (IBAction)skippedMessageClicked:(id)sender {
  // get the properties for the message from the selected
  // pop-up menu item
  NSDictionary *props = [[skippedMessagePopup_ selectedItem] representedObject];

  // display the file path and error string for this message
  NSString *filePath = [props objectForKey:kEmUpMessagePathKey];
  [skippedMessagePathField_ setStringValue:filePath];

  NSString *errorStr = [props objectForKey:kEmUpMessageErrorStringKey];
  if (errorStr) {
    [skippedMessageErrorField_ setStringValue:errorStr];
  }

  NSRange range = [[props objectForKey:kEmUpMessageRangeKey] rangeValue];

  [skippedMessageTextView_ setString:@""];

  // open the file memory-mapped, read in the message, store the message
  // in the text view
  NSData *fileData = [NSData dataWithContentsOfMappedFile:filePath];
  if (fileData) {
    unsigned int dataLen = [fileData length];
    const char *fileDataPtr = [fileData bytes];
    const char *messagePtr = fileDataPtr + range.location;

    if (dataLen >= NSMaxRange(range)) {

      NSString *messageText = [[[NSString alloc] initWithBytes:(void *)messagePtr
                                                        length:range.length
                                                      encoding:NSUTF8StringEncoding] autorelease];
      if (messageText == nil) {
        // try MacRoman encoding
        messageText = [[[NSString alloc] initWithBytes:(void *)messagePtr
                                                length:range.length
                                              encoding:NSMacOSRomanStringEncoding] autorelease];
      }

      if (messageText) {
        [skippedMessageTextView_ setString:messageText];
      }
    }
  }
}

- (IBAction)showSkippedMessageFileClicked:(id)sender {
  NSDictionary *props = [[skippedMessagePopup_ selectedItem] representedObject];
  NSString *filePath = [props objectForKey:kEmUpMessagePathKey];
  if ([filePath length] > 0) {
    [[NSWorkspace sharedWorkspace] selectFile:filePath
                     inFileViewerRootedAtPath:nil];
  }
}

#pragma mark -

// uploadNow is the entry point to start or resume uploading
- (void)uploadNow {
  NSString *str;
  if (isPaused_) {
    // resuming from pause
    isPaused_ = NO;
    str = NSLocalizedString(@"UploadingResumed", nil);
    [self reportProgressWithTimestamp:str];
    [self updateUI];

  } else {
    // starting from stopped
    [self resetUploading];

    isUploading_ = YES;
    str = NSLocalizedString(@"UploadingStarted", nil);
    [self reportProgressWithTimestamp:str];

    if (shouldSimulateUploads_) {
      str = NSLocalizedString(@"UploadingSimulated", nil); // "(Simulating uploads)"
      [self reportProgress:str];
    }

    // switch the tab view to show the progress report
    [tabView_ selectTabViewItemWithIdentifier:kTabViewItemProgress];

    // immediately display the progress info before we start to upload
    [self updateUI];
    [messagesTransferredField_ display];
  }

  [self uploadMoreMessages];
}

- (void)stopUploading {
  isUploading_ = NO;
  isPaused_ = NO;

  // purge any pending upload invocation
  [self cancelUploadMoreMessagesAfterDelay];

  [uploadTickets_ makeObjectsPerformSelector:@selector(cancelTicket)];
  [uploadTickets_ removeAllObjects];

  [self updateUI];
}

- (void)uploadingCompleted {
  // "Messages transferred: %u/%u  Skipped: %u"
  NSString *template = NSLocalizedString(@"UploadingEndCountTemplate", nil);
  NSString *countStr = [NSString stringWithFormat:template,
                        messagesUploadedCount_, [self countSelectedMessages],
                        messagesSkippedCount_];
  [self reportProgress:countStr];
  
  template = NSLocalizedString(@"UploadingFinished", nil);
  [self reportProgressWithTimestamp:template];
  
  template = NSLocalizedString(@"StatusSeparator", nil);
  [self reportProgress:template];

  [self stopUploading];
  
  NSSound *theSound = [NSSound soundNamed:@"MailUploadDoneSound.mp3"];
  [theSound play];  
}

// uploadMoreMessages is called repeatedly to upload another message.  During
// slow upload mode, this will rate-limit itself and re-invoke itself
// recursively when needed to achieve the slow upload rate.
- (void)uploadMoreMessages {

  int maxTickets = isSlowUploadMode_ ? kSlowUploadMaxTickets : kFastUploadMaxTickets;
  if ([uploadTickets_ count] >= maxTickets) {
    // wait for some tickets to complete before uploading more
    return;
  }
  
  // in slow upload mode, wait a period after the last upload
  if (isSlowUploadMode_) {
    if (lastUploadDate_ != nil) {

      NSTimeInterval secsSinceLastUpload = - [lastUploadDate_ timeIntervalSinceNow];

      if (secsSinceLastUpload < kSlowUploadInterval) {
        NSTimeInterval newDelay = (kSlowUploadInterval - secsSinceLastUpload);
        
        [self uploadMoreMessagesAfterDelay:newDelay];
        return;
      }
    }
  }
  
  if (isPaused_) return;

  // get a message to upload from the retry queue or from the current controller
  NSString *template;
  
  // loop to upload an entry, either from the retry queue or from an outline
  // item controller. We'll stop looking when we've found an
  // entry to add or run out of entries to add
  while (1) {
    
    unsigned int numberOfPendingRetries = [entriesToRetry_ count];
    
    if (numberOfPendingRetries == 0
        && currentUploadingControllerIndex_ >= [itemsControllers_ count]) {
      // no more controllers left to get upload items from
      
      if ([uploadTickets_ count] == 0) {
        // we're done uploading
        [self uploadingCompleted];
      }
      break;
    }
    
    GDataEntryMailItem *entryToUpload = nil;
    
    // add an entry from the retry queue
    if (numberOfPendingRetries > 0) {
      
      // get the entry from the retry queue
      entryToUpload = [[[entriesToRetry_ objectAtIndex:0] retain] autorelease];
      [entriesToRetry_ removeObjectAtIndex:0];
      
    } else {
      
      // get an entry from the current upload item controller
      id<MailItemController> controller = [itemsControllers_ objectAtIndex:currentUploadingControllerIndex_];
      
      entryToUpload = [self nextEntryFromController:controller];
      if (entryToUpload == nil) {
        
        // move to the next controller
        ++currentUploadingControllerIndex_;
        continue;
      } else {
        // we got a new entry to upload from the current controller
        //
        // report to the user the name of the mailbox from which we got this entry
        NSString *mailboxName = [entryToUpload propertyForKey:kEmUpMailboxNameKey];
        if (![currentUploadingMailboxName_ isEqual:mailboxName]) {
          // "Uploading %@"
          template = NSLocalizedString(@"UploadingMailboxTemplate", nil);
          [self reportProgress:[NSString stringWithFormat:template,
                                mailboxName]];
          [self setCurrentUploadingMailboxName:mailboxName];
        }
        
        // see if we've uploaded one with this message ID before; if so,
        // report and skip it
        NSString *messageID = [entryToUpload propertyForKey:kEmUpMessageIDKey];
        if ([messageID length] > 0) {
          
          NSString *previousMsgLoc = [messageIDsUploaded_ objectForKey:messageID];
          if (previousMsgLoc != nil) {
            
            // "Already uploaded message with this ID\n   previously found in file %@"
            template = NSLocalizedString(@"StatusDuplicateIDTemplate", nil);
            NSString *dupMsg = [NSString stringWithFormat:template,
                                previousMsgLoc];
            [entryToUpload setProperty:dupMsg
                                forKey:kEmUpMessageErrorStringKey];
            [entryToUpload setProperty:kEmUpMessageErrorTypeDuplicate
                                forKey:kEmUpMessageErrorType];
            
            NSDictionary *propertyDict = [entryToUpload properties];
            [self handleFailedMessageForProperties:propertyDict];
            
            continue;
          }
          
          // add this to our set of uploaded message IDs
          NSString *path = [entryToUpload propertyForKey:kEmUpMessagePathKey];
          [messageIDsUploaded_ setObject:path forKey:messageID];
        }
      }
    }
    
    // upload the entry now
    [self uploadEntry:entryToUpload];
    
    if (isSlowUploadMode_ || ([uploadTickets_ count] >= maxTickets)) {
      break;
    }
  }
}


// nextEntryFromController returns the next upload mail entry from the specified
// controller, with additional properties and labels added to match user's
// settings in the user interface
- (GDataEntryMailItem *)nextEntryFromController:(id<MailItemController>)controller {

  GDataEntryMailItem *newEntry = [controller nextUploadItem];
  if (newEntry == nil) {
    // no more mail entries available from this controller
    return nil;
  }

  // add a label with the mailbox name, if checked by the user
  if ([maiboxNamesAsLabelsCheckbox_ state] == NSOnState) {
    NSString *mailboxName = [newEntry propertyForKey:kEmUpMailboxNameKey];
    if ([mailboxName length] > 0) {
      [newEntry addMailItemLabelWithString:mailboxName];
    }
  }

  // preserve message properties, if checked by the user
  if ([preserveMailPropertiesCheckbox_ state] == NSOnState) {
    NSArray *props = [newEntry propertyForKey:kEmUpMailboxPropertiesKey];
    NSString *property;
    GDATA_FOREACH(property, props) {
      [newEntry addMailItemPropertyWithString:property];
    }
  }

  // keep uploaded mail in inbox, if checked by the user
  BOOL isInboxChecked = ([putAllMailInInboxCheckbox_ state] == NSOnState);
  if (isInboxChecked) {
    [newEntry addMailItemPropertyWithString:kGDataMailItemIsInbox];
  }

  // add a custom label, if checked by the user
  if ([assignAdditionalLabelCheckbox_ state] == NSOnState) {

    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    NSString *labelStr = [additionalLabelField_ stringValue];
    labelStr = [labelStr stringByTrimmingCharactersInSet:whitespace];
    if ([labelStr length] > 0) {
      [newEntry addMailItemLabelWithString:labelStr];
    }
  }
  return newEntry;
}

- (void)uploadEntry:(GDataEntryMailItem *)entry {

  [self setLastUploadDate:[NSDate date]];

  if (shouldSimulateUploads_) {
    // invoke the callback in a second
    [self performSelector:@selector(simulateUploadEntry:)
               withObject:entry
               afterDelay:1.0];
  } else {

    GDataServiceGoogle *service = [self service];

    NSString *urlString = @"https://apps-apis.google.com/a/feeds/migration/2.0/default/mail";

    GDataServiceTicket *ticket;
    ticket = [service fetchEntryByInsertingEntry:entry
                                      forFeedURL:[NSURL URLWithString:urlString]
                                        delegate:self
                               didFinishSelector:@selector(uploadTicket:finishedWithEntry:error:)];
    [uploadTickets_ addObject:ticket];
  }
}

- (void)simulateUploadEntry:(GDataEntryMailItem *)entry {

  // make a fake results entry
  //
  // pass the actual entry
  [GDataServiceBase invokeCallback:@selector(uploadTicket:finishedWithEntry:error:)
                            target:self
                            ticket:nil
                            object:entry
                             error:nil];
}

- (void)uploadTicket:(GDataServiceTicket *)ticket
   finishedWithEntry:(GDataEntryMailItem *)entry
               error:(NSError *)error {
  
  GDataEntryMailItem *postedEntry = [ticket postedObject];
  if (ticket) {
    [uploadTickets_ removeObjectIdenticalTo:ticket];
  }
  
  if (error == nil) {
    // success for this entry
    messagesUploadedCount_++;

    if (messagesUploadedCount_ > kFastModeMaxMessages) {
      // we've uploaded 500 messages; change to slow upload mode
      isSlowUploadMode_ = YES;
    }

    [self updateUI];

    // reset the backoff counter, since there was no 503 status this time
    backoffCounter_ = 0;
    [self uploadMoreMessages];

  } else {
    // failure for this entry

    BOOL shouldKeepUploading = NO;
    BOOL shouldBackOff = NO;

    int statusCode = [error code];

    if (statusCode == 503) {
      // retry this entry later
      [entriesToRetry_ addObject:postedEntry];

      shouldKeepUploading = YES;
      shouldBackOff = YES;
      isSlowUploadMode_ = YES;

    } else if (statusCode == 403) {
      // forbidden -- probably bad username/password
      NSString *errorTitle = NSLocalizedString(@"ErrorTitle", nil); // "Error"
      NSString *errorMsg = NSLocalizedString(@"InvalidUserErr", nil); // "Username or password not accepted"

      NSBeginAlertSheet(errorTitle, nil, nil, nil,
                        [self window], self,
                        @selector(authFailedSheetDidEnd:returnCode:contextInfo:),
                        nil, nil, errorMsg);

      NSString *statusMsg = NSLocalizedString(@"UploadingStopped", nil);
      NSString *statusSeparator = NSLocalizedString(@"StatusSeparator", nil);
      [self reportProgressWithTimestamp:statusMsg];
      [self reportProgress:statusSeparator];

    } else {
      // this entry flat-out failed and we won't retry it
      // (or should we? it could lead to an infinite loop of errors)
      NSString *serverErrMsg = [error localizedDescription];

      // shove the error message into the entry's properties
      [postedEntry setProperty:serverErrMsg
                        forKey:kEmUpMessageErrorStringKey];

      [postedEntry setProperty:kEmUpMessageErrorTypeServer
                        forKey:kEmUpMessageErrorType];

      // report the failure
      NSDictionary *properties = [postedEntry properties];
      [self handleFailedMessageForProperties:properties];

      shouldKeepUploading = YES;
    }

    [self updateUI];

    if (!shouldKeepUploading) {
      [self stopUploading];
    } else {
      if (shouldBackOff) {
        [self uploadMoreMessagesAfterBackingOff];
      } else {
        // reset the backoff counter
        backoffCounter_ = 0;
        [self uploadMoreMessages];
      }
    }

  }
}

- (void)addSkippedMessagesPopupItemForProperties:(NSDictionary *)propertyDict {

  if ([skippedMessagePopup_ numberOfItems] > 250) {
    // too big a menu, plus too many properties of messages to retain
    return;
  }

  // make a menu item for this skipped message showing the mailbox or
  // file name, along with the message ID (or byte range in the file,
  // if no message ID is available)
  NSString *path = [propertyDict objectForKey:kEmUpMessagePathKey];
  NSString *mailboxName = [path lastPathComponent];

  NSString *messageID = [propertyDict objectForKey:kEmUpMessageIDKey];
  NSString *title = mailboxName;

  UniChar symbol;
  NSString *messageType = [propertyDict objectForKey:kEmUpMessageErrorType];
  if ([messageType isEqual:kEmUpMessageErrorTypeDuplicate]) {
    // duplicate
    symbol = 0x260D; // opposition symbol
  } else {
    // server errors
    symbol = 0x2639; // frown
  }
  
  NSString *template;
  if (messageID != nil) {
    // the menu item title is the file name and the message's ID
    template = NSLocalizedString(@"FilenameIDTemplate", nil); // "%C %@ %@"
    title = [NSString stringWithFormat:template,
             symbol, mailboxName, messageID];
  } else {
    NSRange range = [[propertyDict objectForKey:kEmUpMessageRangeKey] rangeValue];
    if (range.length > 0) {
      // the menu item title is the file name and the message's byte range
      template = NSLocalizedString(@"FilenameByteRangeTemplate", nil); // "%C %@ (bytes %u..%u)"
      title = [NSString stringWithFormat:template, 
               symbol, mailboxName,
               range.location, (range.location + range.length - 1)];
    }
  }

  NSMenuItem *menuItem = [[[NSMenuItem alloc] initWithTitle:title
                                                     action:@selector(skippedMessageClicked:)
                                              keyEquivalent:@""] autorelease];
  [menuItem setTarget:self];
  [menuItem setRepresentedObject:propertyDict];
  [[skippedMessagePopup_ menu] addItem:menuItem];

  if ([skippedMessagePopup_ numberOfItems] == 1) {
    // when adding the first menu item, select it as if the user
    // clicked it, thus loading the text view
    [self skippedMessageClicked:menuItem];
  }

  // update the tab label
  [self updateUI];
}

// in case of uploading error on a message, this method can convert the
// message's properties into something vaguely human readable, with the
// message's file path and perhaps its index in the mbox file
- (NSString *)messageDisplayIDFromProperties:(NSDictionary *)propertyDict {

  NSString *result;

  NSString *path = [propertyDict objectForKey:kEmUpMessagePathKey];
  unsigned int index = [[propertyDict objectForKey:kEmUpMessageIndexKey] unsignedIntValue];

  if (index == 0) {
    // it's the first message in the file; just report the path
    result = path;
  } else {
    // report the path and the file index
    // "%@ (at message %d)"
    NSString *template = NSLocalizedString(@"MessageDisplayIDTemplate", nil);
    result = [NSString stringWithFormat:template, path, index + 1];
  }
  return result;
}

// report failed messages to the user, and increment the count of messages
// skipped
- (void)handleFailedMessageForProperties:(NSDictionary *)propertyDict {
  NSString *format = NSLocalizedString(@"StatusFailedUpload", nil);
  
  // report the reason
  NSString *reason = [propertyDict objectForKey:kEmUpMessageErrorStringKey];

  NSString *errMsg = [NSString stringWithFormat:format, reason];
  [self reportProgress:errMsg];

  // "   %@"
  NSString *indentTemplate = NSLocalizedString(@"StatusIndentedMessageID", nil);
  
  NSString *path = [propertyDict objectForKey:kEmUpMessagePathKey];
  NSAssert1(path != nil, @"invalid properties: %@", propertyDict);
  
  NSString *messageDisplayID = [self messageDisplayIDFromProperties:propertyDict];
  NSString *reportStr = [NSString stringWithFormat:indentTemplate,
                         messageDisplayID];
  [self reportProgress:reportStr];
  
  // report message ID so the user can find the message in the file
  NSString *messageID = [propertyDict objectForKey:kEmUpMessageIDKey];
  if ([messageID length] > 0) {
    NSString *idReportStr = [NSString stringWithFormat:indentTemplate,
                             messageID];
    [self reportProgress:idReportStr];
  } else {
    // can't get the message ID, so report the byte range instead
    NSRange range = [[propertyDict objectForKey:kEmUpMessageRangeKey] rangeValue];
    if (range.length > 0) {
      // "   bytes %u..%u"
      NSString *template = NSLocalizedString(@"StatusIndentedMessageByteRange", nil);
      NSString *rangeStr = [NSString stringWithFormat:template,
                            range.location, (range.location + range.length - 1)];
      [self reportProgress:rangeStr];
    }
  }
  
  messagesSkippedCount_++;
  
  [self addSkippedMessagesPopupItemForProperties:propertyDict];
}

- (void)uploadMoreMessagesAfterBackingOff {
  // delay up to 15, 30, 60, 120 seconds
  if (backoffCounter_ < 4) {
    ++backoffCounter_;
  }

  NSTimeInterval delay = 7.5 * (double) (1L << backoffCounter_);

  // "   Delaying upload per server request (%d seconds)"
  NSString *template = NSLocalizedString(@"StatusDelayingTemplate", nil);
  NSString *str = [NSString stringWithFormat:template, (int)delay];

  [self reportProgressWithTimestamp:str];

  [self uploadMoreMessagesAfterDelay:delay];
}

- (void)uploadMoreMessagesAfterDelay:(NSTimeInterval)delay {

  if (delay > 0) {
    [self performSelector:@selector(uploadMoreMessages)
               withObject:nil
               afterDelay:delay];
  } else {
    [self uploadMoreMessages];
  }
}

- (void)cancelUploadMoreMessagesAfterDelay {
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(uploadMoreMessages)
                                             object:nil];
}

- (void)authFailedSheetDidEnd:(NSWindow *)sheet
                   returnCode:(int)returnCode
                  contextInfo:(void *)contextInfo {
  // we reported the failure to the user
}

- (void)resetUploading {

  currentUploadingControllerIndex_ = 0;
  [self setCurrentUploadingMailboxName:nil];

  messagesUploadedCount_ = 0;
  messagesSkippedCount_ = 0;

  isSlowUploadMode_ = NO;

  backoffCounter_ = 0;

  id<MailItemController> itemController;
  GDATA_FOREACH(itemController, itemsControllers_) {
    [itemController resetUpload];
  }

  [entriesToRetry_ removeAllObjects];

  [messageIDsUploaded_ removeAllObjects];
  
  [skippedMessagePopup_ removeAllItems];
  [skippedMessagePathField_ setStringValue:@""];
  [skippedMessageErrorField_ setStringValue:@""];
}

// reportProgress: appends and displays a string in the text view during
// uploading
- (void)reportProgress:(NSString *)reportStr {

  // add a return to the end
  reportStr = [reportStr stringByAppendingString:@"\n"];

  NSString *oldText = [progressReportTextView_ string];
  NSRange appendRange = NSMakeRange([oldText length], 0);

  [progressReportTextView_ replaceCharactersInRange:appendRange withString:reportStr];

  NSRange visibleRange = NSMakeRange(appendRange.location, [reportStr length]);
  [progressReportTextView_ scrollRangeToVisible:visibleRange];
  [progressReportTextView_ display];
}

// we'll add timestamps to reports when starting and stopping uploads
- (void)reportProgressWithTimestamp:(NSString *)reportStr {
  NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
  [dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];

  [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
  [dateFormatter setTimeStyle:NSDateFormatterMediumStyle];

  NSString *timestampStr = [dateFormatter stringFromDate:[NSDate date]];
  NSString *newReportStr = [NSString stringWithFormat:@"%@ %@",
                            reportStr, timestampStr];
  [self reportProgress:newReportStr];
}

- (BOOL)canAppQuitNow {
  if (!isUploading_) return YES;

  NSString *title = NSLocalizedString(@"QuitNowTitle", nil); // "Quit now?"
  NSString *msg = NSLocalizedString(@"QuitNowMsg", nil); // "Uploading progress will be lost."
  NSString *quitBtn = NSLocalizedString(@"QuitButton", nil); // "Quit"
  NSString *dontQuitBtn = NSLocalizedString(@"DontQuitButton", nil); // "Don't Quit"

  NSBeginAlertSheet(title, quitBtn, dontQuitBtn, nil,
                    [self window], self,
                    @selector(quitSheetDidEnd:returnCode:contextInfo:),
                    nil, nil, msg);
  return NO;
}

- (void)quitSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {

  BOOL shouldQuit = (returnCode == NSOKButton);

  // tell NSApp if the user does or does not want to quit
  [NSApp replyToApplicationShouldTerminate:shouldQuit];
}

#pragma mark -

// get a singleton of the GData service object
- (GDataServiceGoogle *)service {

  static GDataServiceGoogle* service = nil;

  if (service == nil) {
    service = [[GDataServiceGoogle alloc] init];

    [service setUserAgent:@"Google-MacMailUploader-1.0"];
    [service setServiceID:@"apps"];
  }

  // update the name/password each time the service is requested
  NSString *username = [usernameField_ stringValue];
  NSString *password = [passwordField_ stringValue];

  [service setUserCredentialsWithUsername:username
                                 password:password];
  return service;
}

#pragma mark -

#pragma mark Outline view data source

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {

  if (item == nil) {
    return [itemsControllers_ count];
  } else {
    return [item numberOfChildren];
  }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {

  unsigned numberOfChildren = [item numberOfChildren];
  return (numberOfChildren > 0);
}



- (id)outlineView:(NSOutlineView *)outlineView
            child:(int)index
           ofItem:(id)item {

  if (item == nil) {
    return [[itemsControllers_ objectAtIndex:index] rootItem];
  }

  id childItem = [item childAtIndex:index];
  return childItem;
}

static NSString *const kNameColumn = @"name";
static NSString *const kCheckboxColumn = @"checkbox";

- (id)outlineView:(NSOutlineView *)outlineView
objectValueForTableColumn:(NSTableColumn *)tableColumn
           byItem:(id)item {

  if ([[tableColumn identifier] isEqual:kNameColumn]) {

    // placeholder if there's no item; we don't expect to see this
    if (item == nil) return @"/";

    NSString *name = [item name];

    // indent according to the level of this folder
    NSString *padding = [@"" stringByPaddingToLength:[item level] * 3
                                          withString:@" "
                                     startingAtIndex:0];
    name = [padding stringByAppendingString:name];

    if ([item numberOfMessages] > 0 || ![outlineView isItemExpanded:item]) {
      unsigned int checkedNum = [item recursiveNumberOfCheckedMessages];
      unsigned int totalNum = [item recursiveNumberOfMessages];

      // report the number of checked items contained in this folder, and if
      // it's less than that total number of contained items, report that too
      NSString *template;
      if (checkedNum < totalNum) {
        // "%@ (%u of %u)"
        template = NSLocalizedString(@"MailboxPartiallySelectedTemplate", nil);
        name = [NSString stringWithFormat:template, name, checkedNum, totalNum];
      } else {
        // "%@ (%u)"
        template = NSLocalizedString(@"MailboxFullySelectedTemplate", nil);
        name = [NSString stringWithFormat:template, name, totalNum];
      }
    }

    if (isUploading_) {
      // make the outline item names gray
      NSDictionary *attrs;
      attrs = [NSDictionary dictionaryWithObject:[NSColor grayColor]
                                          forKey:NSForegroundColorAttributeName];
      name = [[[NSAttributedString alloc] initWithString:name
                                              attributes:attrs] autorelease];
    }
    return name;
  }

  if ([[tableColumn identifier] isEqual:kCheckboxColumn]) {
    return [NSNumber numberWithInt:[item state]];
  }
  return nil;
}

- (void)outlineView:(NSOutlineView *)outlineView
     setObjectValue:(id)object
     forTableColumn:(NSTableColumn *)tableColumn
             byItem:(id)item {

  // disallow checking/unchecking when mailboxes are being uploaded and
  // during uploads
  if (isUploading_ || isLoadingMailboxes_) return;

  if ([[tableColumn identifier] isEqual:kCheckboxColumn]) {
    int newState = [object intValue];
    if (newState == NSMixedState) {
      newState = NSOnState;
    }
    [item setState:newState];

    [outlineView reloadData];
  }

  // update count of checked messages
  [self updateUI];
}

- (NSString *)outlineView:(NSOutlineView *)ov
           toolTipForCell:(NSCell *)cell
                     rect:(NSRectPointer)rect
              tableColumn:(NSTableColumn *)tc
                     item:(id)item
            mouseLocation:(NSPoint)mouseLocation {

  if ([item isKindOfClass:[OutlineViewItem class]]) {
    return [item path];
  }
  return nil;
}
#pragma mark UI delegate methods

- (void)controlTextDidChange:(NSNotification *)note {
  // enable the upload button when a username and password are entered
  [self updateUI];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
  // when switching to the skipped tab, select the pop-up so arrow keys will
  // navigate through the skipped message list
  if ([[[tabView selectedTabViewItem] identifier] isEqual:kTabViewItemSkipped]) {
    [[self window] makeFirstResponder:skippedMessagePopup_]; 
  }
}


#pragma mark Setters and Getters -- just to avoid leaks internally

- (NSMutableArray *)uploadTickets {
  return uploadTickets_;
}

- (void)setUploadTickets:(NSMutableArray *)array {
  [uploadTickets_ autorelease];
  uploadTickets_ = [array retain];
}

- (NSString *)currentUploadingMailboxName {
  return currentUploadingMailboxName_;
}

- (void)setCurrentUploadingMailboxName:(NSString *)str {
  [currentUploadingMailboxName_ autorelease];
  currentUploadingMailboxName_ = [str copy];
}

- (void)setLastUploadDate:(NSDate *)date {
  [lastUploadDate_ release];
  lastUploadDate_ = [date retain];
}

- (void)setSimulateUploads:(BOOL)flag {
  shouldSimulateUploads_ = flag;
}

@end
