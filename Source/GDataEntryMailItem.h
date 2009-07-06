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
//  GDataEntryMailItem.h
//

#import "GDataEntryBase.h"

// We define constant symbols in the main entry class for the client service

#undef _EXTERN
#undef _INITIALIZE_AS
#ifdef GDATAMAILITEM_DEFINE_GLOBALS
#define _EXTERN 
#define _INITIALIZE_AS(x) =x
#else
#define _EXTERN extern
#define _INITIALIZE_AS(x)
#endif

_EXTERN NSString* kGDataNamespaceGoogleApps       _INITIALIZE_AS(@"http://schemas.google.com/apps/2006");
_EXTERN NSString* kGDataNamespaceGoogleAppsPrefix _INITIALIZE_AS(@"apps");

_EXTERN NSString* kGDataCategoryMailItem _INITIALIZE_AS(@"http://schemas.google.com/apps/2006#mailItem");

_EXTERN NSString* kGDataMailItemIsDraft    _INITIALIZE_AS(@"IS_DRAFT");
_EXTERN NSString* kGDataMailItemIsInbox    _INITIALIZE_AS(@"IS_INBOX");
_EXTERN NSString* kGDataMailItemIsStarred  _INITIALIZE_AS(@"IS_STARRED");
_EXTERN NSString* kGDataMailItemIsSent     _INITIALIZE_AS(@"IS_SENT");
_EXTERN NSString* kGDataMailItemIsTrash    _INITIALIZE_AS(@"IS_TRASH");
_EXTERN NSString* kGDataMailItemIsUnread   _INITIALIZE_AS(@"IS_UNREAD");

@interface GDataMailItemProperty : GDataValueConstruct <GDataExtension>
+ (NSString *)extensionElementURI;
+ (NSString *)extensionElementPrefix;
+ (NSString *)extensionElementLocalName;
@end

@interface GDataMailItemLabel : GDataValueConstruct <GDataExtension>
+ (NSString *)extensionElementURI;
+ (NSString *)extensionElementPrefix;
+ (NSString *)extensionElementLocalName;
@end

@interface GDataMailItemRFC822Msg : GDataValueElementConstruct <GDataExtension>
+ (NSString *)extensionElementURI;
+ (NSString *)extensionElementPrefix;
+ (NSString *)extensionElementLocalName;

- (void)setIsEncodedBase64:(BOOL)flag;
- (BOOL)isEncodedBase64;
@end

@interface GDataMailItemSpamSetting : GDataBoolValueConstruct <GDataExtension>
+ (NSString *)extensionElementURI;
+ (NSString *)extensionElementPrefix;
+ (NSString *)extensionElementLocalName;
@end


@interface GDataEntryMailItem : GDataEntryBase

+ (NSDictionary *)appsNamespaces;

+ (GDataEntryMailItem *)mailItem;
+ (GDataEntryMailItem *)mailItemWithRFC822String:(NSString *)str;

// extensions
- (GDataMailItemRFC822Msg *)RFC822Msg;
- (void)setRFC822Msg:(GDataMailItemRFC822Msg *)obj;

- (BOOL)shouldFilterSpam;
- (void)setShouldFilterSpam:(BOOL)flag;

- (NSArray *)mailItemLabels;
- (void)setMailItemLabels:(NSArray *)array;
- (void)addMailItemLabel:(GDataMailItemLabel *)obj;
- (void)addMailItemLabelWithString:(NSString *)str;

- (NSArray *)mailItemProperties;
- (void)setMailItemProperties:(NSArray *)arr;
- (void)addMailItemProperty:(GDataMailItemProperty *)obj;
- (void)addMailItemPropertyWithString:(NSString *)str;

+ (NSString *)stringWithBase64ForData:(NSData *)data;

@end
