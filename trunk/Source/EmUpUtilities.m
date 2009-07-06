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

#import "EmUpUtilities.h"

@implementation EmUpUtilities

+ (NSString *)headersForMessageText:(NSString *)message
                          endOfLine:(NSString *)endOfLine {

  // scan the message's headers into a string (including the newlines at the
  // end)
  NSString *headers = nil;
  NSScanner *msgScanner = [NSScanner scannerWithString:message];
  [msgScanner setCharactersToBeSkipped:[NSCharacterSet whitespaceCharacterSet]];

  NSString *twoReturns = [NSString stringWithFormat:@"%@%@",
                          endOfLine, endOfLine];

  if ([msgScanner scanUpToString:twoReturns intoString:&headers]) {
    // add the two newlines at the end
    headers = [headers stringByAppendingString:twoReturns];
    return headers;
  }
  return nil;
}

+ (NSString *)scanHeaderLineWithScanner:(NSScanner *)scanner
                              endOfLine:(NSString *)endOfLine
                             headerName:(NSString **)outName
                             headerBody:(NSString **)outBody {
  // returns a single header (including continuation lines and ending endOfLine)
  // using the supplied scanner
  //
  // output arguments may be nil for "don't care"
  //
  // returns nil if no header line found (but there's still an endOfLine
  // remaining in the headers)

  NSAssert([scanner charactersToBeSkipped] == nil, @"bad scanner");

  NSCharacterSet *wsSet = [NSCharacterSet whitespaceCharacterSet];

  NSString *name = nil;
  NSString *body = nil;

  if (outName) *outName = nil;
  if (outBody) *outBody = nil;

  NSMutableString *fullHeader = [NSMutableString string];

  // scan the first line
  if ([scanner scanUpToString:@":" intoString:&name]
      && [scanner scanString:@":" intoString:nil]
      && [scanner scanUpToString:endOfLine intoString:&body]
      && [scanner scanString:endOfLine intoString:nil]) {

    // add the first line to the mutable result string
    [fullHeader appendFormat:@"%@:%@%@", name, body, endOfLine];

    if (outName) *outName = name;

    // also copy any continuation lines for this header; continuation lines
    // begin with whitespace and end with endOfLine
    while (1) {
      NSString *copiedHeader = nil;
      NSString *copiedWS = nil;

      if ([scanner scanCharactersFromSet:wsSet intoString:&copiedWS]) {
        if ([scanner scanUpToString:endOfLine intoString:&copiedHeader]
            && [scanner scanString:endOfLine intoString:nil]) {

          [fullHeader appendFormat:@"%@%@%@", copiedWS, copiedHeader, endOfLine];
        }
      } else {
        // no more continuation lines
        break;
      }
    }

    if (outBody) {
      // the body of the header is the full header after the header name and
      // colon, minus the final endOfLine
      unsigned int prefixLen = [name length] + 1;
      unsigned int headerLen = [fullHeader length];
      unsigned int eolLen = [endOfLine length];

      if (headerLen > (prefixLen + eolLen)) {
        NSRange bodyRange = NSMakeRange(prefixLen,
                                        headerLen - prefixLen - eolLen);
        NSString *fullBody = [fullHeader substringWithRange:bodyRange];
        *outBody = [fullBody stringByTrimmingCharactersInSet:wsSet];
      }
    }
    return fullHeader;
  }
  return nil;
}

+ (NSString *)stringForHeader:(NSString *)headerName
                  fromHeaders:(NSString *)headers
                    endOfLine:(NSString *)endOfLine {
  if (headers) {
    // scan a header line, and return the body of the header

    NSScanner *hdrScanner = [NSScanner scannerWithString:headers];
    [hdrScanner setCharactersToBeSkipped:nil];

    while (1) {
      NSString *foundName = nil;
      NSString *foundBody = nil;

      NSString *headerLine = [self scanHeaderLineWithScanner:hdrScanner
                                                   endOfLine:endOfLine
                                                  headerName:&foundName
                                                  headerBody:&foundBody];
      if (headerLine == nil) break;

      if ([foundName caseInsensitiveCompare:headerName] == NSOrderedSame) {
        return foundBody;
      }
    }
  }

  // not found
  return nil;
}

+ (NSString *)headersSettingHeader:(NSString *)headerName
                         withValue:(NSString *)headerValue
                         inHeaders:(NSString *)headers
                         endOfLine:(NSString *)endOfLine {
  // take the headers passed in and replace the header named
  // "headerName" with the new headerValue (adding the header
  // if necessary)
  //
  // returns the new headers
  if (headers == nil) return nil;

  NSScanner *hdrScanner = [NSScanner scannerWithString:headers];
  [hdrScanner setCharactersToBeSkipped:nil];

  NSMutableString *newHeaders = [NSMutableString string];

  // NSScanner is case-insensitive by default

  // headers look like:<eol>
  //   header1: body<eol>
  //     more body<eol>
  //   header2: body<eol>
  //   <eol>

  while (1) {
    // scan a header line
    NSString *name = nil;

    NSString *headerLine = [self scanHeaderLineWithScanner:hdrScanner
                                                 endOfLine:endOfLine
                                                headerName:&name
                                                headerBody:nil];
    if (headerLine == nil) {
      // we're done copying (though the block still needs the extra endOfLine
      // at the end
      break;
    }

    if ([name caseInsensitiveCompare:headerName] == NSOrderedSame) {
      // skip copying this header since it's the one we're replacing
    } else {
      [newHeaders appendString:headerLine];
    }
  }

  // insert the replacement header at the end of the header block and add
  // the final eol
  [newHeaders appendFormat:@"%@: %@%@%@",
   headerName, headerValue, endOfLine, endOfLine];

  return newHeaders;
}

+ (NSString *)messageTextWithAlteredHeadersForMessageText:(NSString *)message
                                                endOfLine:(NSString *)endOfLine {
  NSString *headers = [self headersForMessageText:message
                                        endOfLine:endOfLine];
  if (headers == nil) return message;

  // if the body begins with <x-html>, set the content-type header to text/html
  unsigned int headerLen = [headers length];
  if ([message length] > headerLen + 8) {
    // 8 characters in <x-html>
    NSString *bodyStart;
    bodyStart = [message substringWithRange:NSMakeRange(headerLen, 8)];

    if ([bodyStart isEqual:@"<x-html>"]) {
      // found it; set the content-type header and append the message body to
      // the new headers
      NSString *newHeaders = [self headersSettingHeader:@"Content-Type"
                                              withValue:@"text/html"
                                              inHeaders:headers
                                              endOfLine:endOfLine];

      NSString *body = [message substringFromIndex:headerLen];
      message = [newHeaders stringByAppendingString:body];
    } else {
      // body doesn't begin with x-html
    }
  }
  return message;
}
@end
