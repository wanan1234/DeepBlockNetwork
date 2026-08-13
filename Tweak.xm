// =============================================================
//  DeepBlockNetwork — 深度断网插件（Hook connect + NSURLProtocol）
//  使用 fishhook 替换 connect 系统调用，阻断所有 TCP 连接
//  新增：双指双击手势开关菜单，实时切换无需重启
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
    return YES; // 全部拦截
}

// ---------- 原始 connect ----------
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);

// ---------- 替换后的 connect ----------
int hooked_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (DKShouldBlockConnection(addr)) {
        errno = EHOSTUNREACH;  // 改为 EHOSTUNREACH，应用可能持续重试
        return -1;
    }
    return orig_connect(sockfd, addr, addrlen);
}

// ---------- 安装 Hook ----------
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
// 手势控制
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
    
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"DeepBlockNetworkEnabled"];
    NSString *status = enabled ? @"已开启" : @"已关闭";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"深度断网控制"
                                                                   message:[NSString stringWithFormat:@"当前状态：%@\n点击下方切换", status]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 断网", enabled ? @"关闭" : @"开启"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newState = !enabled;
                                                [[NSUserDefaults standardUserDefaults] setBool:newState forKey:@"DeepBlockNetworkEnabled"];
                                                [[NSUserDefaults standardUserDefaults] synchronize];
                                                
                                                // 发送网络变化通知（尝试让应用刷新网络状态）
                                                dispatch_async(dispatch_get_main_queue(), ^{
                                                    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                                                         CFSTR("com.apple.system.config.network_change"), NULL, NULL, YES);
                                                    [[NSNotificationCenter defaultCenter] postNotificationName:@"kNetworkReachabilityChangedNotification" object:nil];
                                                });
                                                
                                                showToast([NSString stringWithFormat:@"断网已%@", newState ? @"开启" : @"关闭"], window);
                                            }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }
    
    [topVC presentViewController:alert animated:YES completion:nil];
}

// =============================================================
// Hook UIWindow：双指双击
// =============================================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dk_handleDoubleDoubleTap:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.numberOfTapsRequired = 2;
        [self addGestureRecognizer:gesture];
        NSLog(@"[DeepBlockNetwork] Double-tap gesture added");
    }
    return self;
}

%new
- (void)dk_handleDoubleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        showSettingsMenu(self);
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
