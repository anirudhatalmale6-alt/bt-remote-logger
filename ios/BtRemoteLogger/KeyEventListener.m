#import "KeyEventListener.h"
#import "EventWindow.h"
#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>

@implementation KeyEventListener {
  BOOL _isListening;
  BOOL _hasListeners;
  float _lastVolume;
  BOOL _volumeObserverActive;

  CGFloat _touchStartX;
  CGFloat _touchStartY;
  CGFloat _touchLastX;
  CGFloat _touchLastY;
  BOOL _touchTracking;

  BOOL _pendingVolumeKey;
  BOOL _pendingClick;
  NSTimer *_pendingTimer;

  NSTimeInterval _lastEmitTime;
}

static KeyEventListener *_shared = nil;
static CGFloat const kSwipeThreshold = 100.0;
static NSTimeInterval const kDetectWindowSec = 0.4;
static NSTimeInterval const kCooldownSec = 0.6;

+ (KeyEventListener *)shared {
  return _shared;
}

RCT_EXPORT_MODULE(KeyEventListener);

- (NSArray<NSString *> *)supportedEvents {
  return @[@"onButtonDetected"];
}

- (void)startObserving {
  _hasListeners = YES;
}

- (void)stopObserving {
  _hasListeners = NO;
}

+ (BOOL)requiresMainQueueSetup {
  return YES;
}

RCT_EXPORT_METHOD(startListening) {
  _shared = self;
  _isListening = YES;
  _lastEmitTime = 0;
  _pendingVolumeKey = NO;
  _pendingClick = NO;
  _touchTracking = NO;

  dispatch_async(dispatch_get_main_queue(), ^{
    [self setupVolumeMonitoring];
    [self setupGameController];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (self->_hasListeners && self->_isListening) {
        UIWindow *keyWindow = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
        BOOL isEW = [keyWindow isKindOfClass:[EventWindow class]];
        NSString *msg = isEW ? @"EventWindow active" : [NSString stringWithFormat:@"Window: %@", NSStringFromClass([keyWindow class])];

        [self sendEventWithName:@"onButtonDetected" body:@{
          @"buttonId": @"DIAG",
          @"label": msg,
          @"timestamp": @([[NSDate date] timeIntervalSince1970] * 1000)
        }];
      }
    });
  });
}

RCT_EXPORT_METHOD(stopListening) {
  if (_shared == self) {
    _shared = nil;
  }
  _isListening = NO;
  [self cancelPending];
  [self teardownVolumeMonitoring];
}

RCT_EXPORT_METHOD(addListener:(NSString *)eventName) {
}

RCT_EXPORT_METHOD(removeListeners:(double)count) {
}

RCT_EXPORT_METHOD(getDiagnostics:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *keyWindow = nil;
    if (@available(iOS 15.0, *)) {
      for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
          for (UIWindow *w in scene.windows) {
            if (w.isKeyWindow) { keyWindow = w; break; }
          }
        }
        if (keyWindow) break;
      }
    }
    if (!keyWindow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      keyWindow = UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
    }

    NSString *windowClass = keyWindow ? NSStringFromClass([keyWindow class]) : @"nil";
    BOOL isEventWindow = [keyWindow isKindOfClass:[EventWindow class]];
    NSArray *controllers = [GCController controllers];
    float volume = [AVAudioSession sharedInstance].outputVolume;

    resolve(@{
      @"windowClass": windowClass,
      @"eventWindowActive": @(isEventWindow),
      @"volumeMonitorActive": @(self->_volumeObserverActive),
      @"currentVolume": @(volume),
      @"connectedControllers": @(controllers.count),
      @"moduleActive": @(self->_isListening),
      @"hasListeners": @(self->_hasListeners),
      @"sendEventCount": @([EventWindow sendEventCount]),
      @"pressEventCount": @([EventWindow pressEventCount]),
      @"touchEventCount": @([EventWindow touchEventCount]),
    });
  });
}

#pragma mark - Cooldown

- (BOOL)isInCooldown {
  return ([[NSDate date] timeIntervalSince1970] - _lastEmitTime) < kCooldownSec;
}

#pragma mark - Volume Monitoring

- (void)setupVolumeMonitoring {
  if (_volumeObserverActive) return;

  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *error = nil;
  [session setCategory:AVAudioSessionCategoryAmbient error:&error];
  [session setActive:YES error:&error];
  _lastVolume = session.outputVolume;

  [session addObserver:self
            forKeyPath:@"outputVolume"
               options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
               context:nil];
  _volumeObserverActive = YES;
}

- (void)teardownVolumeMonitoring {
  if (!_volumeObserverActive) return;
  @try {
    [[AVAudioSession sharedInstance] removeObserver:self forKeyPath:@"outputVolume"];
  } @catch (NSException *e) {}
  _volumeObserverActive = NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
  if ([keyPath isEqualToString:@"outputVolume"]) {
    if (!_isListening || !_hasListeners) return;
    if ([self isInCooldown]) return;

    [self onVolumeKeyReceived];
  }
}

