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

#import <Cocoa/Cocoa.h>

#import "OutlineViewItem.h"
#import "GDataEntryMailItem.h"

@interface OutlineViewItemApple : OutlineViewItem {
      
  // paths of email messages, if any, in this mailbox
  NSMutableArray *emlxPaths_;
}

- (void)setEmlxPaths:(NSArray *)paths;
- (NSArray *)emlxPaths;
- (void)addEmlxPath:(NSString *)path;

@end

@interface AppleMailItemsController : NSObject <MailItemController> {
  NSString *mailFolderPath_;
  NSString *rootName_; // name to display in outline view

  OutlineViewItemApple *rootItem_;
  BOOL isMaildir_;

  OutlineViewItemApple *lastUploadedItem_; // non-nil once something's been uploaded
  int lastUploadedIndex_; // message within the item, -1 if none yet attemped
}

- (id)initWithMailFolderPath:(NSString *)path rootName:(NSString *)rootName isMaildir:(BOOL)isMaildir;

- (OutlineViewItem *)rootItem;

- (unsigned int)countSelectedMessages;

- (void)resetUpload;

// nextUploadItem is called during uploading; it returns nil once the
// uploads for this controller have been exhausted
- (GDataEntryMailItem *)nextUploadItem;

- (NSString *)mailFolderPath;

@end
