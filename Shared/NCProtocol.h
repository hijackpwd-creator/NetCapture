#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

#define NC_WIRE_MAGIC 0x4E434150U
#define NC_WIRE_VERSION 2
#define NC_MAX_METADATA_SIZE (512U * 1024U)
#define NC_MAX_PAYLOAD_SIZE (256U * 1024U)

typedef NS_ENUM(uint16_t, NCMessageType) {
    NCMessageHello = 1,
    NCMessageTransactionBegin = 10,
    NCMessageHopBegin = 11,
    NCMessageHopResponse = 12,
    NCMessageRequestBody = 20,
    NCMessageRequestBodyEnd = 21,
    NCMessageResponseBody = 22,
    NCMessageResponseBodyEnd = 23,
    NCMessageHopMetrics = 30,
    NCMessageHopEnd = 31,
    NCMessageTransactionEnd = 32,
    NCMessagePing = 40,
};

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint16_t version;
    uint16_t type;
    uint32_t metadataLength;
    uint32_t payloadLength;
    uint64_t sequence;
} NCWireHeaderV2;

NSData * _Nullable NCBuildFrameV2(NCMessageType type, uint64_t sequence, NSDictionary *metadata, NSData * _Nullable payload, NSError **error);
BOOL NCDecodeWireHeaderV2(const void *bytes, NSUInteger length, NCWireHeaderV2 *headerOut, uint64_t *frameLengthOut);
NSDictionary * _Nullable NCDecodeMetadataV2(const uint8_t *bytes, NSUInteger length, NSError **error);
