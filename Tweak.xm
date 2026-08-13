// =============================================================
//  DeepBlockNetwork — 深度断网插件
//  双指双击手势开关联网/断网
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
// 手势控制（双指双击）
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
                                                                   message:[NSString stringWithFormat:@"当前状态：%@", status]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSString *actionTitle = isNetworkOn ? @"关闭联网" : @"开启联网";
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
                                                        showToast(@"联网已关闭", window);
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

// =============================================================
// Hook UIWindow：双指双击（增强穿透）
// =============================================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        [self dk_addDoubleTapGesture];
    }
    return self;
}

- (void)dk_addDoubleTapGesture {
    // 移除可能已存在的手势，避免重复添加
    for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
        if ([gesture isKindOfClass:[UITapGestureRecognizer class]] &&
            gesture.numberOfTouchesRequired == 2 &&
            gesture.numberOfTapsRequired == 2) {
            [self removeGestureRecognizer:gesture];
        }
    }
    
    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dk_handleDoubleTap:)];
    gesture.numberOfTouchesRequired = 2;
    gesture.numberOfTapsRequired = 2;
    
    // 关键：不延迟触摸，让手势尽快识别
    gesture.delaysTouchesBegan = NO;
    gesture.delaysTouchesEnded = NO;
    gesture.cancelsTouchesInView = NO;
    
    gesture.delegate = (id<UIGestureRecognizerDelegate>)self;
    [self addGestureRecognizer:gesture];
    NSLog(@"[DeepBlockNetwork] 2-finger double-tap added");
}

%new
- (void)dk_handleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        // 触觉反馈
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [generator prepare];
            [generator impactOccurred];
        }
        showSettingsMenu(self);
    }
}

// 允许与其他手势共存（关键）
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 如果是我们的双指双击手势，允许与所有手势共存
    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] &&
        gestureRecognizer.numberOfTouchesRequired == 2 &&
        gestureRecognizer.numberOfTapsRequired == 2) {
        return YES;
    }
    return NO;
}

// 不需要等待其他手势失败才识别（提高优先级）
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 我们的手势不依赖于其他手势失败
    return NO;
}

// 不要让其他手势要求我们的手势失败
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 阻止其他手势要求我们的手势失败（提高识别率）
    return NO;
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
