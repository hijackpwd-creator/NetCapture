#pragma once
#import <Foundation/Foundation.h>
@interface NCRuntimePaths : NSObject
+ (NSString *)baseDirectory;
+ (NSString *)databasePath;
+ (NSString *)bodiesDirectory;
+ (NSString *)runtimeDirectory;
+ (NSString *)socketPath;
+ (BOOL)prepareDirectories:(NSError **)error;
@end
