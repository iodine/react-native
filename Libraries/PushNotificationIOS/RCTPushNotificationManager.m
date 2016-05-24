/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTPushNotificationManager.h"

#import "RCTBridge.h"
#import "RCTConvert.h"
#import "RCTEventDispatcher.h"
#import "RCTUtils.h"

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_8_0

#define UIUserNotificationTypeAlert UIRemoteNotificationTypeAlert
#define UIUserNotificationTypeBadge UIRemoteNotificationTypeBadge
#define UIUserNotificationTypeSound UIRemoteNotificationTypeSound
#define UIUserNotificationTypeNone  UIRemoteNotificationTypeNone
#define UIUserNotificationType      UIRemoteNotificationType

#endif

NSString *const RCTLocalNotificationReceived = @"LocalNotificationReceived";
NSString *const RCTRemoteNotificationReceived = @"RemoteNotificationReceived";
NSString *const RCTRemoteNotificationsRegistered = @"RemoteNotificationsRegistered";

@implementation RCTConvert (UILocalNotification)

+ (UILocalNotification *)UILocalNotification:(id)json
{
  NSDictionary<NSString *, id> *details = [self NSDictionary:json];
  UILocalNotification *notification = [UILocalNotification new];
  notification.fireDate = [RCTConvert NSDate:details[@"fireDate"]] ?: [NSDate date];
  notification.alertBody = [RCTConvert NSString:details[@"alertBody"]] ?: nil;
  notification.soundName = [RCTConvert NSString:details[@"soundName"]] ?: nil;
  notification.applicationIconBadgeNumber = [RCTConvert NSInteger:details[@"badgeCount"]] ?: nil;
  notification.userInfo = [RCTConvert NSDictionary:details[@"userInfo"]] ?: nil;
  if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
    notification.category = [RCTConvert NSString:details[@"category"]] ?: nil;
  }
  return notification;
}

@end

@implementation RCTPushNotificationManager
{
  NSDictionary *_initialNotification;
}


RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setBridge:(RCTBridge *)bridge
{
  _bridge = bridge;

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleLocalNotificationReceived:)
                                               name:RCTLocalNotificationReceived
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleRemoteNotificationReceived:)
                                               name:RCTRemoteNotificationReceived
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleRemoteNotificationsRegistered:)
                                               name:RCTRemoteNotificationsRegistered
                                             object:nil];

  if (bridge.launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]) {
    _initialNotification =
      [bridge.launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey] copy];
  } else if (bridge.launchOptions[UIApplicationLaunchOptionsLocalNotificationKey]) {
    UILocalNotification *localNotification =
      [bridge.launchOptions[UIApplicationLaunchOptionsLocalNotificationKey] copy];

    _initialNotification = [RCTPushNotificationManager extractLocalNotificationData:localNotification withActionIdentifier:nil];
  }
}

- (NSDictionary<NSString *, id> *)constantsToExport
{
  return @{@"initialNotification": RCTNullIfNil(_initialNotification)};
}

+ (void)didRegisterUserNotificationSettings:(__unused UIUserNotificationSettings *)notificationSettings
{
  if ([UIApplication instancesRespondToSelector:@selector(registerForRemoteNotifications)]) {
    [RCTSharedApplication() registerForRemoteNotifications];
  }
}

+ (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
  NSMutableString *hexString = [NSMutableString string];
  NSUInteger deviceTokenLength = deviceToken.length;
  const unsigned char *bytes = deviceToken.bytes;
  for (NSUInteger i = 0; i < deviceTokenLength; i++) {
    [hexString appendFormat:@"%02x", bytes[i]];
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:RCTRemoteNotificationsRegistered
                                                      object:self
                                                    userInfo:@{@"deviceToken" : [hexString copy]}];
}

+ (void)didReceiveRemoteNotification:(NSDictionary *)notification
{
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:notification];
  UIApplication* application = RCTSharedApplication();
  if (application.applicationState == UIApplicationStateActive) {
    userInfo[@"applicationState"] = @"active";
  } else {
    userInfo[@"applicationState"] = @"background";
  }

  [[NSNotificationCenter defaultCenter] postNotificationName:RCTRemoteNotificationReceived
                                                      object:self
                                                    userInfo:userInfo];
}

