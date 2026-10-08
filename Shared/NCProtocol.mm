#import "NCProtocol.h"
#include <arpa/inet.h>

static uint64_t NCHostToNetwork64(uint64_t value) {
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    return ((uint64_t)htonl((uint32_t)(value & 0xffffffffULL)) << 32) |
           htonl((uint32_t)(value >> 32));
#else
    return value;
#endif
}

static uint64_t NCNetworkToHost64(uint64_t value) {
    return NCHostToNetwork64(value);
}

NSData * _Nullable NCBuildFrameV2(NCMessageType type,
                       uint64_t sequence,
                       NSDictionary *metadata,
                       NSData *payload,
                       NSError * _Nullable * _Nullable error) {
    NSDictionary *safeMetadata = metadata ?: @{};
    if (![NSJSONSerialization isValidJSONObject:safeMetadata]) return nil;

    NSData *json = [NSJSONSerialization dataWithJSONObject:safeMetadata options:0 error:error];
    if (!json) return nil;
    if (json.length > NC_MAX_METADATA_SIZE || payload.length > NC_MAX_PAYLOAD_SIZE) return nil;

    NCWireHeaderV2 header = {
        htonl(NC_WIRE_MAGIC),
        htons(NC_WIRE_VERSION),
        htons((uint16_t)type),
        htonl((uint32_t)json.length),
        htonl((uint32_t)payload.length),
        NCHostToNetwork64(sequence)
    };

    NSMutableData *frame = [NSMutableData dataWithCapacity:sizeof(header) + json.length + payload.length];
    [frame appendBytes:&header length:sizeof(header)];
    [frame appendData:json];
    if (payload.length) [frame appendData:payload];
    return frame;
}

BOOL NCDecodeWireHeaderV2(const void *bytes,
                          NSUInteger length,
                          NCWireHeaderV2 *headerOut,
                          uint64_t *frameLengthOut) {
    if (!bytes || length < sizeof(NCWireHeaderV2)) return NO;

    NCWireHeaderV2 wireHeader;
    memcpy(&wireHeader, bytes, sizeof(wireHeader));

    NCWireHeaderV2 header = {
        ntohl(wireHeader.magic),
        ntohs(wireHeader.version),
        ntohs(wireHeader.type),
        ntohl(wireHeader.metadataLength),
        ntohl(wireHeader.payloadLength),
        NCNetworkToHost64(wireHeader.sequence)
    };

    if (header.magic != NC_WIRE_MAGIC || header.version != NC_WIRE_VERSION) return NO;
    if (header.metadataLength > NC_MAX_METADATA_SIZE || header.payloadLength > NC_MAX_PAYLOAD_SIZE) return NO;

    uint64_t frameLength = sizeof(NCWireHeaderV2) +
                           (uint64_t)header.metadataLength +
                           (uint64_t)header.payloadLength;
    if (frameLength < sizeof(NCWireHeaderV2)) return NO;

    if (headerOut) *headerOut = header;
    if (frameLengthOut) *frameLengthOut = frameLength;
    return YES;
}

NSDictionary * _Nullable NCDecodeMetadataV2(const uint8_t *bytes, NSUInteger length, NSError * _Nullable * _Nullable error) {
    if (!bytes && length != 0) return nil;
    NSData *data = [NSData dataWithBytes:bytes length:length];
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}
