#import "NCClientConnection.h"
#import "NCTransactionAssembler.h"
#import "../Shared/NCProtocol.h"
#include <sys/socket.h>
#include <unistd.h>
#include <errno.h>

static const NSUInteger kNCMaxReceiveBuffer = 2U * 1024U * 1024U;
static const NSUInteger kNCCompactThreshold = 256U * 1024U;

@interface NCClientConnection () {
    int _fd;
    dispatch_queue_t _queue;
    dispatch_source_t _readSource;
    NSMutableData *_buffer;
    NSUInteger _readOffset;
    uint64_t _lastSequence;
    BOOL _hasSequence;
    BOOL _helloReceived;
    BOOL _closed;
}
@end

@implementation NCClientConnection

- (instancetype)initWithFD:(int)fd {
    self = [super init];
    if (self) {
        _fd = fd;
        _identifier = NSUUID.UUID.UUIDString;
        _queue = dispatch_queue_create("com.netcapture.client", DISPATCH_QUEUE_SERIAL);
        _buffer = [NSMutableData data];
    }
    return self;
}

- (void)start {
    dispatch_async(_queue, ^{
        if (self->_closed || self->_fd < 0 || self->_readSource) return;
        self->_readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, self->_fd, 0, self->_queue);
        if (!self->_readSource) {
            [self closeLocked];
            return;
        }
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(self->_readSource, ^{
            [weakSelf handleReadableLocked];
        });
        dispatch_resume(self->_readSource);
    });
}

- (BOOL)isAllowedCaptureMessageType:(uint16_t)type {
    switch ((NCMessageType)type) {
        case NCMessageTransactionBegin:
        case NCMessageHopBegin:
        case NCMessageHopResponse:
        case NCMessageRequestBody:
        case NCMessageRequestBodyEnd:
        case NCMessageResponseBody:
        case NCMessageResponseBodyEnd:
        case NCMessageHopMetrics:
        case NCMessageHopEnd:
        case NCMessageTransactionEnd:
        case NCMessagePing:
            return YES;
        default:
            return NO;
    }
}


- (BOOL)payloadShapeIsValidForHeader:(NCWireHeaderV2)header {
    switch ((NCMessageType)header.type) {
        case NCMessageRequestBody:
        case NCMessageResponseBody:
            return header.payloadLength > 0;
        default:
            return header.payloadLength == 0;
    }
}

- (BOOL)acceptSequence:(uint64_t)sequence {
    if (_hasSequence && sequence <= _lastSequence) return NO;
    _hasSequence = YES;
    _lastSequence = sequence;
    return YES;
}

- (BOOL)validateHello:(NSDictionary *)metadata header:(NCWireHeaderV2)header {
    if (header.payloadLength != 0) return NO;
    NSString *session = [metadata[@"session"] isKindOfClass:NSString.class] ? metadata[@"session"] : nil;
    NSString *role = [metadata[@"role"] isKindOfClass:NSString.class] ? metadata[@"role"] : nil;
    NSNumber *protocol = [metadata[@"protocol"] isKindOfClass:NSNumber.class] ? metadata[@"protocol"] : nil;
    if (!session.length || ![role isEqualToString:@"capture"] || protocol.unsignedIntegerValue != NC_WIRE_VERSION) return NO;
    self.sessionID = session;
    return YES;
}

- (void)handleReadableLocked {
    uint8_t temporary[64 * 1024];
    for (;;) {
        ssize_t n = recv(_fd, temporary, sizeof(temporary), 0);
        if (n > 0) {
            [_buffer appendBytes:temporary length:(NSUInteger)n];
            if (_buffer.length - _readOffset > kNCMaxReceiveBuffer) {
                [self closeLocked];
                return;
            }
            [self parseFramesLocked];
            if (_closed) return;
            continue;
        }
        if (n == 0) {
            [self closeLocked];
            return;
        }
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) break;
        [self closeLocked];
        return;
    }
}

- (void)parseFramesLocked {
    while (_buffer.length - _readOffset >= sizeof(NCWireHeaderV2)) {
        const uint8_t *base = (const uint8_t *)_buffer.bytes + _readOffset;
        NSUInteger available = _buffer.length - _readOffset;

        NCWireHeaderV2 header;
        uint64_t frameLength = 0;
        if (!NCDecodeWireHeaderV2(base, available, &header, &frameLength)) {
            [self closeLocked];
            return;
        }
        if (frameLength > available) break;
        if (![self acceptSequence:header.sequence]) {
            [self closeLocked];
            return;
        }

        NSError *error = nil;
        NSDictionary *metadata = NCDecodeMetadataV2(base + sizeof(NCWireHeaderV2), header.metadataLength, &error);
        if (!metadata) {
            [self closeLocked];
            return;
        }

        if (!_helloReceived) {
            if (header.type != NCMessageHello || ![self validateHello:metadata header:header]) {
                [self closeLocked];
                return;
            }
            _helloReceived = YES;
        } else {
            if (header.type == NCMessageHello ||
                ![self isAllowedCaptureMessageType:header.type] ||
                ![self payloadShapeIsValidForHeader:header]) {
                [self closeLocked];
                return;
            }

            if (header.type != NCMessagePing) {
                NSData *payload = header.payloadLength
                    ? [NSData dataWithBytes:base + sizeof(NCWireHeaderV2) + header.metadataLength length:header.payloadLength]
                    : NSData.data;
                [[NCTransactionAssembler shared] receiveMessage:(NCMessageType)header.type
                                                       metadata:metadata
                                                        payload:payload
                                                     connection:self];
            }
        }

        _readOffset += (NSUInteger)frameLength;
    }

    if (_readOffset && (_readOffset >= kNCCompactThreshold || _readOffset >= _buffer.length / 2)) {
        if (_readOffset == _buffer.length) {
            [_buffer setLength:0];
            _readOffset = 0;
        } else {
            NSUInteger remaining = _buffer.length - _readOffset;
            memmove(_buffer.mutableBytes, (uint8_t *)_buffer.mutableBytes + _readOffset, remaining);
            [_buffer setLength:remaining];
            _readOffset = 0;
        }
    }
}

- (void)close {
    dispatch_async(_queue, ^{
        [self closeLocked];
    });
}

- (void)closeLocked {
    if (_closed) return;
    _closed = YES;

    if (_readSource) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }
    if (_fd >= 0) {
        close(_fd);
        _fd = -1;
    }

    [[NCTransactionAssembler shared] connectionDidClose:self];

    void (^handler)(NCClientConnection *) = _closeHandler;
    _closeHandler = nil;
    if (handler) handler(self);
}

@end
