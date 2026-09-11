# 安装与连接

## General Registry

```julia
using Pkg
Pkg.add("ResearchVault")
```

## 独立仓库稳定标签

```julia
using Pkg
Pkg.add(PackageSpec(
    url="https://github.com/Haiyang-Bian/ResearchVault.jl.git",
    rev="v0.5.1",
))
```

General Registry 注册完成前使用上述 Git URL；注册完成后首选 `Pkg.add("ResearchVault")`。
正式研究使用已发布标签或经验证的精确 SHA，并提交研究工程自己的 `Project.toml` 和
`Manifest.toml`。`main` 只用于开发跟踪。

## 版本兼容

| Research Vault | Julia SDK | 支持状态 |
| --- | --- | --- |
| 0.12.x | 0.4.x | 历史服务名兼容 |
| 0.13.0 | — | 已知安装生命周期缺陷，必须升级 |
| 0.13.1 | 0.5.1+ | 支持新服务名与 Rust 原生登录任务激活 |
| 0.14.x | 0.5.1+ | 模块化构建不改变客户端 API |

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
