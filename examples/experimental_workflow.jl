using ResearchVault
using Tables

length(ARGS) == 1 || error("usage: julia experimental_workflow.jl PATH_TO_EXPERIMENT.csv")

connect_local() do vault
    project_record = create_project(
        vault;
        title="Julia experiment",
        research_goal="Compare experimental observations with reproducible scenarios",
    )
    importing = import_dataset(
        vault,
        only(ARGS);
        title="Experimental observations",
        kind=:experimental_table,
        provenance=:measured,
    )
    imported = wait_success(
        vault,
        importing.id;
        on_progress=task -> println("$(round(task.progress * 100; digits=1))% $(task.message)"),
    )
    version = dataset_version(vault, imported.result_resource_id)
    attach_resource(
        vault,
        project_record.id,
        :dataset_version,
        version.id;
        role="evidence",
    )
    create_machine_view(vault, version.id)
    table = query_dataset(vault, version.id, QuerySpec(limit=20))
    println("columns: ", Tables.columnnames(table), ", rows: ", length(table))
end

