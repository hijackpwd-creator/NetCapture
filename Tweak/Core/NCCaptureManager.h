#pragma once
#import <Foundation/Foundation.h>
@interface NCCaptureManager : NSObject
+ (instancetype)shared;
- (void)observeCreatedTask:(NSURLSessionTask *)task request:(NSURLRequest *)request;
- (void)taskWillResume:(NSURLSessionTask *)task;
- (void)task:(NSURLSessionTask *)task completionData:(NSData * _Nullable)data response:(NSURLResponse * _Nullable)response error:(NSError * _Nullable)error;
@end
