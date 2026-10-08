#import "NCRuntimePaths.h"
#include <sys/stat.h>
#include <errno.h>

@implementation NCRuntimePaths
+ (NSString *)baseDirectory { return @"/var/mobile/Library/NetCapture"; }
+ (NSString *)databasePath { return [[self baseDirectory] stringByAppendingPathComponent:@"capture.sqlite3"]; }
+ (NSString *)bodiesDirectory { return [[self baseDirectory] stringByAppendingPathComponent:@"Bodies"]; }
+ (NSString *)runtimeDirectory { return [[self baseDirectory] stringByAppendingPathComponent:@"Runtime"]; }
+ (NSString *)socketPath { return [[self runtimeDirectory] stringByAppendingPathComponent:@"ncap.sock"]; }

+ (BOOL)prepareDirectories:(NSError * _Nullable * _Nullable)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *path in @[[self baseDirectory], [self bodiesDirectory], [self runtimeDirectory]]) {
        if (![fm createDirectoryAtPath:path
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:error]) {
            return NO;
        }
        if (chmod(path.fileSystemRepresentation, 0700) != 0) {
            if (error) {
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSFilePathErrorKey:path}];
            }
            return NO;
        }
    }
    return YES;
}
@end
