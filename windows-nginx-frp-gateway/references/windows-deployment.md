# Windows 部署与维护参考

示例使用 Nginx 环回端口 `18080`、FRP 控制端口 `7000` 和 TCP 映射端口 `19090`。替换域名、证书路径和占位凭据，并与现有服务核对端口。取得 [Nginx Windows 发布包](https://nginx.org/en/download.html) 和与服务端兼容的 [FRP 发布包](https://github.com/fatedier/frp/releases)。

## 配置模板

把 `nginx.conf` 和 `frpc.toml` 放在部署目录根部。示例运行路径为 `runtime/nginx/nginx.exe` 和 `runtime/frp/frpc.exe`。将 Nginx 发布包完整解压到对应的运行目录，确保 `-p` 指定的前缀下有可写的 `logs` 和 `temp` 目录，缺少时先创建。Nginx 的证书信任文件采用 PEM，按实际部署选择受信任的 CA 链。

```nginx
events {}

http {
    server {
        listen 127.0.0.1:18080;
        client_max_body_size 500m;

        location / {
            proxy_pass https://gateway.example.com;
            proxy_set_header Host gateway.example.com;
            proxy_ssl_server_name on;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate "C:/path/to/trusted-ca-bundle.pem";

            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_read_timeout 300s;
        }
    }
}
```

这份模板保留 URI、查询参数和默认透传的 API 鉴权头，支持 SSE 流式响应。上游若使用 WebSocket，再按 Nginx 的 `Upgrade` 与 `Connection` 转发规则配置。`500m` 对应带图片的部署示例，请按实际载荷和上游上限调整。

```toml
serverAddr = "frps.example.net"
serverPort = 7000
loginFailExit = false

[auth]
method = "token"
token = "REPLACE_WITH_FRP_TOKEN"

[[proxies]]
name = "windows-api-gateway"
type = "tcp"
localIP = "127.0.0.1"
localPort = 18080
remotePort = 19090
```

确保云端 `frps` 允许该 `remotePort`。云端 TLS 入口可以反代到云端环回的映射端口。若映射端口已绑定公网地址，可通过防火墙限制直连，避免绕过云端 HTTPS。`proxyBindAddr` 会影响同一 `frps` 实例上的其他代理，变更前核对现有映射。

## 语法检查和启动

在部署目录运行以下命令。两个进程手动启动时可分别在对应终端运行。

```powershell
$gatewayRoot = (Get-Location).Path
$nginxDirectory = Join-Path $gatewayRoot 'runtime\nginx'
$nginxExecutable = Join-Path $nginxDirectory 'nginx.exe'
$nginxPrefix = $nginxDirectory.Replace('\', '/') + '/'
$nginxConfig = (Join-Path $gatewayRoot 'nginx.conf').Replace('\', '/')
$frpcExecutable = Join-Path $gatewayRoot 'runtime\frp\frpc.exe'
$frpcConfig = Join-Path $gatewayRoot 'frpc.toml'

& $nginxExecutable -t -p $nginxPrefix -c $nginxConfig
if ($LASTEXITCODE -ne 0) { throw 'Nginx 配置检查失败。' }
& $frpcExecutable verify -c $frpcConfig
if ($LASTEXITCODE -ne 0) { throw 'FRP 配置检查失败。' }
```

手动启动时在 Nginx 检查通过后执行 `& $nginxExecutable -p $nginxPrefix -c $nginxConfig`，再用 `& $frpcExecutable -c $frpcConfig` 启动客户端。端口测试成功只表明 TCP 可连通。核对 `frpc` 日志中的登录和代理启动结果，并分别调用环回地址和云端的实际 API 路径。例如用 `curl.exe --noproxy '*' -i http://127.0.0.1:18080/v1/models` 核对环回响应。

## 开机启动

在计划用作任务账户的管理员 PowerShell 会话中准备上一节变量。执行前检查同名任务和手动启动的进程。已有同名任务时先核对其执行路径，迁移正在运行的实例时安排短暂切换。

```powershell
$gatewayAccount = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$gatewayPrincipal = New-ScheduledTaskPrincipal -UserId $gatewayAccount -LogonType S4U -RunLevel Limited
$gatewaySettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew `
    -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

$nginxAction = New-ScheduledTaskAction -Execute $nginxExecutable -WorkingDirectory $nginxDirectory `
    -Argument ('-p "{0}" -c "{1}"' -f $nginxPrefix, $nginxConfig)
$nginxTrigger = New-ScheduledTaskTrigger -AtStartup
$nginxTrigger.Delay = 'PT30S'
Register-ScheduledTask -TaskName 'Gateway-Nginx' -Action $nginxAction -Trigger $nginxTrigger `
    -Principal $gatewayPrincipal -Settings $gatewaySettings -ErrorAction Stop | Out-Null

$frpcAction = New-ScheduledTaskAction -Execute $frpcExecutable -WorkingDirectory $gatewayRoot `
    -Argument ('-c "{0}"' -f $frpcConfig)
$frpcTrigger = New-ScheduledTaskTrigger -AtStartup
$frpcTrigger.Delay = 'PT45S'
Register-ScheduledTask -TaskName 'Gateway-frpc' -Action $frpcAction -Trigger $frpcTrigger `
    -Principal $gatewayPrincipal -Settings $gatewaySettings -ErrorAction Stop | Out-Null

Start-ScheduledTask -TaskName 'Gateway-Nginx' -ErrorAction Stop
Start-ScheduledTask -TaskName 'Gateway-frpc' -ErrorAction Stop
Get-ScheduledTask -TaskName 'Gateway-Nginx','Gateway-frpc' | Select-Object TaskName,State,Triggers
```

延迟可按开机时 DNS 和网络就绪速度调整。固定延迟用于错峰启动。`S4U` 适用于本地配置和普通出站连接，依赖 Windows 身份认证的网络资源或加密文件时，核对所用账户和登录类型。用 `Get-ScheduledTaskInfo` 查看执行结果，并用 `Get-NetTCPConnection -LocalPort 18080 -State Listen` 核对监听。排障时检查 Nginx `logs/error.log` 和任务历史。禁用开机触发可用 `Disable-ScheduledTask`，停止当前实例可用 `Stop-ScheduledTask`。

## 请求体上限与热重载

修改 `client_max_body_size` 后先以同一套参数运行 `nginx -t`。确认 PID 文件指向本部署的 Nginx 主进程后，执行 `& $nginxExecutable -s reload -p $nginxPrefix -c $nginxConfig`。从任务外的会话发信号失败时，检查任务实例、运行账户及 Windows 权限。必要时在维护窗口通过计划任务重启。

对本地环回监听发送 HTTP/1.1 请求头，使用 `Expect: 100-continue`，把 `Content-Length` 分别设为配置上限和上限加 1 字节。读取首个状态行后关闭连接，无需上传请求体。正常情况下，前者返回 `100 Continue`，后者返回 `413`。对 `500m` 而言，测试值是 `524288000` 和 `524288001`。用实际、有授权的图片请求验证整条链路时，还要考虑上游文件大小、图片数量、上下文和超时限制。