+ (void)didReceiveLocalNotification:(UILocalNotification *)notification
{
  NSDictionary *baseNotificationData = [RCTPushNotificationManager extractLocalNotificationData:notification
                                                                           withActionIdentifier:nil];
  NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:baseNotificationData];
  if (notification.alertBody) {
    details[@"alertBody"] = notification.alertBody;
  }
  if (notification.userInfo) {
    details[@"userInfo"] = RCTJSONClean(notification.userInfo);
  }

  UIApplication* application = RCTSharedApplication();
  if (application.applicationState == UIApplicationStateActive) {
    details[@"applicationState"] = @"active";
  } else {
    details[@"applicationState"] = @"background";
  }

  [[NSNotificationCenter defaultCenter] postNotificationName:RCTLocalNotificationReceived
                                                      object:self
                                                    userInfo:details];
}

- (void)handleLocalNotificationReceived:(NSNotification *)notification
{
  /* TODO(brentvatne): */
  /* Need to check if it has an action associated with it and only set as initialNotification
   * in that case. Revisit later, time constrained at moment and is harmless */
  _initialNotification = [notification userInfo];
  [_bridge.eventDispatcher sendDeviceEventWithName:@"localNotificationReceived"
                                              body:notification.userInfo];
}

- (void)handleRemoteNotificationReceived:(NSNotification *)notification
{
  [_bridge.eventDispatcher sendDeviceEventWithName:@"remoteNotificationReceived"
                                              body:notification.userInfo];
}

- (void)handleRemoteNotificationsRegistered:(NSNotification *)notification
{
  [_bridge.eventDispatcher sendDeviceEventWithName:@"remoteNotificationsRegistered"
                                              body:notification.userInfo];
}

+ (NSDictionary*)extractLocalNotificationData:(UILocalNotification *)localNotification withActionIdentifier:(nullable NSString *)identifier {
  NSDictionary *baseNotificationData = @{
    @"aps": @{
      @"alert": localNotification.alertBody,
      @"sound": localNotification.soundName?: @"",
      @"badge": @(localNotification.applicationIconBadgeNumber)?: @0
    },
    @"userInfo": localNotification.userInfo
  };

  NSMutableDictionary *notificationData = [NSMutableDictionary dictionaryWithDictionary:baseNotificationData];

  if (localNotification.fireDate) {
    notificationData[@"fireDate"] = [NSString stringWithFormat:@"%d",(int)[localNotification.fireDate timeIntervalSince1970]];
  }

  if (identifier) {
    notificationData[@"actionIdentifier"] = identifier;
  }

  return notificationData;
}

/* note(brentvatne): */
/* Could rewrite this as pop as well, just would need to clear the _initialNotification value */
RCT_EXPORT_METHOD(getInitialNotification:(RCTResponseSenderBlock)callback)
{
  callback(@[
    RCTNullIfNil(_initialNotification)
  ]);
}

/**
 * Update the application icon badge number on the home screen
 */
RCT_EXPORT_METHOD(setApplicationIconBadgeNumber:(NSInteger)number)
{
  RCTSharedApplication().applicationIconBadgeNumber = number;
}

/**
 * Get the current application icon badge number on the home screen
 */
RCT_EXPORT_METHOD(getApplicationIconBadgeNumber:(RCTResponseSenderBlock)callback)
{
  callback(@[@(RCTSharedApplication().applicationIconBadgeNumber)]);
}

