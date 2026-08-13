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

// 返回 YES 表示阻断（断网），NO 表示允许（联网）
static BOOL DKIsBlockEnabled(void) {
    // 注意：这里存储的是“是否阻断”，YES=阻断，NO=允许
    // 但我们 UI 上用“联网”概念，所以取反显示
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
// 手势控制（UI 文案改为“联网”）
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
    
    // 注意：存储值是“阻断”标志，YES=断网，NO=联网
    BOOL blocking = [[NSUserDefaults standardUserDefaults] boolForKey:@"DeepBlockNetworkEnabled"];
    // 联网状态 = !blocking
    BOOL isNetworkOn = !blocking;
    NSString *status = isNetworkOn ? @"已联网" : @"已断网";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网络控制"
                                                                   message:[NSString stringWithFormat:@"当前状态：%@", status]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSString *actionTitle = isNetworkOn ? @"关闭联网" : @"开启联网";
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                // 切换阻断标志
                                                BOOL newBlocking = !blocking; // 如果之前阻断，改为不阻断；反之亦然
                                                [[NSUserDefaults standardUserDefaults] setBool:newBlocking forKey:@"DeepBlockNetworkEnabled"];
                                                [[NSUserDefaults standardUserDefaults] synchronize];
                                                // 显示 Toast
                                                NSString *toastMsg = newBlocking ? @"联网已关闭（断网）" : @"联网已开启";
                                                showToast(toastMsg, window);
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
    // 默认第一次启动时设为断网（阻断）状态，即 DeepBlockNetworkEnabled = YES
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DeepBlockNetworkEnabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DeepBlockNetworkEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    [NSURLProtocol registerClass:[BlockProtocol class]];
    NSLog(@"[DeepBlockNetwork] NSURLProtocol registered");
    
    install_connect_hook();
    
    NSLog(@"[DeepBlockNetwork] DeepBlockNetwork loaded");
}
