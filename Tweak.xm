// =============================================================
//  DeepBlockNetwork — 深度断网插件
//  双指长按手势（基于 UIApplication sendEvent:，不会被拦截）
// =============================================================
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/socket.h>
#import <dlfcn.h>
#import <errno.h>
#import <arpa/inet.h>
#import <netdb.h>
#import "fishhook.h"

// ---------- 配置 ----------
static NSArray *kWhitelistDomains = @[];

static BOOL DKIsBlockEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DeepBlockNetworkEnabled"];
}

static BOOL DKShouldBlockConnection(const struct sockaddr *addr) {
    if (!DKIsBlockEnabled()) return NO;
    return YES;
}

// ---------- 原始 connect ----------
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);

int hooked_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (DKShouldBlockConnection(addr)) {
        errno = ECONNREFUSED;
        return -1;
    }
    return orig_connect(sockfd, addr, addrlen);
}

static void install_connect_hook(void) {
    struct rebinding rebind;
    rebind.name = "connect";
    rebind.replacement = (void *)hooked_connect;
    rebind.replaced = (void **)&orig_connect;
    rebind_symbols(&rebind, 1);
    NSLog(@"[DeepBlockNetwork] connect hook installed");
}

// ---------- NSURLProtocol ----------
@interface BlockProtocol : NSURLProtocol
@end
@implementation BlockProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (!DKIsBlockEnabled()) return NO;
    NSString *scheme = request.URL.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        return YES;
    }
    return NO;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}
- (void)startLoading {
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
    [self.client URLProtocol:self didFailWithError:error];
}
- (void)stopLoading {}
@end

// =============================================================
// 手势检测（基于 UIApplication sendEvent:）
// =============================================================

static void showToast(NSString *msg, UIWindow *window) {
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

static void showSettingsMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    
    BOOL blocking = [[NSUserDefaults standardUserDefaults] boolForKey:@"DeepBlockNetworkEnabled"];
    BOOL isNetworkOn = !blocking;
    NSString *status = isNetworkOn ? @"已联网" : @"已断网";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网络控制"
                                                                   message:[NSString stringWithFormat:@"当前状态：%@\n切换后可能需重启 App 生效", status]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSString *actionTitle = isNetworkOn ? @"关闭联网（断网）" : @"开启联网";
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newBlocking = !blocking;
                                                
                                                if (newBlocking) {
                                                    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                                                                           message:@"关闭联网后需要重启 App 才能生效，确定要继续吗？"
                                                                                                                    preferredStyle:UIAlertControllerStyleAlert];
                                                    [confirmAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                                                        [[NSUserDefaults standardUserDefaults] setBool:newBlocking forKey:@"DeepBlockNetworkEnabled"];
                                                        [[NSUserDefaults standardUserDefaults] synchronize];
                                                        showToast(@"联网已关闭（断网）", window);
                                                    }]];
                                                    [confirmAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                                                    
                                                    UIViewController *top = window.rootViewController;
                                                    while (top.presentedViewController) {
                                                        top = top.presentedViewController;
                                                    }
                                                    [top presentViewController:confirmAlert animated:YES completion:nil];
                                                } else {
                                                    [[NSUserDefaults standardUserDefaults] setBool:newBlocking forKey:@"DeepBlockNetworkEnabled"];
                                                    [[NSUserDefaults standardUserDefaults] synchronize];
                                                    showToast(@"联网已开启", window);
                                                }
                                            }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }
    
    [topVC presentViewController:alert animated:YES completion:nil];
}

// 检测双指长按的全局变量
static NSTimeInterval touchStartTime = 0;
static BOOL isTouching = NO;
static NSInteger touchCount = 0;

// =============================================================
// Hook UIApplication 的 sendEvent: 来检测触摸事件
// =============================================================
%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    %orig; // 先执行原始事件处理
    
    if (event.type != UIEventTypeTouches) return;
    
    NSSet *touches = [event allTouches];
    if (touches.count == 0) return;
    
    UITouch *touch = [touches anyObject];
    if (touch.phase == UITouchPhaseBegan) {
        touchCount = touches.count;
        if (touchCount == 2) {
            isTouching = YES;
            touchStartTime = [NSDate timeIntervalSinceReferenceDate];
        }
    } else if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
        isTouching = NO;
        touchCount = 0;
    } else if (touch.phase == UITouchPhaseStationary) {
        // 检查是否双指仍触摸，且持续时间超过 1.2 秒
        if (isTouching && touchCount == 2) {
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            if (now - touchStartTime > 1.2) {
                // 触发菜单
                UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
                if (keyWindow) {
                    // 触觉反馈
                    if (@available(iOS 10.0, *)) {
                        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
                        [generator prepare];
                        [generator impactOccurred];
                    }
                    showSettingsMenu(keyWindow);
                }
                // 重置状态，避免重复触发
                isTouching = NO;
                touchCount = 0;
            }
        }
    }
}

%end

// =============================================================
// 注入入口
// =============================================================
%ctor {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DeepBlockNetworkEnabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DeepBlockNetworkEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    [NSURLProtocol registerClass:[BlockProtocol class]];
    NSLog(@"[DeepBlockNetwork] NSURLProtocol registered");
    
    install_connect_hook();
    
    NSLog(@"[DeepBlockNetwork] DeepBlockNetwork loaded");
}
