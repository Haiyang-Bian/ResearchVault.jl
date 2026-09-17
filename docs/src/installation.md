# 安装与连接

## 当前来源

General 尚未注册；0.6.0 仍是候选源码，不能先声明支持 `Pkg.add("ResearchVault")`。
已审计的 0.5.1 旧认证代码可以用精确提交安装（不支持新的成员权限 Vault）：

```julia
using Pkg
Pkg.add(PackageSpec(
    url="https://github.com/Haiyang-Bian/ResearchVault.jl.git",
    rev="17b4de0ce953bc1d801d653fd857912419051d74",
))
```

General Registry 注册完成前使用经过验证的 Git 提交；注册完成后才能使用 `Pkg.add("ResearchVault")`。
正式研究使用已发布标签或经验证的精确 SHA，并提交研究工程自己的 `Project.toml` 和
`Manifest.toml`。`main` 只用于开发跟踪。

## 版本兼容

| Research Vault | Julia SDK | 支持状态 |
| --- | --- | --- |
| 0.12.x | 0.4.x | 历史服务名兼容 |
| 0.13.0 | — | 已知安装生命周期缺陷，必须升级 |
| 0.13.1 | 0.5.1+ | 支持新服务名与 Rust 原生登录任务激活 |
| 0.14.x 旧单用户认证 | 0.5.1+ | 模块化构建不改变客户端 API |
| 0.14.0 成员权限候选 | 0.6.0 候选 | Windows x64 原生凭据；通过精确提交安装 |

0.6.0 的[成员身份合同](member-auth.md)规定默认读取当前已保存的桌面身份，或通过
`connect_local(credential_id="<非敏感凭据 ID>")` 显式选择。连接建立后不会随桌面切换身份。
`identity_context(vault)` 返回强类型 `IdentityContext`，可查询实际身份和有效权限；没有成员管理和
凭据签发 API。

## 本地服务发现

`connect_local()` 先验证当前 runtime 的进程身份、loopback endpoint、令牌及健康状态。
服务未运行且 `auto_start=true` 时，只激活当前用户已注册的 Research Vault 登录任务；
显式 `service_executable` 只能核对注册目标，不直接启动 EXE。缺少或陈旧注册明确失败并提示修复安装。
客户端不直接读取 SQLite/CAS，令牌不进入 Notebook、日志或异常输出。

完整安装包负责注册登录任务，不需要打开桌面。开发时在独立终端运行服务，然后连接它的 Vault 根：

```julia
vault = connect_local(
    app_data=raw"D:\ResearchVaultDevData",
    auto_start=false,
)
close(vault)
```

服务和 Worker 均可离线运行。Julia 包的首次依赖安装仍需已有 depot 缓存或访问 Julia registry；
研究机器可预先复制 depot 或使用组织内 Julia package server。
