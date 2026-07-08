#import <React/RCTEventEmitter.h>
#import <React/RCTBridgeModule.h>
#import <UIKit/UIKit.h>

@interface KeyEventListener : RCTEventEmitter <RCTBridgeModule>

+ (KeyEventListener *)shared;
- (void)handlePress:(UIPress *)press action:(NSString *)action;
- (void)handleTouch:(UITouch *)touch;
- (void)logOtherEventType:(NSInteger)eventType subtype:(NSInteger)subtype;

@end
