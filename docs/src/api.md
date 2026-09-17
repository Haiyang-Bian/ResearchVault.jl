# API 概览

连接：`connect_local`、`close`、`health`、`identity_context`。

0.6.0 适配旧单用户和 Windows x64 成员身份、常驻服务及原生计划任务激活；被动查询不启动或续期科学 Worker/绘图宿主：

```@docs
runtime_status
identity_context
```

`identity_context` 返回 `IdentityContext`，不包含访问令牌。

科研项目：`projects`、`project`、`create_project`、`update_project`、`project_resources`、
`attach_resource`。

数据集：`datasets`、`dataset`、`dataset_versions`、`dataset_version`、`import_dataset`、
`import_dataset_version`、`create_machine_view`、`query_dataset`。

0.2.0 增加不可变格式约定。导入可传 `format_contract`，或对现有版本创建后继版本；不会更改旧文件、旧视图或项目固定引用。

```@docs
dataset_format
revise_dataset_format
```

场景与任务：`start_scenario_run`、`runs`、`run`、`run_preview`、`query_run`、`task`、
`wait_task`、`wait_success`、`cancel_task`。

Figure：`figure_templates`、`create_figure`、`revise_figure`、`compare_figure_revisions`、
`create_figure_from_dataset`、`create_figure_from_run`、`render_figure`。

Artifact：`artifact`、`download_artifact`、`export_artifact`。

0.3.0 增加系统字体、正式渲染批次与有界交互数据发现；不会发布或更改科研图。
`figure_render_batches` 返回按 Run 归组的历史记录；`figure_preview` 读取准备完成后的缓存。

```@docs
figure_fonts
prepare_figure_preview
```

查询类型：`QuerySpec`、`QueryFilter`、`QueryAggregate`、`QueryTimeBucket`、`QueryOrder`、
`VaultTable`。场景请求使用 `ScenarioRunRequest`，只复制 protocol v5 必要外层校验，嵌套科学参数仍
由服务和 Pydantic 严格验证。
