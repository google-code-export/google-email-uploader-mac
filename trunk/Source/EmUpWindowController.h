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
//  EmUpWindowController.h
//

#import <Cocoa/Cocoa.h>

#import "GDataElements.h"
#import "OutlineViewItem.h"
#import "AppleMailItemsController.h"
#import "MBoxItemsController.h"

@interface EmUpWindowController : NSWindowController {

  IBOutlet NSOutlineView *outlineView_;
  IBOutlet NSTextView *progressReportTextView_;
  IBOutlet NSTabView *tabView_;
  IBOutlet NSTextField *outlineViewTitle_;
  
  IBOutlet NSTextView *skippedMessageTextView_;
  IBOutlet NSPopUpButton *skippedMessagePopup_;
  IBOutlet NSButton *showSkippedMessageFileButton_;
  IBOutlet NSTextField *skippedMessagePathField_;
  IBOutlet NSTextField *skippedMessageErrorField_;

  IBOutlet NSTextField *usernameField_;
  IBOutlet NSSecureTextField *passwordField_;

  IBOutlet NSProgressIndicator *progressIndicator_;
  IBOutlet NSProgressIndicator *spinner_;

  IBOutlet NSTextField *messagesSelectedNumField_;
  IBOutlet NSTextField *messagesTransferredField_;

  IBOutlet NSButton *uploadButton_;
  IBOutlet NSButton *stopButton_;
  IBOutlet NSButton *pauseButton_;

  IBOutlet NSButton *maiboxNamesAsLabelsCheckbox_;
  IBOutlet NSButton *preserveMailPropertiesCheckbox_;
  IBOutlet NSButton *putAllMailInInboxCheckbox_;
  IBOutlet NSButton *assignAdditionalLabelCheckbox_;
  IBOutlet NSTextField *additionalLabelField_;

  IBOutlet NSTextField *pausedMessageField_;

  IBOutlet NSTextField *uploadTimeEstimateField_;

  // each top-level item in the outline view has an item controller
  // object of type id<MailItemController>
  NSMutableArray *itemsControllers_;

  // index into itemControllers_ for the controller we're currently
  // uploading from, and the name of the current mailbox being uploaded from
  unsigned int currentUploadingControllerIndex_;
  NSString *currentUploadingMailboxName_;

  // status 503 responses cause us to back off for (15, 30, 60, 120) seconds,
  // enter slow upload mode, and add the 503'd entries to the retry list
  int backoffCounter_;

  NSMutableArray *entriesToRetry_;

  NSMutableDictionary *messageIDsUploaded_; // maps ID to file path
  
  NSDate *lastUploadDate_; // time last message was uploadded

  // app user interface state
  BOOL isLoadingMailboxes_;
  BOOL isUploading_;         // is uploading, though may be paused
  BOOL isPaused_;
  unsigned long messagesUploadedCount_;
  unsigned long messagesSkippedCount_;

  // we upload fast up to 500 messages upload fast, or until
  // we get a 503 status from the server
  BOOL isSlowUploadMode_;

  NSMutableArray *uploadTickets_;
  
  BOOL shouldSimulateUploads_;
}

+ (EmUpWindowController *)sharedEmUpWindowController;

- (BOOL)canAppQuitNow;

- (IBAction)uploadClicked:(id)sender;
- (IBAction)stopClicked:(id)sender;
- (IBAction)pauseClicked:(id)sender;
- (IBAction)showSkippedMessageFileClicked:(id)sender;
- (IBAction)reloadMailboxesClicked:(id)sender;

// addMailboxes is sent by menu items with a tag of 0 (Apple), 1 (Eudora),
// 2 (Thunderbird), or 3 (Entourage RGE)
- (IBAction)addMailboxes:(id)sender;

// import will use Apple script to ask Entourage to create an RGE archive
- (IBAction)importRGEArchiveFromEntourage:(id)sender;

- (void)setSimulateUploads:(BOOL)flag;

@end
