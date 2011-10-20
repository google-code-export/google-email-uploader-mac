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

#import "EmUpConstants.h"
#import "OutlineViewItem.h"
#import "GDataEntryMailItem.h"

@interface OutlineViewItemMBox : OutlineViewItem {
  
  // byte offsets to start of mail messages in the mbox file
  NSArray *messageOffsets_;
  NSString *endOfLine_;
}

- (void)setMessageOffsets:(NSArray *)array;
- (NSArray *)messageOffsets;

- (void)setEndOfLine:(NSString *)str;
- (NSString *)endOfLine;

@end

// MBoxItemsController handles folders of MBox files such as Eudora and
// Thunderbird

@interface MBoxItemsController : NSObject <MailItemController> {
  OutlineViewItemMBox *rootItem_;
  
  NSString *mailFolderPath_;
  NSString *rootName_;
  
  OutlineViewItemMBox *lastUploadedItem_; // non-nil once something's been uploaded
  int lastUploadedIndex_; // message within the item, -1 if none attemped
  
  NSData *uploadingData_; // memory-mapped file data for uploading
}

- (id)initWithMailFolderPath:(NSString *)path
                    rootName:(NSString *)rootName;

- (OutlineViewItem *)rootItem;

- (unsigned int)countSelectedMessages;

- (NSString *)mailFolderPath;

- (void)resetUpload;
- (GDataEntryMailItem *)nextUploadItem;

@end
