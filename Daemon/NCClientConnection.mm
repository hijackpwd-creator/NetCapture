#import "NCClientConnection.h"
#import "../Shared/NCProtocol.h"
#import "NCTransactionAssembler.h"
#include <sys/socket.h>
#include <unistd.h>
#include <errno.h>
@interface NCClientConnection(){int _fd;dispatch_queue_t _queue;dispatch_source_t _src;NSMutableData*_buf;NSUInteger _off;uint64_t _lastSeq;BOOL _haveSeq,_hello,_closed;}@end
@implementation NCClientConnection
- (instancetype)initWithFD:(int)fd{if((self=[super init])){_fd=fd;_identifier=[NSUUID UUID].UUIDString;_queue=dispatch_queue_create("com.netcapture.client",DISPATCH_QUEUE_SERIAL);_buf=[NSMutableData data];}return self;}
- (void)start{dispatch_async(_queue,^{if(self->_closed)return;self->_src=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,self->_fd,0,self->_queue);__weak typeof(self)w=self;dispatch_source_set_event_handler(self->_src,^{[w readable];});dispatch_resume(self->_src);});}
- (void)readable{uint8_t tmp[65536];for(;;){ssize_t n=recv(_fd,tmp,sizeof(tmp),0);if(n>0){[_buf appendBytes:tmp length:n];if(_buf.length-_off>2*1024*1024){[self closeLocked];return;}[self parse];continue;}if(n==0){[self closeLocked];return;}if(errno==EINTR)continue;if(errno==EAGAIN||errno==EWOULDBLOCK)break;[self closeLocked];return;}}
- (void)parse{while(_buf.length-_off>=sizeof(NCWireHeaderV2)){const uint8_t*base=(const uint8_t*)_buf.bytes+_off;NCWireHeaderV2 h;uint64_t fl=0;if(!NCDecodeWireHeaderV2(base,_buf.length-_off,&h,&fl)){[self closeLocked];return;}if(fl>_buf.length-_off)break;NSError*err=nil;NSDictionary*m=NCDecodeMetadataV2(base+sizeof(NCWireHeaderV2),h.metadataLength,&err);if(!m){[self closeLocked];return;}if(_haveSeq && h.sequence<=_lastSeq){[self closeLocked];return;}_haveSeq=YES;_lastSeq=h.sequence;if(!_hello){if(h.type!=NCMessageHello){[self closeLocked];return;}_hello=YES;_sessionID=[m[@"session"] isKindOfClass:NSString.class]?m[@"session"]:@"";}else if(h.type!=NCMessageHello){NSData*p=h.payloadLength?[NSData dataWithBytes:base+sizeof(NCWireHeaderV2)+h.metadataLength length:h.payloadLength]:[NSData data];[[NCTransactionAssembler shared]receiveMessage:(NCMessageType)h.type metadata:m payload:p connection:self];} _off+=(NSUInteger)fl;}
    if(_off&&(_off>=262144||_off>=_buf.length/2)){if(_off==_buf.length){[_buf setLength:0];_off=0;}else{NSUInteger remain=_buf.length-_off;memmove(_buf.mutableBytes,(uint8_t*)_buf.mutableBytes+_off,remain);[_buf setLength:remain];_off=0;}}}
- (void)close{dispatch_async(_queue,^{[self closeLocked];});}
- (void)closeLocked{if(_closed)return;_closed=YES;if(_src){dispatch_source_cancel(_src);_src=nil;}if(_fd>=0){close(_fd);_fd=-1;}[[NCTransactionAssembler shared]connectionDidClose:self];void(^h)(NCClientConnection*)=_closeHandler;_closeHandler=nil;if(h)h(self);}
@end
