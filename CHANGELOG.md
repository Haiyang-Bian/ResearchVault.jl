# Changelog

## 0.7.0 - Unreleased

- 新增 `connect_team(name)`，只读取 Windows team-client 的命名连接与个人 Credential Manager 凭据。
- HTTPS 固定连接私有 CA并校验证书链/IP SAN，禁止 HTTP、重定向、代理和验证绕过；连接后核对身份上下文。
- `import_dataset` / `import_dataset_version` 在团队连接中改为分块上传、完整哈希校验和幂等中央提交，不发送本机绝对路径。
- 新增不可变版本文件流式下载与断点恢复；最终校验 manifest 大小和 SHA-256。
- 当前远程 DataOnly 能力以 fail-closed 表达：科学计算、无头绘图、服务器路径导出和成果回传不提交请求。
- 保留 `connect_local` 与 0.6.0 身份行为；仍不创建标签、Release 或 General Registry 条目。

## 0.6.0 - Unreleased

- Windows x64 成员模式通过原生 Credential Manager 读取已保存的桌面用途凭据；支持按非敏感凭据 ID 选择。
- 连接前核验服务、Workspace 和用户；缺失、损坏、过期或撤销时不回退共享令牌。
- 新增强类型 `IdentityContext` 与 `identity_context`；客户端和内部连接对象显示时不输出令牌。
- 保留 0.13.1–0.14.x 旧单用户模式，并在连接时验证认证而不只检查公开 health。
- 修正未发布标签的安装示例及 CompatHelper 工作流。尚未注册 General，不宣称已发布。

## 0.5.1 - 2026-09-10

- 识别 `research-vault-service.exe` 及其 Windows target 后缀名，并保留一版
  `scenario-service.exe` 发现兼容。
- 在新 `com.haiyangbian.research-vault` app-data 根与存在历史状态的
  `com.alice.scenarios-generate` 根之间执行确定性选择。
- 读取 schema v1/v2 `service-task.json`，并通过 Research Vault 0.13.1 的原生
  `service-task start` 激活已注册登录任务。
- 继续核验 PID、可执行文件名和进程启动时间；未知、复用或不匹配身份仍拒绝提交业务请求。

Research Vault 0.13.1 的最低支持客户端为 ResearchVault.jl 0.5.1。
