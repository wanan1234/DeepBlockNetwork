// =============================================================
//  DeepBlockNetwork — 深度断网插件（Hook connect + NSURLProtocol）
//  使用 fishhook 替换 connect 系统调用，阻断所有 TCP 连接
//  新增：双指双击手势开关菜单
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
// 白名单域名（这些域名的连接将放行）—— 暂不实现
static NSArray *kWhitelistDomains = @[];

// 从 NSUserDefaults 读取开关状态
static BOOL DKIsBlockEnabled(void) {
    // 默认开启，用户可通过手势切换
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DeepBlockNetworkEnabled"];
}

// 判断是否应该拦截此连接（根据目标 IP 或域名）
static BOOL DKShouldBlockConnection(const struct sockaddr *addr) {
    if (!DKIsBlockEnabled()) return NO;
    // 简单全部拦截（忽略白名单）
    return YES;
}

// ---------- 原始 connect 函数指针 ----------
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);

// ---------- 替换后的 connect ----------
int hooked_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (DKShouldBlockConnection(addr)) {
        errno = ECONNREFUSED;  // 模拟连接被拒绝
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

// ---------- NSURLProtocol 辅助拦截 ----------
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
// 新增：双指双击手势控制
// =============================================================

// 显示 Toast 提示（全局函数）
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

// 显示设置菜单（全局函数）
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
                                                // 显示 Toast 提示
                                                showToast([NSString stringWithFormat:@"断网已%@", newState ? @"开启" : @"关闭"], window);
                                            }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    // iPad 适配
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }
    
    [topVC presentViewController:alert animated:YES completion:nil];
}

// =============================================================
// Hook UIWindow：添加双指双击手势
// =============================================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        // 双指双击手势
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
    // 默认第一次启动时开启断网（若未设置）
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DeepBlockNetworkEnabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DeepBlockNetworkEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    // 注册 NSURLProtocol
    [NSURLProtocol registerClass:[BlockProtocol class]];
    NSLog(@"[DeepBlockNetwork] NSURLProtocol registered");
    
    // 安装 connect hook
    install_connect_hook();
    
    NSLog(@"[DeepBlockNetwork] DeepBlockNetwork loaded");
}
