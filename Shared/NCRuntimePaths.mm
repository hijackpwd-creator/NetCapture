#import "NCRuntimePaths.h"
@implementation NCRuntimePaths
+ (NSString *)baseDirectory { return @"/var/mobile/Library/NetCapture"; }
+ (NSString *)databasePath { return [[self baseDirectory] stringByAppendingPathComponent:@"capture.sqlite3"]; }
+ (NSString *)bodiesDirectory { return [[self baseDirectory] stringByAppendingPathComponent:@"Bodies"]; }
+ (NSString *)runtimeDirectory { return [[self baseDirectory] stringByAppendingPathComponent:@"Runtime"]; }
+ (NSString *)socketPath { return [[self runtimeDirectory] stringByAppendingPathComponent:@"ncap.sock"]; }
+ (BOOL)prepareDirectories:(NSError **)error {
    NSFileManager *fm=[NSFileManager defaultManager];
    for (NSString *p in @[[self baseDirectory],[self bodiesDirectory],[self runtimeDirectory]]) {
        if (![fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@(0700)} error:error]) return NO;
    }
    return YES;
}
@end
