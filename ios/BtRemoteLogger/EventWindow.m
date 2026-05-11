#import "EventWindow.h"
#import "KeyEventListener.h"

static NSInteger _sendEventCount = 0;
static NSInteger _pressEventCount = 0;
static NSInteger _touchEventCount = 0;

@implementation EventWindow

+ (NSInteger)sendEventCount { return _sendEventCount; }
+ (NSInteger)pressEventCount { return _pressEventCount; }
+ (NSInteger)touchEventCount { return _touchEventCount; }
+ (void)resetCounts { _sendEventCount = 0; _pressEventCount = 0; _touchEventCount = 0; }

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
  _pressEventCount++;
  KeyEventListener *listener = [KeyEventListener shared];
  if (listener) {
    for (UIPress *press in presses) {
      [listener handlePress:press action:@"DOWN"];
    }
  }
  [super pressesBegan:presses withEvent:event];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
  KeyEventListener *listener = [KeyEventListener shared];
  if (listener) {
    for (UIPress *press in presses) {
      [listener handlePress:press action:@"UP"];
    }
  }
  [super pressesEnded:presses withEvent:event];
}

- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
  [super pressesCancelled:presses withEvent:event];
}

- (void)sendEvent:(UIEvent *)event {
  _sendEventCount++;
  KeyEventListener *listener = [KeyEventListener shared];

  if (event.type == UIEventTypeTouches && listener) {
    _touchEventCount++;
    NSSet<UITouch *> *touches = [event allTouches];
    for (UITouch *touch in touches) {
      [listener handleTouch:touch];
    }
  }

  if (event.type == UIEventTypePresses && listener) {
    _pressEventCount++;
    if ([event isKindOfClass:[UIPressesEvent class]]) {
      UIPressesEvent *pressEvent = (UIPressesEvent *)event;
      NSSet<UIPress *> *presses = [pressEvent allPresses];
      for (UIPress *press in presses) {
        if (press.phase == UIPressPhaseBegan) {
          [listener handlePress:press action:@"DOWN_VIA_SEND"];
        }
      }
    }
  }

  [super sendEvent:event];
}

@end
