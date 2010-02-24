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

#include <Carbon/Carbon.h>

#import "GDataHTTPFetcher.h"

#import "EmUpAppController.h"
#import "EmUpWindowController.h"

@interface EmUpAppController (PrivateMethods)
- (void)checkVersion;
@end

@implementation EmUpAppController

- (void)applicationWillFinishLaunching:(NSNotification *)notifcation {

  EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];
  [windowController showWindow:self];

  [self checkVersion];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];
  return [windowController canAppQuitNow] ? NSTerminateNow : NSTerminateLater;
}

- (void)applicationWillTerminate:(NSNotification *)note {
  EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];
  [windowController deleteImportedEntourageArchive];
}

#pragma mark -

- (IBAction)showHelp:(id)sender {
  NSString *urlStr = @"http://code.google.com/p/google-email-uploader-mac/";
  NSURL *url = [NSURL URLWithString:urlStr];
  [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)showReleaseNotes:(id)sender {
  NSString *urlStr = @"http://google-email-uploader-mac.googlecode.com/svn/trunk/Source/ReleaseNotes.txt";
  NSURL *url = [NSURL URLWithString:urlStr];
  [[NSWorkspace sharedWorkspace] openURL:url];
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

#pragma mark -

// we'll check the version in our plist against the plist on the open
// source site
- (void)checkVersion {
  NSString *const kLastCheckDateKey = @"lastVersionCheck";

  // determine if we've checked in the last 24 hours (or if the option key
  // is down, which forces us to offer the update)
  UInt32 currentModifiers = GetCurrentKeyModifiers();
  BOOL shouldForceUpdate = ((currentModifiers & optionKey) != 0)
    && ((currentModifiers & controlKey) != 0);

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSDate *lastCheckDate = [defaults objectForKey:kLastCheckDateKey];
  if (lastCheckDate && !shouldForceUpdate) {
    // if the time since the last check is under a day, bail
    NSTimeInterval interval = - [lastCheckDate timeIntervalSinceNow];
    if (interval < 24 * 60 * 60) {
      return;
    }
  }

  // set the last check date to now
  [defaults setObject:[NSDate date]
               forKey:kLastCheckDateKey];

  // URL of our plist file in the sources online
  NSString *urlStr = @"http://google-email-uploader-mac.googlecode.com/svn/trunk/Source/LatestVersion.plist";

  NSURL *plistURL = [NSURL URLWithString:urlStr];
  NSURLRequest *request = [NSURLRequest requestWithURL:plistURL];
  GDataHTTPFetcher *fetcher = [GDataHTTPFetcher httpFetcherWithRequest:request];

  [fetcher beginFetchWithDelegate:self
                didFinishSelector:@selector(plistFetcher:finishedWithData:)
                  didFailSelector:@selector(plistFetcher:failedWithError:)];

  [fetcher setUserData:[NSNumber numberWithBool:shouldForceUpdate]];
}

- (void)plistFetcher:(GDataHTTPFetcher *)fetcher finishedWithData:(NSData *)data {
  // convert the returns data to a plist dictionary
  NSString *errorStr = nil;
  NSDictionary *plist;

  plist = [NSPropertyListSerialization propertyListFromData:data
                                           mutabilityOption:NSPropertyListImmutable
                                                     format:NULL
                                           errorDescription:&errorStr];

  if ([plist isKindOfClass:[NSDictionary class]]) {
    // compare the plist's short version string with the one in this bundle
    NSString *latestVersion = [plist objectForKey:@"CFBundleShortVersionString"];
    NSString *thisVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];

    NSComparisonResult result = [GDataUtilities compareVersion:thisVersion
                                                     toVersion:latestVersion];

    BOOL shouldForceUpdate = [[fetcher userData] boolValue];

    if (result != NSOrderedAscending && !shouldForceUpdate) {
      // we're current; do nothing
    } else {
      // show the user the "update now?" dialog
      EmUpWindowController* windowController = [EmUpWindowController sharedEmUpWindowController];

      NSString *title = NSLocalizedString(@"UpdateAvailable", nil);
      NSString *msg = NSLocalizedString(@"UpdateAvailableMsg", nil);
      NSString *updateBtn = NSLocalizedString(@"UpdateButton", nil); // "Update Now"
      NSString *dontUpdateBtn = NSLocalizedString(@"DontUpdateButton", nil); // "Don't Update"

      NSBeginAlertSheet(title, updateBtn, dontUpdateBtn, nil,
                        [windowController window], self,
                        @selector(updateSheetDidEnd:returnCode:contextInfo:),
                        nil, nil, msg, thisVersion, latestVersion);
    }
  } else {
    NSLog(@"unable to parse plist, %@", errorStr);
  }
}

- (void)updateSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {

  if (returnCode == NSOKButton) {
    // open the project page
    NSString *urlStr = @"https://code.google.com/p/google-email-uploader-mac/";
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlStr]];
  }
}

- (void)plistFetcher:(GDataHTTPFetcher *)fetcher failedWithError:(NSError *)error {
  // nothing to do but report this on the console
  NSLog(@"unable to fetch plist at %@, %@", [[fetcher request] URL], error);
}

@end
