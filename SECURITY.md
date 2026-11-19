# Security Policy

## 离线与隐私设计原则

`tinycast-extensions`（包括原生悬浮工作台 `tinycast-devkit`）严格遵循**本地优先、最小权限**原则：

1. **100% 本地离线运算**：UUID、时间戳、Hash（MD5/SHA/SHA-3/BLAKE3/SM3/CRC32 等）、编解码（Base64/JWT/Zlib）、AES-256-GCM/CBC 加解密、JSON 转换、密码生成、二维码绘制、Cron 解析与色值/WCAG 运算全部在本机内存中离线完成，**不发送任何用户输入到第三方服务器**。
2. **按需且无账号/无敏感上传的只读外网调用**：
   - 「本机 IP & 端口 (`network-ports`)」点击 **「查询公网 IP」** 时向 `https://api.ipify.org?format=json` 请求只读公网 IP；
   - 「TLS / X.509 证书 (`cert-inspector`)」点击 **「拉取 TLS 证书链」** 时向用户指定域名发起 `HEAD` TLS 握手以检视公开证书链；
   - 「各国汇率计算器 (`currency-converter`)」打开或刷新时向公开无密钥数据源（`cdn.jsdelivr.net` / `latest.currency-api.pages.dev` / `open.er-api.com` / `api.frankfurter.dev`）拉取公开汇率并缓存至 `~/Library/Caches/tinycast-devkit/`（4 小时 TTL，不上传用户输入金额）；
   - 其余所有计算与 Vision 识别功能全程离线。
3. **敏感密码隐私保护**：所有生成的密码与密钥默认标记 macOS `org.nspasteboard.ConcealedType`，避免被第三方剪贴板历史管理器明文持久化记录。
4. **本地进程隔离**：单实例锁文件与请求交接文件位于 `/tmp/tinycast-devkit-<uid>.lock` 及其同级 `-request.json`，采用用户 UID 隔离。

## 报告安全漏洞

如果你发现了潜在的安全隐患（例如解析漏洞、命令注入风险或权限问题），**请不要在公开 Issue 中直接披露敏感利用细节**，请通过以下方式联系：

- 在 GitHub 仓库的 **Security → Advisories → Report a vulnerability** 提交私密安全报告。
- 我们会在收到报告后尽快确认影响范围并发布修复版本。
