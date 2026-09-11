# Changelog

## 0.5.1 - 2026-09-10

- 识别 `research-vault-service.exe` 及其 Windows target 后缀名，并保留一版
  `scenario-service.exe` 发现兼容。
- 在新 `com.haiyangbian.research-vault` app-data 根与存在历史状态的
  `com.alice.scenarios-generate` 根之间执行确定性选择。
- 读取 schema v1/v2 `service-task.json`，并通过 Research Vault 0.13.1 的原生
  `service-task start` 激活已注册登录任务。
- 继续核验 PID、可执行文件名和进程启动时间；未知、复用或不匹配身份仍拒绝提交业务请求。

Research Vault 0.13.1 的最低支持客户端为 ResearchVault.jl 0.5.1。
