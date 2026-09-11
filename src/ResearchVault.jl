"""
Typed local Julia client for Research Vault.

The package communicates only with the loopback `research-vault-service` API. It does
not open the Vault catalog, CAS, or scientific worker directly.
"""
module ResearchVault

using Dates
using HTTP
using JSON
using SHA
using Sockets
using Tables

const CLIENT_VERSION = v"0.5.1"
const SERVICE_API_VERSION = 1
const MINIMUM_JULIA_VERSION = v"1.10"

include("errors.jl")
include("models.jl")
include("transport.jl")
include("discovery.jl")
include("query.jl")
include("api.jl")
include("artifacts.jl")

export Artifact,
    CLIENT_VERSION,
    Dataset,
    DatasetVersion,
    Figure,
    FigureRevision,
    FigureRevisionRecord,
    Health,
    MachineView,
    QueryAggregate,
    QueryFilter,
    QueryOrder,
    QuerySpec,
    QueryTimeBucket,
    ProjectResource,
    ResearchProject,
    Rfc3339Timestamp,
    Run,
    RunRecord,
    ScenarioRunRequest,
    SERVICE_API_VERSION,
    VaultClient,
    VaultConnectionError,
    VaultError,
    VaultIntegrityError,
    VaultTask,
    VaultTaskError,
    VaultTaskTimeoutError,
    VaultTable,
    artifact,
    attach_resource,
    cancel_task,
    close,
    connect_local,
    create_figure,
    create_figure_from_dataset,
    create_figure_from_run,
    create_machine_view,
    create_project,
    dataset,
    dataset_manifest,
    dataset_format,
    revise_dataset_format,
    dataset_usage,
    dataset_version,
    dataset_versions,
    datasets,
    download_artifact,
    export_artifact,
    export_run,
    figure,
    figure_renders,
    figure_revision,
    figure_revision_usage,
    figure_revisions,
    figure_templates,
    figure_fonts,
    figure_render_batches,
    prepare_figure_preview,
    figure_preview,
    figures,
    health,
    runtime_status,
    administrator,
    import_dataset,
    import_dataset_version,
    import_equipment_curve,
    import_weather_dataset,
    machine_views,
    parse_rfc3339,
    project,
    project_resources,
    projects,
    query_dataset,
    query_run,
    render_figure,
    restore_figure_revision,
    revise_figure,
    run,
    run_preview,
    run_result,
    runs,
    start_scenario_run,
    task,
    task_result,
    terminal,
    update_dataset,
    update_figure,
    update_project,
    wait_success,
    wait_task,
    compare_figure_revisions

end
