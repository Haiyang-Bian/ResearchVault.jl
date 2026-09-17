# 本机与团队身份合同（0.7.0 候选）

旧单用户和 Windows x64 loopback 成员模式保持兼容。0.7.0 新增显式团队 HTTPS 连接；
科研 REST 响应和严格模型不因连接位置改变。

- `connect_local` 读取本机 `runtime/identity.json` 中的非敏感凭据引用，再通过
  Windows Credential Manager 读取 `desktop` 用途的原生客户端凭据，绝不使用 MCP 凭据。
- 默认使用连接时选中的桌面身份；可用 `credential_id` 明确选择已保存的原生凭据。
  连接成功后身份固定，切换桌面身份不会改变已创建的 Julia 客户端。重新连接才应用新的选择。
- SDK 不签发、保存或恢复凭据。成员配置存在但损坏、凭据缺失、撤销或过期时明确失败，
  不能退回 `service.token`。只有没有成员配置、未转换的 Vault 才使用旧认证。
- 连接前验证服务进程与 loopback 地址；连接成功前通过 `/team/v1/context`
  核对服务、Workspace 和用户绑定。该查询不产生科研写入。
- `identity_context(vault)` 返回强类型 `IdentityContext`，包含当前服务鉴权得到的非敏感身份、权限和能力；
  角色变更、撤销和过期由服务逐请求执行，SDK 不缓存权限决定，也不自动重试业务写入。
- 同一个 Windows 用户可以访问自己保存的原生身份；该机制不是对恶意本机代码的安全隔离。
  路径导入导出仍需管理员原生身份；SDK 不新增成员管理、发布、删除或 GC 接口。
- 凭据仅保留在客户端内存，显示客户端/连接对象时必须脱敏；不进入项目文件、Notebook 输出或异常。

`connect_team(name)` 只接受 team-client 已登记的连接名称，不接受 URL 或 token。SDK 读取用户 app-data
中的 `research-vault-client/connections.json`，验证 CA PEM 指纹、server/Workspace/user 与 desktop token
元数据，再从完全限定的 Credential Manager 目标读取秘密。TLS 仅信任该连接的私有 CA，并校验证书链和
IP SAN；禁止代理、重定向、HTTP 回退和关闭验证。连接后再次用 `/team/v1/context` 核对三类身份。

团队连接支持数据/项目读取编辑、有界查询、可恢复上传、幂等 DatasetVersion 导入和带哈希的版本文件下载。
当前不支持远程科学计算、Julia 无头绘图、服务器路径导入导出或成果回传；这些能力缺失时 SDK 在提交前失败。
token 剩余 14 天时只提示用户打开 team-client 轮换，Julia 不改写连接或凭据。

发布前门禁包括正反例、身份绑定、原生凭据读取和清理、撤销及旧模式回归，
并在临时 Vault 上完成真实导入、查询、计算和绘图。注册状态与实现测试状态分开记录。
