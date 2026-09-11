# ResearchVault.jl

适配 Research Vault 0.13.1 和 0.14.x。服务常驻，客户端只激活已注册的登录任务；关闭
SDK 或桌面不会取消已提交任务。

`ResearchVault.jl` 是 Research Vault 的类型化本机 Julia SDK，包版本为 0.5.1，最低支持
Julia 1.10。它通过认证的 loopback API 使用科研项目、不可变数据版本、场景 Run、Figure
工作版本、Task 和 Artifact，不直接打开 SQLite、CAS 或 Python Worker。

## 安装

注册 General Registry 后，稳定版安装为：

```julia
using Pkg
Pkg.add("ResearchVault")
```

注册完成前，或需要固定精确来源时，从独立公开仓库安装：

```julia
using Pkg
Pkg.add(PackageSpec(
    url="https://github.com/Haiyang-Bian/ResearchVault.jl.git",
    rev="v0.5.1",
))
```

开发者可克隆独立仓库并运行 `Pkg.develop(path="...")`。正式研究应使用发布标签或精确 SHA，
并提交研究工程自己的 `Project.toml` 和 `Manifest.toml`；`main` 只作为开发来源。

## 客户端兼容

| Research Vault | Julia SDK | 说明 |
| --- | --- | --- |
| 0.12.x | 0.4.x | 历史 `scenario-service` 产品名 |
| 0.13.0 | 不作为支持组合 | 安装生命周期存在已知缺陷，请升级应用 |
| 0.13.1 | 0.5.1 或更高 | 支持 `research-vault-service` 和原生 `service-task` |
| 0.14.x | 0.5.1 或更高 | 动态 DuckDB 与模块化构建不改变客户端 API |

## 连接

完整安装包注册当前用户的登录服务任务；不需要先打开桌面窗口。随后：

```julia
using ResearchVault

connect_local() do vault
    println(health(vault).version)
    println(length(projects(vault)))
end
```

服务未运行时，`auto_start=true` 只请求启动已注册任务，不直接创建服务子进程。
缺少注册时需要修复安装，不能只传一个 EXE 路径代替注册。开发环境先在独立终端启动服务，再连接同一根目录：

```julia
vault = connect_local(
    app_data=raw"D:\ResearchVaultDevData",
    auto_start=false,
)
```

## 数据、任务和 Tables.jl

```julia
using DataFrames
using ResearchVault

connect_local() do vault
    project = create_project(vault; title="Julia experiment")
    importing = import_dataset(
        vault,
        raw"D:\experiment\observations.csv";
        title="Observations",
        kind=:experimental_table,
        provenance=:measured,
    )
    completed = wait_success(vault, importing.id; on_progress=t -> @info(t.message))
    version = dataset_version(vault, completed.result_resource_id)
    attach_resource(vault, project.id, :dataset_version, version.id; role="evidence")

    result = query_dataset(
        vault,
        version.id,
        QuerySpec(columns=["timestamp", "value"], limit=4000);
        logical_path="observations.csv",
    )
    frame = DataFrame(result)
end
```

`DataFrames.jl` 不是本包依赖；`VaultTable` 实现 Tables.jl，可同样交给 CSV.jl、Arrow.jl 等
Tables.jl 消费方。JSON `null` 映射为 `missing`，列顺序由服务响应保持。

## 权限边界

Julia SDK 是本机高信任客户端，可提交明确的导入和 Artifact 导出路径；路径仍由服务规范化和
校验。它不提供任意 SQL、任意服务 URL、Figure 发布、删除、迁移或 GC。Figure 工作版本必须在
桌面端人工审阅后发布。

完整示例见 `examples/experimental_workflow.jl`，API 与故障处理见 `docs/`。
