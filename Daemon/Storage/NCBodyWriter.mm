#import "NCBodyWriter.h"
#import "../Model/NCServerModels.h"
#import "../../Shared/NCRuntimePaths.h"
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

static const uint64_t kNCBodyStorageLimit = 32ULL * 1024ULL * 1024ULL;

@implementation NCBodyWriter

+ (instancetype)shared {
    static NCBodyWriter *writer;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        writer = [[NCBodyWriter alloc] init];
    });
    return writer;
}

- (BOOL)openState:(NCServerBodyState *)state
      transaction:(NCServerTransaction *)transaction
              hop:(NCServerHop *)hop
        direction:(NSString *)direction {
    if (!state.storeEnabled) return NO;
    if (state.fd >= 0) return YES;

    NSString *safeDirection = [direction isEqualToString:@"request"] ? @"request" : @"response";
    NSString *name = [NSString stringWithFormat:@"%@-hop-%lu-%@.body",
                      transaction.storageIdentifier,
                      (unsigned long)hop.index,
                      safeDirection];
    NSString *path = [[NCRuntimePaths bodiesDirectory] stringByAppendingPathComponent:name];

    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd < 0) {
        state.storeEnabled = NO;
        state.truncated = YES;
        return NO;
    }

    state.fd = fd;
    state.path = path;
    return YES;
}

- (BOOL)appendPayload:(NSData *)payload
               offset:(uint64_t)offset
          transaction:(NCServerTransaction *)transaction
                  hop:(NCServerHop *)hop
            direction:(NSString *)direction
                state:(NCServerBodyState *)state {
    if (!payload.length || !transaction || !hop || !state || state.ended) return NO;

    uint64_t end = offset + (uint64_t)payload.length;
    if (end < offset || offset != state.expectedOffset) {
        state.corrupted = YES;
        state.truncated = YES;
        state.storeEnabled = NO;
        [self closeFileForState:state];
        if (end >= offset) {
            state.expectedOffset = end;
            state.receivedBytes = MAX(state.receivedBytes, end);
        }
        return NO;
    }

    state.expectedOffset = end;
    state.receivedBytes = end;

    if (!state.storeEnabled) return YES;
    if (state.storedBytes >= kNCBodyStorageLimit) {
        state.truncated = YES;
        state.storeEnabled = NO;
        [self closeFileForState:state];
        return YES;
    }

    if (![self openState:state transaction:transaction hop:hop direction:direction]) return NO;

    uint64_t remaining = kNCBodyStorageLimit - state.storedBytes;
    NSUInteger wanted = (NSUInteger)MIN(remaining, (uint64_t)payload.length);
    const uint8_t *bytes = (const uint8_t *)payload.bytes;
    NSUInteger written = 0;

    while (written < wanted) {
        ssize_t n = write(state.fd, bytes + written, wanted - written);
        if (n > 0) {
            written += (NSUInteger)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;

        state.truncated = YES;
        state.storeEnabled = NO;
        [self closeFileForState:state];
        return NO;
    }

    state.storedBytes += written;
    if (written < payload.length) {
        state.truncated = YES;
        state.storeEnabled = NO;
        [self closeFileForState:state];
    }
    return YES;
}

- (void)closeFileForState:(NCServerBodyState *)state {
    if (!state) return;
    if (state.fd >= 0) {
        close(state.fd);
        state.fd = -1;
    }
}

@end