#pragma mark - Game Controller

- (void)setupGameController {
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(controllerConnected:)
                                               name:GCControllerDidConnectNotification
                                             object:nil];

  for (GCController *controller in [GCController controllers]) {
    [self configureController:controller];
  }
}

- (void)controllerConnected:(NSNotification *)notification {
  GCController *controller = notification.object;
  [self configureController:controller];
}

- (void)configureController:(GCController *)controller {
  __weak typeof(self) weakSelf = self;

  if (controller.extendedGamepad) {
    controller.extendedGamepad.dpad.up.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"ARROW_UP" label:@"Arrow Up"];
    };
    controller.extendedGamepad.dpad.down.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"ARROW_DOWN" label:@"Arrow Down"];
    };
    controller.extendedGamepad.dpad.left.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"ARROW_LEFT" label:@"Arrow Left"];
    };
    controller.extendedGamepad.dpad.right.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"ARROW_RIGHT" label:@"Arrow Right"];
    };
    controller.extendedGamepad.buttonA.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"HEART" label:@"Heart / Like button"];
    };
    controller.extendedGamepad.buttonB.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"GEAR" label:@"Gear button"];
    };
  }

  if (controller.microGamepad) {
    controller.microGamepad.dpad.up.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"ARROW_UP" label:@"Arrow Up"];
    };
    controller.microGamepad.dpad.down.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"ARROW_DOWN" label:@"Arrow Down"];
    };
    controller.microGamepad.dpad.left.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"ARROW_LEFT" label:@"Arrow Left"];
    };
    controller.microGamepad.dpad.right.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"ARROW_RIGHT" label:@"Arrow Right"];
    };
    controller.microGamepad.buttonA.pressedChangedHandler = ^(GCControllerButtonInput *btn, float value, BOOL pressed) {
      if (pressed) [weakSelf emitButton:@"HEART" label:@"Heart / Like button"];
    };
  }
}

#pragma mark - UIPress Handling

- (void)handlePress:(UIPress *)press action:(NSString *)action {
  if (!_isListening || !_hasListeners) return;
  if (![action isEqualToString:@"DOWN"] && ![action isEqualToString:@"DOWN_VIA_SEND"]) return;

  NSString *buttonId = nil;
  NSString *label = nil;

  if (@available(iOS 13.4, *)) {
    if (press.key) {
      UIKeyboardHIDUsage keyCode = press.key.keyCode;
      switch (keyCode) {
        case UIKeyboardHIDUsageKeyboardUpArrow:
          buttonId = @"ARROW_UP"; label = @"Arrow Up"; break;
        case UIKeyboardHIDUsageKeyboardDownArrow:
          buttonId = @"ARROW_DOWN"; label = @"Arrow Down"; break;
        case UIKeyboardHIDUsageKeyboardLeftArrow:
          buttonId = @"ARROW_LEFT"; label = @"Arrow Left"; break;
        case UIKeyboardHIDUsageKeyboardRightArrow:
          buttonId = @"ARROW_RIGHT"; label = @"Arrow Right"; break;
        case UIKeyboardHIDUsageKeyboardReturnOrEnter:
          buttonId = @"HEART"; label = @"Heart / Like button"; break;
        case UIKeyboardHIDUsageKeyboardEscape:
          buttonId = @"GEAR"; label = @"Gear button"; break;
        case UIKeyboardHIDUsageKeyboardSpacebar:
          buttonId = @"CAMERA"; label = @"Camera button"; break;
        default:
          buttonId = [NSString stringWithFormat:@"KEY_%ld", (long)keyCode];
          label = [NSString stringWithFormat:@"Key HID %ld", (long)keyCode];
          break;
      }
    }
  }

  if (!buttonId) {
    switch (press.type) {
      case UIPressTypeUpArrow:
        buttonId = @"ARROW_UP"; label = @"Arrow Up"; break;
      case UIPressTypeDownArrow:
        buttonId = @"ARROW_DOWN"; label = @"Arrow Down"; break;
      case UIPressTypeLeftArrow:
        buttonId = @"ARROW_LEFT"; label = @"Arrow Left"; break;
      case UIPressTypeRightArrow:
        buttonId = @"ARROW_RIGHT"; label = @"Arrow Right"; break;
      case UIPressTypeSelect:
        buttonId = @"HEART"; label = @"Heart / Like button"; break;
      case UIPressTypeMenu:
        buttonId = @"GEAR"; label = @"Gear button"; break;
      case UIPressTypePlayPause:
        buttonId = @"CAMERA"; label = @"Camera button"; break;
      default:
        buttonId = [NSString stringWithFormat:@"PRESS_%ld", (long)press.type];
        label = [NSString stringWithFormat:@"Press Type %ld", (long)press.type];
        break;
    }
  }

  if ([self isInCooldown]) return;
  [self emitButton:buttonId label:label];
}

