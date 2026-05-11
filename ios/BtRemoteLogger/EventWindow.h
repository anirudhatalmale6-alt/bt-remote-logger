#import <UIKit/UIKit.h>

@interface EventWindow : UIWindow

+ (NSInteger)sendEventCount;
+ (NSInteger)pressEventCount;
+ (NSInteger)touchEventCount;
+ (void)resetCounts;

@end
