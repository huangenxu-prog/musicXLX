#import "AppDelegate.h"
#import <ReactNativeNavigation/ReactNativeNavigation.h>
#import <React/RCTBundleURLProvider.h>
#import <React/RCTBridgeModule.h>
#import <UIKit/UIKit.h>

@interface LXScreenControlModule : NSObject <RCTBridgeModule>
@end

@implementation LXScreenControlModule

RCT_EXPORT_MODULE(LXScreenControlModule)

RCT_EXPORT_METHOD(setIdleTimerDisabled:(BOOL)disabled)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [UIApplication sharedApplication].idleTimerDisabled = disabled;
  });
}

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  RCTBridge *bridge = [[RCTBridge alloc] initWithDelegate:self launchOptions:launchOptions];
  [ReactNativeNavigation bootstrapWithBridge:bridge];
  self.initialProps = @{};
  return YES;
}

- (NSArray<id<RCTBridgeModule>> *)extraModulesForBridge:(RCTBridge *)bridge {
  return [ReactNativeNavigation extraModulesForBridge:bridge];
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self getBundleURL];
}
- (NSURL *)getBundleURL
{
#if DEBUG
  return [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@"index"];
#else
  return [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];
#endif
}

@end
