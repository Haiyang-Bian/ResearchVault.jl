# ResearchVault.jl

`ResearchVault.jl` 是 Research Vault 的类型化 Julia SDK，当前开发版本为 0.7.0 候选，最低支持
Julia 1.10。它支持本机 loopback Vault，以及 Windows x64 上由 Research Vault team-client 登记的
HTTPS 团队连接；不直接打开 SQLite、CAS 或 Worker。关闭 SDK 或桌面不会取消服务已接受的任务。

## 安装

目前还没有 General 注册或发布标签，不能使用 `Pkg.add("ResearchVault")` 或 `rev="v0.5.1"`。
团队使用应在维护者完成审计后固定 0.7.0 的精确提交：

```julia
using Pkg
Pkg.add(PackageSpec(
    url="https://github.com/Haiyang-Bian/ResearchVault.jl.git",
    rev="<0.7.0 已审计提交 SHA>",
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
| 0.14.x 旧单用户认证 | 0.5.1 | 动态 DuckDB 与模块化构建不改变客户端 API |
| 0.14.0 本机成员权限 | 0.6.0+ | 复用已保存桌面身份，严格禁止回退共享令牌 |
| 0.14.0 团队远程候选 | 0.7.0 候选 | 命名 HTTPS 连接、固定团队 CA、远程导入/查询/下载 |

0.7.0 的 Windows x64 身份与团队连接适配见[身份合同](docs/src/member-auth.md)；它仍是未经标签或 General
注册的候选源码。产品仓库的机器可读兼容合同在验收后固定可安装的精确提交。实现和文档有大量
AI 辅助贡献，维护者须在 General 注册前亲自审阅并理解代码，见 [MIGRATION.md](MIGRATION.md)。

## 连接

完整安装包注册当前用户的登录服务任务；不需要先打开桌面窗口。随后：

```julia
using ResearchVault

connect_local() do vault
    println(health(vault).version)
    println(length(projects(vault)))
end
```

团队成员先用 team-client 导入管理员发放的一次性 `.rvinvite`，核对服务器地址与 CA 指纹；SDK 不接收
URL 或 token，只按已登记名称连接：

```julia
connect_team("实验室服务器") do vault
    context = identity_context(vault)
    @info "connected" context.user_id context.role
    println(length(projects(vault)))
end
```

团队导入仍调用 `import_dataset` / `import_dataset_version`。SDK 会在本机读取并哈希文件、按 8 MiB
分块上传、服务端校验后幂等创建不可变 DatasetVersion；客户端绝对路径不会发送到服务器。

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

Julia SDK 是高信任客户端。`connect_local` 可提交本机路径；`connect_team` 只传逻辑路径和字节，
并复用 team-client 保存的个人桌面凭据。它不提供任意 SQL/URL/token、成员管理、发布、删除、迁移或
GC。当前团队服务器是 DataOnly；远程科学计算、无头图形和服务器路径导出会在提交前失败。

完整示例见 `examples/experimental_workflow.jl`，API 与故障处理见 `docs/`。
