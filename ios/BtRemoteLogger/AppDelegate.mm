#import "AppDelegate.h"
#import "EventWindow.h"

#import <React/RCTBundleURLProvider.h>
#import <objc/runtime.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  self.moduleName = @"BtRemoteLogger";
  self.initialProps = @{};

  BOOL result = [super application:application didFinishLaunchingWithOptions:launchOptions];

  if (self.window && ![self.window isKindOfClass:[EventWindow class]]) {
    object_setClass(self.window, [EventWindow class]);
  }

  // Enable pointer lock on the root view controller. On iOS this is the only
  // way to receive raw GCMouse movement deltas (the Beauty-R1's arrows) —
  // without it the system owns the pointer and the app gets no movement.
  UIViewController *rootVC = self.window.rootViewController;
  if (rootVC) {
    [self enablePointerLockOnViewController:rootVC];
  }

  return result;
}

// Dynamically subclass the (RN-provided) root view controller's class and
// override -prefersPointerLocked to return YES. Using a runtime subclass
// (KVO-style) is safe regardless of what the base class actually is.
- (void)enablePointerLockOnViewController:(UIViewController *)vc
{
  if (@available(iOS 14.0, *)) {
    Class original = object_getClass(vc);
    NSString *subclassName = [NSString stringWithFormat:@"%@_PointerLock", NSStringFromClass(original)];
    Class subclass = NSClassFromString(subclassName);
    if (!subclass) {
      subclass = objc_allocateClassPair(original, subclassName.UTF8String, 0);
      if (subclass) {
        IMP imp = imp_implementationWithBlock(^BOOL(id _self) { return YES; });
        class_addMethod(subclass, @selector(prefersPointerLocked), imp, "B@:");
        objc_registerClassPair(subclass);
      }
    }
    if (subclass) {
      object_setClass(vc, subclass);
      [vc setNeedsUpdateOfPrefersPointerLocked];
    }
  }
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self bundleURL];
}

- (NSURL *)bundleURL
{
#if DEBUG
  return [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@"index"];
#else
  return [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];
#endif
}

@end
