#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NCRuntimePaths : NSObject
+ (NSString *)baseDirectory;
+ (NSString *)databasePath;
+ (NSString *)bodiesDirectory;
+ (NSString *)runtimeDirectory;
+ (NSString *)socketPath;
+ (BOOL)prepareDirectories:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
