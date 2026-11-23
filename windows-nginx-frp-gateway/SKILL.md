---
name: windows-nginx-frp-gateway
description: 在 Windows 上配置和维护 Nginx + FRP 客户端网关。适用于通过已部署的 frps 转发获授权的 HTTPS API、配置开机自启、调整请求体上限，或排查 401、413 和隧道连通性。
---

# Windows Nginx + FRP 网关

链路为云端 `frps` 的 TCP 映射端口 → Windows `frpc` → 本机环回 Nginx → HTTPS 上游。使用 [配置与操作参考](references/windows-deployment.md) 中对应的配置或命令。

## 部署与验证

1. 核对现有进程、计划任务、监听端口、FRP 云端地址和端口白名单。优先复用现有运行文件和配置。从官方发布渠道补齐缺失的 Windows 二进制，并核对实际版本及可用的签名或摘要。
2. 保持 Nginx 仅监听环回地址，保留上游 Host、TLS SNI、证书验证和 API 鉴权。FRP token 用于隧道连接鉴权。对外入口使用 HTTPS 和适当的访问控制，真实 API Key 只通过受保护的入口发送。
3. 先检查 Nginx 和 `frpc` 配置，再验证本机、隧道注册和云端入口。空凭据请求返回上游的 `401 API_KEY_REQUIRED` 可以证明该请求到达鉴权层。使用获授权的有效凭据成功调用后，再确认 API 功能可用。
4. 开机启动使用 Windows 任务计划程序的 `AtStartup` 触发器和可在用户未登录时运行的账户。注册需要管理员权限，任务使用普通权限。手动触发后核对任务状态、监听端口和出口响应。区分手动触发验证与重启实测。

## 维护与排查

- 调整 `client_max_body_size` 时按实际 HTTP 请求体字节数估算。默认 `1m`，`500m` 表示 500 MiB。普通英文文本可按约 4 字节/token 粗估，图片 Base64 约为原始字节的 4/3，另计 JSON 开销。具体上限按业务负载与各网关限制选择。
- 先在原实例的 `-p`、`-c` 参数下运行 `nginx -t`，再热重载。若出现 `413`，用环回地址和 `Expect: 100-continue` 验证本机边界，结合日志或响应来源定位其他代理和上游限制。边界探测只发送请求头。
- 发布配置示例时使用占位域名和凭据。实际 token、API Key、内部域名、部署地址、运行日志和二进制保存在部署环境。
