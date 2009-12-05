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

#import "EmUpConstants.h"
#import "OutlineViewItem.h"
#import "GDataUtilities.h"

@implementation OutlineViewItem
- (id)initWithName:(NSString *)name level:(unsigned int)level {
  self = [super init];
  if (self) {
    name_ = [name copy];
    level_ = level;
  }
  return self;
}

- (void)dealloc {
  [name_ release];
  [children_ release];
  [path_ release];
  [nextOutlineItem_ release];
  [super dealloc];
}

- (NSString *)description {
  // for the description, print the name, a checkmark if appropriate,
  // the path, and the number of children
  NSString *str = [NSString stringWithFormat:@"\"%@\"", name_];

  NSCellStateValue state = [self state];
  if (state == NSOnState) {
    str = [str stringByAppendingFormat:@" %C", 0x2713]; // checkmark
  }

  if (path_) {
    str = [str stringByAppendingFormat:@" <%@>", path_];
  }

  if ([children_ count] > 0) {
    str = [str stringByAppendingFormat:@" (%u child items)", [children_ count]];
  }

  if (numberOfMessages_ > 0) {
    str = [str stringByAppendingFormat:@" (%u msgs)", numberOfMessages_];
  }
  
  return str;
}

#pragma mark -

+ (id)itemWithName:(NSString *)name level:(unsigned int)level{
  return [[[self alloc] initWithName:name level:level] autorelease];
}

- (void)addChild:(OutlineViewItem *)child {
  if (children_ == nil) {
    children_ = [[NSMutableArray alloc] init];
  }
  [children_ addObject:child];
}

- (id)childAtIndex:(unsigned)index {
  if (index < [children_ count]) {
    return [children_ objectAtIndex:index];
  }
  return nil;
}

- (unsigned)numberOfChildren {
  return [children_ count];
}

- (NSString *)name {
  return name_;
}

- (unsigned int)level {
  return level_;
}

- (NSString *)path {
  return path_;
}

- (void)setPath:(NSString *)path {
  [path_ autorelease];
  path_ = [path copy];
}

- (void)setNextOutlineItem:(OutlineViewItem *)item {
  [nextOutlineItem_ autorelease];
  nextOutlineItem_ = [item retain];
}

- (id)nextOutlineItem {
  return nextOutlineItem_;
}

- (void)setState:(NSCellStateValue)val {
  if ([children_ count] == 0) {
    cellState_ = val;
  } else {
    // set all the children to match this one's new state
    [children_ setValue:[NSNumber numberWithInt:val] forKey:@"state"];
  }
}


- (NSCellStateValue)state {
  // if there are no children, the state depends only on its own state
  if ([children_ count] == 0) {
    return cellState_;
  }

  // there are children; examine their states
  int minVal = [[children_ valueForKeyPath:@"@min.state"] intValue];

  // if any are mixed state children (-1) then return mixed
  if (minVal < 0) return NSMixedState;

  // if all children are on (1), then return on
  if (minVal > 0) return NSOnState;

  // if all are off (0) then return off
  int maxVal = [[children_ valueForKeyPath:@"@max.state"] intValue];
  if (maxVal == 0) return NSOffState;

  // some are on, some are off
  return NSMixedState;
}

- (void)setNumberOfMessages:(unsigned int)val {
  numberOfMessages_ = val;
}

- (unsigned int)numberOfMessages {
  return numberOfMessages_;
}

- (unsigned int)recursiveNumberOfMessages {
  unsigned int numberOfOwnMessages = [self numberOfMessages];
  if ([children_ count] == 0) {
    // we have no children
    return numberOfOwnMessages;
  }

  NSNumber *sum = [children_ valueForKeyPath:@"@sum.recursiveNumberOfMessages"];
  unsigned int totalMessages = [sum unsignedIntValue] + numberOfOwnMessages;
  return totalMessages;
}

- (unsigned int)recursiveNumberOfCheckedMessages {

  // if we're unchecked, then we're done
  if ([self state] == NSOffState) {
    return 0;
  }

  unsigned int numberOfOwnMessages = [self numberOfMessages];
  if ([children_ count] == 0) {
    // we have no children; we may contain messages ourself
    return numberOfOwnMessages;
  }

  // add up the checked messages in the children
  NSNumber *sum = [children_ valueForKeyPath:@"@sum.recursiveNumberOfCheckedMessages"];
  unsigned int totalMessages = [sum unsignedIntValue] + numberOfOwnMessages;
  return totalMessages;
}

@end
