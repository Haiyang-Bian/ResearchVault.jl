# ResearchVault.jl

`ResearchVault.jl` 是 Research Vault 本地服务的类型化 Julia 客户端；包 0.5.1 适配 0.13.1 和 0.14.x
常驻服务、被动运行状态与计划任务激活，保留字体、渲染批次和交互预览接口。它面向 Julia
1.10+ 的科研代码，通过回环 HTTP API 使用 Project、DatasetVersion、Run、Figure、Task 和
Artifact，并遵守与桌面端、Python SDK 和 MCP 相同的数据安全合同。

## 最小示例

```julia
using ResearchVault

connect_local() do vault
    @show health(vault).version
    @show projects(vault)
end
```

包不会直接读取 Catalog 或 CAS，也不会发布 Figure、执行删除、迁移、GC、任意 SQL 或任意代码。

```@docs
ResearchVault
```
