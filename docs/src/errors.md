# 错误与离线使用

- `VaultConnectionError`：服务未发现、启动失败、请求超时或传输失败；
- `VaultError`：服务返回统一 `ServiceProblem`，含 status、code、message、request_id 和 details；
- `VaultTaskError`：Task 进入失败、取消或中断终态；
- `VaultTaskTimeoutError`：客户端等待预算耗尽；
- `VaultIntegrityError`：Artifact 长度或 SHA-256 与 Catalog 不一致。

异常文本不会包含服务令牌。路径只用于本机高信任导入/导出请求，不应进入 Notebook 输出、日志或
MCP 响应。

Research Vault 的发布应用和服务在运行时不依赖网络。若需要完全离线安装 Julia 依赖，应在联网机器
上预实例化同一研究环境并保留 depot，或使用可信的内部 package server。