#pragma mark - UITouch Handling

- (void)handleTouch:(UITouch *)touch {
  if (!_isListening || !_hasListeners) return;

  BOOL isExternalPointer = NO;
  if (@available(iOS 13.4, *)) {
    isExternalPointer = (touch.type == UITouchTypeIndirectPointer);
  }
  if (!isExternalPointer && touch.type == UITouchTypeIndirect) {
    isExternalPointer = YES;
  }
  if (!isExternalPointer) return;

  CGPoint location = [touch locationInView:nil];

  switch (touch.phase) {
    case UITouchPhaseBegan:
      _touchStartX = location.x;
      _touchStartY = location.y;
      _touchLastX = location.x;
      _touchLastY = location.y;
      _touchTracking = YES;
      break;

    case UITouchPhaseMoved:
      if (_touchTracking) {
        _touchLastX = location.x;
        _touchLastY = location.y;
      }
      break;

    case UITouchPhaseEnded:
    case UITouchPhaseCancelled:
      if (_touchTracking) {
        _touchLastX = location.x;
        _touchLastY = location.y;
        [self evaluateTouchGesture];
        _touchTracking = NO;
      }
      break;

    default:
      break;
  }
}

- (void)evaluateTouchGesture {
  if ([self isInCooldown]) return;

  CGFloat deltaX = _touchLastX - _touchStartX;
  CGFloat deltaY = _touchLastY - _touchStartY;
  CGFloat absDeltaX = fabs(deltaX);
  CGFloat absDeltaY = fabs(deltaY);

  if (absDeltaX > kSwipeThreshold || absDeltaY > kSwipeThreshold) {
    if (absDeltaY >= absDeltaX) {
      if (deltaY < 0) {
        [self emitButton:@"ARROW_UP" label:@"Arrow Up"];
      } else {
        [self emitButton:@"ARROW_DOWN" label:@"Arrow Down"];
      }
    } else {
      if (deltaX < 0) {
        [self emitButton:@"ARROW_LEFT" label:@"Arrow Left"];
      } else {
        [self emitButton:@"ARROW_RIGHT" label:@"Arrow Right"];
      }
    }
  } else {
    [self onClickReceived];
  }
}

#pragma mark - Deferred Detection (Camera/Gear/Heart)

- (void)onVolumeKeyReceived {
  if (_pendingClick) {
    [self cancelPending];
    [self emitButton:@"GEAR" label:@"Gear button"];
  } else {
    _pendingVolumeKey = YES;
    [self schedulePendingResolve];
  }
}

- (void)onClickReceived {
  if ([self isInCooldown]) return;

  if (_pendingVolumeKey) {
    [self cancelPending];
    [self emitButton:@"GEAR" label:@"Gear button"];
  } else {
    _pendingClick = YES;
    [self schedulePendingResolve];
  }
}

- (void)schedulePendingResolve {
  if (_pendingTimer != nil) return;

  __weak typeof(self) weakSelf = self;
  _pendingTimer = [NSTimer scheduledTimerWithTimeInterval:kDetectWindowSec
                                                  repeats:NO
                                                    block:^(NSTimer *timer) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;

    if ([strongSelf isInCooldown]) {
      strongSelf->_pendingVolumeKey = NO;
      strongSelf->_pendingClick = NO;
      strongSelf->_pendingTimer = nil;
      return;
    }

    if (strongSelf->_pendingVolumeKey && !strongSelf->_pendingClick) {
      [strongSelf emitButton:@"CAMERA" label:@"Camera button"];
    } else if (strongSelf->_pendingClick && !strongSelf->_pendingVolumeKey) {
      [strongSelf emitButton:@"HEART" label:@"Heart / Like button"];
    } else if (strongSelf->_pendingVolumeKey && strongSelf->_pendingClick) {
      [strongSelf emitButton:@"GEAR" label:@"Gear button"];
    }

    strongSelf->_pendingVolumeKey = NO;
    strongSelf->_pendingClick = NO;
    strongSelf->_pendingTimer = nil;
  }];
}

- (void)cancelPending {
  [_pendingTimer invalidate];
  _pendingTimer = nil;
  _pendingVolumeKey = NO;
  _pendingClick = NO;
}

#pragma mark - Emit

- (void)emitButton:(NSString *)buttonId label:(NSString *)label {
  _lastEmitTime = [[NSDate date] timeIntervalSince1970];
  [self cancelPending];

  if (!_hasListeners) return;

  [self sendEventWithName:@"onButtonDetected" body:@{
    @"buttonId": buttonId,
    @"label": label,
    @"timestamp": @([[NSDate date] timeIntervalSince1970] * 1000)
  }];
}

#pragma mark - Cleanup

- (void)dealloc {
  [self teardownVolumeMonitoring];
  [self cancelPending];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
