#import "NCProtocol.h"
#include <arpa/inet.h>

static uint64_t NCHtonll(uint64_t x) {
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    return ((uint64_t)htonl((uint32_t)(x & 0xffffffffULL)) << 32) | htonl((uint32_t)(x >> 32));
#else
    return x;
#endif
}
static uint64_t NCNtohll(uint64_t x) { return NCHtonll(x); }

NSData *NCBuildFrameV2(NCMessageType type, uint64_t sequence, NSDictionary *metadata, NSData *payload, NSError **error) {
    NSData *json=[NSJSONSerialization dataWithJSONObject:metadata ?: @{} options:0 error:error]; if (!json) return nil;
    if (json.length > NC_MAX_METADATA_SIZE || payload.length > NC_MAX_PAYLOAD_SIZE) return nil;
    NCWireHeaderV2 h={ htonl(NC_WIRE_MAGIC), htons(NC_WIRE_VERSION), htons(type), htonl((uint32_t)json.length), htonl((uint32_t)payload.length), NCHtonll(sequence) };
    NSMutableData *out=[NSMutableData dataWithCapacity:sizeof(h)+json.length+payload.length]; [out appendBytes:&h length:sizeof(h)]; [out appendData:json]; if (payload.length) [out appendData:payload]; return out;
}
BOOL NCDecodeWireHeaderV2(const void *bytes, NSUInteger length, NCWireHeaderV2 *headerOut, uint64_t *frameLengthOut) {
    if (length < sizeof(NCWireHeaderV2)) return NO; NCWireHeaderV2 w; memcpy(&w,bytes,sizeof(w));
    NCWireHeaderV2 h={ ntohl(w.magic), ntohs(w.version), ntohs(w.type), ntohl(w.metadataLength), ntohl(w.payloadLength), NCNtohll(w.sequence) };
    if (h.magic!=NC_WIRE_MAGIC || h.version!=NC_WIRE_VERSION || h.metadataLength>NC_MAX_METADATA_SIZE || h.payloadLength>NC_MAX_PAYLOAD_SIZE) return NO;
    uint64_t n=sizeof(NCWireHeaderV2)+(uint64_t)h.metadataLength+(uint64_t)h.payloadLength; if (headerOut) *headerOut=h; if (frameLengthOut) *frameLengthOut=n; return YES;
}
NSDictionary *NCDecodeMetadataV2(const uint8_t *bytes, NSUInteger length, NSError **error) {
    NSData *d=[NSData dataWithBytes:bytes length:length]; id obj=[NSJSONSerialization JSONObjectWithData:d options:0 error:error]; return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}
