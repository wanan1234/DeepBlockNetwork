# DeepBlockNetwork

深度断网插件，通过 Hook `connect` 系统调用阻断所有 TCP 连接，适用于微信、B站等自研网络库的应用，无需外部 VPN，注入即用。

## 功能
- 阻断所有 TCP 连接（HTTP/HTTPS、WebSocket、自定义协议等）
- 辅助拦截 HTTP/HTTPS（通过 NSURLProtocol）
- 支持白名单（目前为硬编码，可修改源码）

1.0 初版-无弹窗
1.1 二版-双指双击-弹窗菜单：开启断网&关闭断网
1.2 三版-双指双击-弹窗菜单：开启联网&关闭联网
当前版本：双指长按-弹窗菜单：开启联网&关闭联网
## 编译
使用 Theos 或 GitHub Actions 自动编译。

## 使用
用 TrollFools 注入目标 App 即可。

## 注意
- 此插件会完全阻断目标 App 的网络，请谨慎使用。
- 如需放行某些域名，请修改 `kWhitelistDomains` 并重新编译。
