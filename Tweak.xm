// =============================================================
//  DeepBlockNetwork — 深度断网插件
//  通过 UIApplication sendEvent: 检测双指长按
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
// 通过 UIApplication 拦截触摸事件检测双指长按
// =============================================================

// 用于跟踪触摸状态
static NSSet *dk_currentTouches = nil;
static NSTimer *dk_longPressTimer = nil;
static CGPoint dk_firstTouchLocation = {0, 0};

// 显示 Toast
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

// 显示设置菜单
static void showSettingsMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    
    BOOL blocking = [[NSUserDefaults standardUserDefaults] boolForKey:@"DeepBlockNetworkEnabled"];
    BOOL isNetworkOn = !blocking;
    NSString *status = isNetworkOn ? @"已联网" : @"已断网";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网络控制"
                                                                   message:[NSString stringWithFormat:@"当前状态：%@\n切换联网状态后，可能需要重启App生效", status]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSString *actionTitle = isNetworkOn ? @"关闭联网" : @"开启联网";
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newBlocking = !blocking;
                                                if (newBlocking) {
                                                    // 关闭联网需要重启
                                                    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"提示"
                                                                                                                   message:@"关闭联网后需要重启 App 才能生效，确定要继续吗？"
                                                                                                            preferredStyle:UIAlertControllerStyleAlert];
                                                    [confirm addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                                                        [[NSUserDefaults standardUserDefaults] setBool:newBlocking forKey:@"DeepBlockNetworkEnabled"];
                                                        [[NSUserDefaults standardUserDefaults] synchronize];
                                                        showToast(@"联网已关闭", window);
                                                    }]];
                                                    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                                                    UIViewController *top = window.rootViewController;
                                                    while (top.presentedViewController) {
                                                        top = top.presentedViewController;
                                                    }
                                                    [top presentViewController:confirm animated:YES completion:nil];
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

// =============================================================
// Hook UIApplication 拦截触摸事件
// =============================================================
%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    %orig; // 必须先调用原方法
    
    // 只处理触摸事件
    if (event.type != UIEventTypeTouches) return;
    
    NSSet *touches = event.allTouches;
    if (!touches || touches.count == 0) return;
    
    // 获取所有触摸点
    NSMutableArray *activeTouches = [NSMutableArray array];
    for (UITouch *touch in touches) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
            [activeTouches addObject:touch];
        }
    }
    
    // 检查是否有两根手指同时触摸
    if (activeTouches.count >= 2) {
        // 获取第一根手指的位置
        UITouch *firstTouch = activeTouches.firstObject;
        CGPoint location = [firstTouch locationInView:firstTouch.window];
        
        // 记录开始位置和开始时间
        if (!dk_currentTouches || dk_currentTouches.count < 2) {
            dk_firstTouchLocation = location;
            // 启动长按定时器
            [dk_longPressTimer invalidate];
            dk_longPressTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                 target:self
                                                               selector:@selector(dk_handleLongPressTimer:)
                                                               userInfo:nil
                                                                repeats:NO];
        }
        dk_currentTouches = activeTouches;
        
        // 检查手指是否移动超过阈值（取消长按）
        if (dk_currentTouches.count >= 2) {
            CGFloat dx = location.x - dk_firstTouchLocation.x;
            CGFloat dy = location.y - dk_firstTouchLocation.y;
            if (sqrt(dx*dx + dy*dy) > 30) {
                [dk_longPressTimer invalidate];
                dk_longPressTimer = nil;
            }
        }
    } else {
        // 手指松开或少于两根，取消定时器
        [dk_longPressTimer invalidate];
        dk_longPressTimer = nil;
        dk_currentTouches = nil;
    }
}

// 定时器触发：长按识别成功
%new
- (void)dk_handleLongPressTimer:(NSTimer *)timer {
    [dk_longPressTimer invalidate];
    dk_longPressTimer = nil;
    
    // 触觉反馈
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator prepare];
        [generator impactOccurred];
    }
    
    // 获取当前窗口
    UIWindow *window = [UIApplication sharedApplication].windows.firstObject;
    if (window) {
        showSettingsMenu(window);
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
