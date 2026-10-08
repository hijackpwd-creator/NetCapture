#import <Foundation/Foundation.h>
#import "../Shared/NCRuntimePaths.h"
#import "Storage/NCDatabase.h"
#import "NCIPCServer.h"
int main(int argc,char**argv){@autoreleasepool{NSError*e=nil;if(![NCRuntimePaths prepareDirectories:&e]){NSLog(@"[NetCapture] dirs: %@",e);return 1;}if(![[NCDatabase shared]start])NSLog(@"[NetCapture] DB unavailable");NCIPCServer*s=[NCIPCServer new];if(![s start])return 2;NSLog(@"[NetCapture] daemon ready");dispatch_main();}return 0;}
