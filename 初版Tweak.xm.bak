// =============================================================
//  DeepBlockNetwork — 深度断网插件（Hook connect + NSURLProtocol）
//  使用 fishhook 替换 connect 系统调用，阻断所有 TCP 连接
//  适用于微信、B站等自研网络库的应用
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
// 白名单域名（这些域名的连接将放行）
static NSArray *kWhitelistDomains = @[
    // @"apple.com",  // 如需放行苹果验证服务器，取消注释
    // @"icloud.com",
];

// 是否启用阻断（默认开启，可通过 NSUserDefaults 动态控制）
static BOOL DKIsBlockEnabled(void) {
    return YES;
}

// 判断是否应该拦截此连接（根据目标 IP 或域名）
static BOOL DKShouldBlockConnection(const struct sockaddr *addr) {
    if (!DKIsBlockEnabled()) return NO;
    // 如果是 IPv4
    if (addr->sa_family == AF_INET) {
        struct sockaddr_in *sin = (struct sockaddr_in *)addr;
        char ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &sin->sin_addr, ip, INET_ADDRSTRLEN);
        // 简单过滤：如果需要在白名单中，可在这里检查 IP
        // 但域名白名单需要 DNS 解析，在此简化，全部拦截
        return YES;
    }
    // IPv6
    if (addr->sa_family == AF_INET6) {
        return YES;
    }
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
    rebind.replacement = (void *)hooked_connect;   // 强制类型转换
    rebind.replaced = (void **)&orig_connect;      // 强制类型转换
    rebind_symbols(&rebind, 1);
    NSLog(@"[DeepBlockNetwork] connect hook installed");
}

// ---------- NSURLProtocol 辅助拦截（可选） ----------
@interface BlockProtocol : NSURLProtocol
@end
@implementation BlockProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (!DKIsBlockEnabled()) return NO;
    // 只拦截 HTTP/HTTPS（防止影响本地请求）
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

// ---------- 注入入口 ----------
%ctor {
    // 注册 NSURLProtocol（辅助）
    [NSURLProtocol registerClass:[BlockProtocol class]];
    NSLog(@"[DeepBlockNetwork] NSURLProtocol registered");
    
    // 安装 connect hook
    install_connect_hook();
    
    NSLog(@"[DeepBlockNetwork] DeepBlockNetwork loaded");
}
