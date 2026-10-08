#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCCaptureManager : NSObject
+ (instancetype)shared;
- (void)observeCreatedTask:(NSURLSessionTask *)task request:(NSURLRequest *)request;
- (void)taskWillResume:(NSURLSessionTask *)task;
- (void)taskDidRequestCancel:(NSURLSessionTask *)task;
- (void)task:(NSURLSessionTask *)task
 completionData:(NSData * _Nullable)data
       response:(NSURLResponse * _Nullable)response
          error:(NSError * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
