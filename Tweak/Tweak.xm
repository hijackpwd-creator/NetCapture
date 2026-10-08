#import <Foundation/Foundation.h>
#import "Hook/NCURLSessionHook.h"
static BOOL NCShouldLoad(void){NSString*p=[NSProcessInfo processInfo].processName?:@"";if([p isEqualToString:@"netcaptured"])return NO;NSString*b=[NSBundle mainBundle].bundleIdentifier?:@"";NSString*allow=[[[NSProcessInfo processInfo] environment] objectForKey:@"NC_CAPTURE_BUNDLE"];if(allow.length)return [b isEqualToString:allow];return [b isEqualToString:@"com.example.NetCaptureTest"];}
%ctor { @autoreleasepool { if(NCShouldLoad()) NCInstallURLSessionHooks(); } }
