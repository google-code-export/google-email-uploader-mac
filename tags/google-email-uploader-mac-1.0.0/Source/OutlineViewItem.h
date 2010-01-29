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

@class OutlineViewItem;
@class GDataEntryMailItem;

// The mail item controller protocol is the interface to the objects
// that handle the topmost-level outline view items
@protocol MailItemController
- (OutlineViewItem *)rootItem;
- (unsigned int)countSelectedMessages;
- (void)resetUpload;
- (GDataEntryMailItem *)nextUploadItem;
- (NSString *)mailFolderPath;
@end

// Each OutlineViewItem represents either a path to a file containing
// one or more messages, or a folder of children, which are other
// outline view items
@interface OutlineViewItem : NSObject {
  NSString *name_;
  NSMutableArray *children_;
  unsigned int level_;
  NSString *path_;

  // pointer to next item containing messages (so we have simple
  // linked list to follow when uploading)
  OutlineViewItem *nextOutlineItem_;

  NSCellStateValue cellState_;
  unsigned int numberOfMessages_;
}

+ (id)itemWithName:(NSString *)name level:(unsigned int)level;

- (id)initWithName:(NSString *)name level:(unsigned int)level;

- (NSString *)name;
- (unsigned int)level; // for drawing folder indentation

- (void)addChild:(OutlineViewItem *)child;
- (id)childAtIndex:(unsigned)index;
- (unsigned)numberOfChildren;

- (void)setPath:(NSString *)str;
- (NSString *)path;

// a linear list for finding messages later
- (void)setNextOutlineItem:(OutlineViewItem *)item;
- (id)nextOutlineItem;

// for items which are parents, setting the state to on or off sets the state of
// all children recursively, and the current state of an item which is a parent
// is determined by examining the states of all children
- (void)setState:(NSCellStateValue)val;
- (NSCellStateValue)state;

- (void)setNumberOfMessages:(unsigned int)val;
- (unsigned int)numberOfMessages;

- (unsigned int)recursiveNumberOfMessages;
- (unsigned int)recursiveNumberOfCheckedMessages;

@end
