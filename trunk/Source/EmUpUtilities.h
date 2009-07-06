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
#import "GDataEntryMailItem.h"

@interface EmUpUtilities : NSObject

// return the headers block of a message as a single string
+ (NSString *)headersForMessageText:(NSString *)message
                          endOfLine:(NSString *)endOfLine;

// scan for a specific header line, and return the text in the header line
// after the ':', or return nil
//
// note: only works for single-line headers
+ (NSString *)stringForHeader:(NSString *)headerName
                  fromHeaders:(NSString *)headers
                    endOfLine:(NSString *)endOfLine;

// fix the headers in a message
//
// currently, this just sets the Content-Type header to text/html if the
// message body begins with <x-html>
+ (NSString *)messageTextWithAlteredHeadersForMessageText:(NSString *)message
                                                endOfLine:(NSString *)endOfLine;
@end
