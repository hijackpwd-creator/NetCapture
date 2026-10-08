#import "NCHeaderField.h"
@implementation NCHeaderField
- (NSDictionary *)JSONObject { return @{ @"name": self.name ?: @"", @"value": self.value ?: @"", @"index": @(self.index) }; }
@end
NSArray<NCHeaderField *> *NCHeaderListFromDictionary(NSDictionary *dictionary) {
    NSMutableArray *out = [NSMutableArray array]; NSUInteger idx = 0;
    for (id key in dictionary) {
        id raw = dictionary[key];
        NCHeaderField *f = [NCHeaderField new]; f.name = [key description] ?: @""; f.value = [raw description] ?: @""; f.index = idx++;
        [out addObject:f];
    }
    return out;
}
NSArray<NSDictionary *> *NCHeaderJSONList(NSArray<NCHeaderField *> *fields) {
    NSMutableArray *out=[NSMutableArray arrayWithCapacity:fields.count]; for (NCHeaderField *f in fields) [out addObject:[f JSONObject]]; return out;
}
