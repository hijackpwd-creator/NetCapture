#import "NCBodyWriter.h"
#import "../Model/NCServerModels.h"
#import "../../Shared/NCRuntimePaths.h"
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
static const uint64_t kLimit=32ULL*1024ULL*1024ULL;
@implementation NCBodyWriter
+ (instancetype)shared { static id x; static dispatch_once_t once; dispatch_once(&once,^{x=[self new];}); return x; }
- (BOOL)appendPayload:(NSData *)payload offset:(uint64_t)offset transaction:(NCServerTransaction *)tx hop:(NCServerHop *)hop state:(NCServerBodyState *)s {
    if (!payload.length || s.ended) return NO; uint64_t end=offset+payload.length; if (end<offset || offset!=s.expectedOffset) { s.corrupted=YES; s.truncated=YES; s.storeEnabled=NO; [self closeFileForState:s]; s.expectedOffset=end; s.receivedBytes=MAX(s.receivedBytes,end); return NO; }
    s.expectedOffset=end; s.receivedBytes=end; if (!s.storeEnabled) return YES;
    if (s.fd<0) { NSString *name=[NSString stringWithFormat:@"%@-hop-%lu-response.body",tx.storageIdentifier,(unsigned long)hop.index]; NSString *p=[[NCRuntimePaths bodiesDirectory] stringByAppendingPathComponent:name]; s.fd=open(p.fileSystemRepresentation,O_WRONLY|O_CREAT|O_TRUNC,0600); if (s.fd<0) { s.storeEnabled=NO; s.truncated=YES; return NO; } s.path=p; }
    uint64_t remain=(s.storedBytes<kLimit)?(kLimit-s.storedBytes):0; NSUInteger want=(NSUInteger)MIN(remain,(uint64_t)payload.length); const uint8_t *b=payload.bytes; NSUInteger done=0;
    while (done<want) { ssize_t n=write(s.fd,b+done,want-done); if (n>0) {done+=(NSUInteger)n; continue;} if (n<0 && errno==EINTR) continue; s.truncated=YES; s.storeEnabled=NO; [self closeFileForState:s]; return NO; }
    s.storedBytes+=done; if (done<payload.length) { s.truncated=YES; s.storeEnabled=NO; [self closeFileForState:s]; } return YES;
}
- (void)closeFileForState:(NCServerBodyState *)s { if (s.fd>=0) { close(s.fd); s.fd=-1; } }
@end
