#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface NCHeaderField : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *value;
@property(nonatomic, assign) NSUInteger index;
- (NSDictionary *)JSONObject;
@end
NSArray<NCHeaderField *> *NCHeaderListFromDictionary(NSDictionary *dictionary);
NSArray<NSDictionary *> *NCHeaderJSONList(NSArray<NCHeaderField *> *fields);
NS_ASSUME_NONNULL_END