RCT_EXPORT_METHOD(requestPermissions:(NSDictionary *)permissions)
{
  if (RCTRunningInAppExtension()) {
    return;
  }

  UIUserNotificationType types = UIUserNotificationTypeNone;
  if (permissions) {
    if ([RCTConvert BOOL:permissions[@"alert"]]) {
      types |= UIUserNotificationTypeAlert;
    }
    if ([RCTConvert BOOL:permissions[@"badge"]]) {
      types |= UIUserNotificationTypeBadge;
    }
    if ([RCTConvert BOOL:permissions[@"sound"]]) {
      types |= UIUserNotificationTypeSound;
    }
  } else {
    types = UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound;
  }

  UIApplication *app = RCTSharedApplication();
  if ([app respondsToSelector:@selector(registerUserNotificationSettings:)]) {
    UIUserNotificationSettings *notificationSettings =
      [UIUserNotificationSettings settingsForTypes:(NSUInteger)types categories:nil];
    [app registerUserNotificationSettings:notificationSettings];
  } else {
    [app registerForRemoteNotificationTypes:(NSUInteger)types];
  }
}

RCT_EXPORT_METHOD(abandonPermissions)
{
  [RCTSharedApplication() unregisterForRemoteNotifications];
}

RCT_EXPORT_METHOD(checkPermissions:(RCTResponseSenderBlock)callback)
{
  if (RCTRunningInAppExtension()) {
    callback(@[@{@"alert": @NO, @"badge": @NO, @"sound": @NO}]);
    return;
  }

  NSUInteger types = 0;
  if ([UIApplication instancesRespondToSelector:@selector(currentUserNotificationSettings)]) {
    types = [RCTSharedApplication() currentUserNotificationSettings].types;
  } else {

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_8_0

    types = [RCTSharedApplication() enabledRemoteNotificationTypes];

#endif

  }

  callback(@[@{
    @"alert": @((types & UIUserNotificationTypeAlert) > 0),
    @"badge": @((types & UIUserNotificationTypeBadge) > 0),
    @"sound": @((types & UIUserNotificationTypeSound) > 0),
  }]);
}

RCT_EXPORT_METHOD(presentLocalNotification:(UILocalNotification *)notification)
{
  [RCTSharedApplication() presentLocalNotificationNow:notification];
}

RCT_EXPORT_METHOD(scheduleLocalNotification:(UILocalNotification *)notification)
{
  [RCTSharedApplication() scheduleLocalNotification:notification];
}

RCT_EXPORT_METHOD(cancelAllLocalNotifications)
{
  [RCTSharedApplication() cancelAllLocalNotifications];
}

RCT_EXPORT_METHOD(cancelLocalNotifications:(NSDictionary *)userInfo)
{
  for (UILocalNotification *notification in RCTSharedApplication().scheduledLocalNotifications) {
    __block BOOL matchesAll = YES;
    NSDictionary *notificationInfo = notification.userInfo;
    [userInfo enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
      if (![notificationInfo[key] isEqual:obj]) {
        matchesAll = NO;
        *stop = YES;
      }
    }];
    if (matchesAll) {
      [RCTSharedApplication() cancelLocalNotification:notification];
    }
  }
}

RCT_EXPORT_METHOD(registerNotificationActionsForCategory:(NSDictionary*)actionsForCategory)
{
  if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0 && actionsForCategory) {
    NSMutableArray *actions = [[NSMutableArray alloc] init];

    if (actionsForCategory[@"actions"]) {
      for (NSDictionary *actionConfig in actionsForCategory[@"actions"]) {
        UIMutableUserNotificationAction *action = [[UIMutableUserNotificationAction alloc] init];
        [action setActivationMode:UIUserNotificationActivationModeBackground];
        [action setTitle:actionConfig[@"title"]];
        [action setIdentifier:actionConfig[@"id"]];
        [action setDestructive:NO];
        [action setAuthenticationRequired:YES];
        [actions addObject:action];
      }
    }

    UIMutableUserNotificationCategory *actionCategory;
    actionCategory = [[UIMutableUserNotificationCategory alloc] init];
    [actionCategory setIdentifier:actionsForCategory[@"id"]];
    [actionCategory setActions:actions
                    forContext:UIUserNotificationActionContextDefault];

    NSSet *categories = [NSSet setWithObject:actionCategory];

    UIUserNotificationType types = [[RCTSharedApplication() currentUserNotificationSettings] types];

    UIUserNotificationSettings *settings;
    settings = [UIUserNotificationSettings settingsForTypes:types
                                                 categories:categories];

    [RCTSharedApplication() registerUserNotificationSettings:settings];
  }
}

@end
