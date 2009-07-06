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

// we use openssl's base64 implementation below in StringWithBase64ForData()
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

@implementation GDataMailItemRFC822Msg
+ (NSString *)extensionElementURI       { return kGDataNamespaceGoogleApps; }
+ (NSString *)extensionElementPrefix    { return kGDataNamespaceGoogleAppsPrefix; }
+ (NSString *)extensionElementLocalName { return @"rfc822Msg"; }

- (void)addParseDeclarations {
  [super addParseDeclarations];
  
  // add the encoding attribtue
  [self addLocalAttributeDeclarations:[NSArray arrayWithObject:kEncodingAttr]];
}

- (void)setIsEncodedBase64:(BOOL)flag {
  NSString *str = (flag ? @"base64" : nil);
  [self setStringValue:str forAttribute:kEncodingAttr];
}

- (BOOL)isEncodedBase64 {
  NSString *str = [self stringValueForAttribute:kEncodingAttr];
  return [str isEqual:@"base64"];
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
  
//  [obj setNamespaces:[GDataEntryMailItem appsNamespaces]];
  
  return obj;
}

+ (GDataEntryMailItem *)mailItemWithRFC822String:(NSString *)str {
  
  GDataEntryMailItem *obj = [self mailItem];

  NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
  NSString *base64 = [self stringWithBase64ForData:data];

  GDataMailItemRFC822Msg *rfc822msg = [GDataMailItemRFC822Msg valueWithString:base64];
  [rfc822msg setIsEncodedBase64:YES];
  
  [obj setRFC822Msg:rfc822msg];
  
  return obj;
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
   [GDataMailItemRFC822Msg class],
   [GDataMailItemSpamSetting class],
   nil];
}

- (NSMutableArray *)itemsForDescription {
  
  GDataMailItemRFC822Msg *msg = [self RFC822Msg];
  NSString *msgStr;
  if ([msg isEncodedBase64]) {
    // avoid descriptions with long unreadable base-64:
    //
    // show the first 10 chars of base-64 encoded messages
    NSString *value = [msg stringValue];
    unsigned int fragmentLen = MIN(10, [value length]);
    msgStr = [NSString stringWithFormat:@"base64:%@...",
                        [value substringWithRange:NSMakeRange(0, fragmentLen)]];
  } else {
    msgStr = [msg description];
  }
  
  NSArray *labels = [self valueForKeyPath:@"mailItemLabels.stringValue"];
  NSString *labelStr = [labels componentsJoinedByString:@","];
  
  struct GDataDescriptionRecord descRecs[] = {
    { @"properties", @"mailItemProperties", kGDataDescValueLabeled     },
    { @"labels",     labelStr,              kGDataDescValueIsKeyPath   },
    { @"rfc822Msg",  msgStr,                kGDataDescValueIsKeyPath   },
    { @"filterSpam", @"shouldFilterSpam",   kGDataDescBooleanPresent   },
    { nil, nil, 0 }
  };
  
  NSMutableArray *items = [super itemsForDescription];
  [self addDescriptionRecords:descRecs toItems:items];
  return items;
}

#pragma mark -

- (GDataMailItemRFC822Msg *)RFC822Msg {
  GDataMailItemRFC822Msg *obj;
  obj = [self objectForExtensionClass:[GDataMailItemRFC822Msg class]];

  return obj;
}

- (void)setRFC822Msg:(GDataMailItemRFC822Msg *)obj {
  [self setObject:obj forExtensionClass:[GDataMailItemRFC822Msg class]];
}

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

#pragma mark -

+ (NSString *)stringWithBase64ForData:(NSData *)data {
  
  BIO *membio, *base64;
  BUF_MEM *buff;
  
  base64 = BIO_new(BIO_f_base64());
  membio = BIO_new(BIO_s_mem());
  BIO_set_flags(base64, BIO_FLAGS_BASE64_NO_NL);
  
  base64 = BIO_push(base64, membio);
  
  BIO_write(base64, [data bytes], [data length]);
  BIO_flush(base64);
  BIO_get_mem_ptr(base64, &buff);
  
  NSString *result = [[[NSString alloc] initWithBytes:buff->data
                                               length:buff->length 
                                             encoding:NSUTF8StringEncoding] autorelease];  
  BIO_free_all(base64);
  
  return result;
}

@end

