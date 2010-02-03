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
//  EmUpAppController.m
//

#import "GDataHTTPFetcher.h"

#import "EmUpAppController.h"
#import "EmUpWindowController.h"

@implementation EmUpAppController

- (void)applicationWillFinishLaunching:(NSNotification *)notifcation {

  EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];
  [windowController showWindow:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note {
  EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];
  [windowController deleteImportedEntourageArchive];
}

- (IBAction)importFromEntourage:(id)sender {
  EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];
  [windowController importRGEArchiveFromEntourage:sender];
}

- (IBAction)addMailboxes:(id)sender {
  EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];
  [windowController addMailboxes:sender];
}

- (IBAction)reloadMailboxes:(id)sender {
  EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];
  [windowController reloadMailboxesClicked:sender];
}

- (IBAction)loggingCheckboxClicked:(id)sender {
  // toggle the menu item's checkmark
  [loggingMenuItem_ setState:![loggingMenuItem_ state]];
  [GDataHTTPFetcher setIsLoggingEnabled:[loggingMenuItem_ state]];
}

- (IBAction)simulateUploadsClicked:(id)sender {
  [simulateUploadsMenuItem_ setState:![simulateUploadsMenuItem_ state]];
  
  EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];
  [windowController setSimulateUploads:[simulateUploadsMenuItem_ state]];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];
  return [windowController canAppQuitNow] ? NSTerminateNow : NSTerminateLater;
}

@end
