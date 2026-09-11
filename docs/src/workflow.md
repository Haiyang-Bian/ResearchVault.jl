# 科研工作流

## 导入与查询

`import_dataset` 返回后台 Task。Task 完成后的 `result_resource_id` 是不可变 DatasetVersion ID。
`query_dataset` 只接受受限 `QuerySpec`，不接受 SQL，并受服务端 4,000 行、10 MiB、30 秒边界约束。

```julia
task_record = import_dataset(
    vault,
    raw"D:\experiment\result.csv";
    title="Experiment result",
    kind=:experimental_table,
    provenance=:measured,
)
completed = wait_success(vault, task_record.id)
version = dataset_version(vault, completed.result_resource_id)

table = query_dataset(
    vault,
    version.id,
    QuerySpec(
        columns=["timestamp", "value"],
        filters=[QueryFilter("value", "gte"; value=0)],
        order_by=[QueryOrder("timestamp")],
        limit=4000,
    );
    logical_path="result.csv",
)
```

`VaultTable` 实现 Tables.jl；安装 DataFrames.jl 后可直接 `DataFrame(table)`。

## Task

`wait_task` 返回任意终态；`wait_success` 在失败、取消或中断时抛出 `VaultTaskError`。回调只在
状态、阶段或进度发生变化时调用。超时默认不取消服务端任务；只有显式
`cancel_on_timeout=true` 才请求取消。

## Figure 与 Artifact

Agent或 Julia 只能创建 Figure 工作版本。每次修订必须提供当前 `base_revision_id`，过期版本返回
`revision_conflict`。正式渲染可生成 SVG、PNG 和 PDF；`download_artifact` 使用同目录临时文件，
校验大小与 SHA-256 后原子改名。

发布仍由 Research Vault 桌面端人工确认。
