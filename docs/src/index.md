# ResearchVault.jl

`ResearchVault.jl` 是 Research Vault 的类型化 Julia 客户端；包 0.7.0 候选保留本机 loopback
连接，并支持 Windows team-client 登记的私有 CA HTTPS 团队连接。它面向 Julia 1.10+ 的科研代码，
通过受权 API 使用 Project、DatasetVersion、Run、Figure、Task 和 Artifact，并遵守与桌面端相同的
身份与不可变数据合同。

## 最小示例

```julia
using ResearchVault

connect_local() do vault
    @show health(vault).version
    @show projects(vault)
end
```

导入团队邀请后按桌面中的连接名称使用：

```julia
connect_team("实验室服务器") do vault
    @show identity_context(vault)
end
```

包不会直接读取 Catalog 或 CAS，也不会发布 Figure、执行删除、迁移、GC、任意 SQL 或任意代码。

```@docs
ResearchVault
```
