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
//  GDataEntryMailItem.m
//

#include <openssl/sha.h>
#include <openssl/evp.h>
#include <openssl/bio.h>
#include <openssl/buffer.h>
#include <openssl/pem.h>
#include <openssl/evp.h>
#include <openssl/err.h>

#define GDATAMAILITEM_DEFINE_GLOBALS 1

#import "GDataEntryMailItem.h"
#import "GDataEntryLink.h"

static NSString* const kEncodingAttr = @"encoding";

@implementation GDataMailItemProperty
+ (NSString *)extensionElementURI       { return kGDataNamespaceGoogleApps; }
+ (NSString *)extensionElementPrefix    { return kGDataNamespaceGoogleAppsPrefix; }
+ (NSString *)extensionElementLocalName { return @"mailItemProperty"; }
@end

@implementation GDataMailItemLabel
+ (NSString *)extensionElementURI       { return kGDataNamespaceGoogleApps; }
+ (NSString *)extensionElementPrefix    { return kGDataNamespaceGoogleAppsPrefix; }
+ (NSString *)extensionElementLocalName { return @"label"; }

- (NSString *)attributeName {
  return @"labelName";
}
@end

@implementation GDataMailItemSpamSetting
+ (NSString *)extensionElementURI       { return kGDataNamespaceGoogleApps; }
+ (NSString *)extensionElementPrefix    { return kGDataNamespaceGoogleAppsPrefix; }
+ (NSString *)extensionElementLocalName { return @"spamSettings"; }
@end

@implementation GDataEntryMailItem

+ (NSDictionary *)appsNamespaces {
  NSMutableDictionary *namespaces;
  
  namespaces = [NSMutableDictionary dictionaryWithObject:kGDataNamespaceGoogleApps
                                                  forKey:kGDataNamespaceGoogleAppsPrefix];
  
  [namespaces addEntriesFromDictionary:[GDataEntryBase baseGDataNamespaces]];
  
  return namespaces;
}

+ (GDataEntryMailItem *)mailItem {
  GDataEntryMailItem *obj;
  obj = [[[GDataEntryMailItem alloc] init] autorelease];

  [obj setNamespaces:[GDataEntryMailItem appsNamespaces]];

  return obj;
}

+ (GDataEntryMailItem *)mailItemWithRFC822String:(NSString *)str {

  GDataEntryMailItem *entry = [self mailItem];

  NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];

  [entry setUploadData:data];
  [entry setUploadMIMEType:@"message/rfc822"];
  return entry;
}

#pragma mark -

+ (NSString *)standardEntryKind {
  return kGDataCategoryMailItem;
}

+ (void)load {
  [self registerEntryClass];
}

- (void)addExtensionDeclarations {
  
  [super addExtensionDeclarations];
  
  [self addExtensionDeclarationForParentClass:[self class]
                                   childClasses:
   [GDataMailItemProperty class],
   [GDataMailItemLabel class],
   [GDataMailItemSpamSetting class],
   nil];
}

- (NSMutableArray *)itemsForDescription {
  
  NSData *uploadData = [self uploadData];
  NSString *msgStr = [[[NSString alloc] initWithData:uploadData
                                            encoding:NSUTF8StringEncoding] autorelease];
  if (msgStr == nil) {
   msgStr = @"<Unknown upload data>"; 
  }

  NSArray *labels = [self valueForKeyPath:@"mailItemLabels.stringValue"];
  NSString *labelStr = [labels componentsJoinedByString:@","];
  
  struct GDataDescriptionRecord descRecs[] = {
    { @"properties", @"mailItemProperties", kGDataDescValueLabeled     },
    { @"labels",     labelStr,              kGDataDescValueIsKeyPath   },
    { @"msg",        msgStr,                kGDataDescValueIsKeyPath   },
    { @"filterSpam", @"shouldFilterSpam",   kGDataDescBooleanPresent   },
    { nil, nil, 0 }
  };
  
  NSMutableArray *items = [super itemsForDescription];
  [self addDescriptionRecords:descRecs toItems:items];
  return items;
}

#pragma mark -

- (NSArray *)mailItemLabels {
  return [self objectsForExtensionClass:[GDataMailItemLabel class]];
}

- (void)setMailItemLabels:(NSArray *)array {
  [self setObjects:array forExtensionClass:[GDataMailItemLabel class]];
}

- (void)addMailItemLabel:(GDataMailItemLabel *)obj {
  [self addObject:obj forExtensionClass:[GDataMailItemLabel class]];
}

- (void)addMailItemLabelWithString:(NSString *)str {
  GDataMailItemLabel *label = [GDataMailItemLabel valueWithString:str];
  [self addMailItemLabel:label];
}

- (NSArray *)mailItemProperties {
  return [self objectsForExtensionClass:[GDataMailItemProperty class]];
}

- (void)setMailItemProperties:(NSArray *)array {
  [self setObjects:array forExtensionClass:[GDataMailItemProperty class]];
}

- (void)addMailItemProperty:(GDataMailItemProperty *)obj {
  [self addObject:obj forExtensionClass:[GDataMailItemProperty class]];
}

- (void)addMailItemPropertyWithString:(NSString *)str {
  GDataMailItemProperty *prop = [GDataMailItemProperty valueWithString:str];
  [self addMailItemProperty:prop];
}

- (BOOL)shouldFilterSpam {
  id obj = [self objectForExtensionClass:[GDataMailItemSpamSetting class]]; 
  return [obj boolValue];
}

- (void)setShouldFilterSpam:(BOOL)flag {
  GDataMailItemSpamSetting *obj = [GDataMailItemSpamSetting valueWithBool:flag];
  [self setObject:obj forExtensionClass:[GDataMailItemSpamSetting class]];
}
@end

