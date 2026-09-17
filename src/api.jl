function _segment(value)
    segment = String(value)
    occursin(r"^[A-Za-z0-9_-]+$", segment) ||
        throw(ArgumentError("resource identifier contains unsupported characters"))
    return segment
end

function _query_path(path::AbstractString, parameters)
    encoded = String[]
    for (key, value) in parameters
        value === nothing && continue
        push!(encoded, "$(HTTP.escapeuri(String(key)))=$(HTTP.escapeuri(string(value)))")
    end
    return isempty(encoded) ? String(path) : String(path) * "?" * join(encoded, "&")
end

function _open_object(value, context::AbstractString)
    value isa AbstractDict || _invalid_response("$context must be an object")
    return Dict{String,Any}(String(key) => item for (key, item) in value)
end

function _items(value, model_type)
    object = _open_object(value, "list response")
    haskey(object, "items") || _invalid_response("list response omitted items")
    return [_parse_model(model_type, item) for item in _vector(object["items"], "items")]
end

function _task_response(value)
    object = _strict_object(value, ("task",))
    return _parse_model(VaultTask, object["task"])
end

function projects(client::VaultClient; include_deleted::Bool=false)
    path = _query_path(
        "/api/v1/research-projects",
        ["include_deleted" => include_deleted],
    )
    return _items(_request_json(client, "GET", path), ResearchProject)
end

function project(client::VaultClient, project_id)
    value = _strict_object(
        _request_json(client, "GET", "/api/v1/research-projects/$(_segment(project_id))"),
        ("project", "resources"),
    )
    resources = [
        _parse_model(ProjectResource, item) for
        item in _vector(value["resources"], "resources")
    ]
    return (project=_parse_model(ResearchProject, value["project"]), resources=resources)
end

function create_project(
    client::VaultClient;
    title,
    description=nothing,
    research_goal=nothing,
    agent_context=nothing,
    tags=String[],
    default_style=nothing,
)
    payload = Dict{String,Any}(
        "title" => String(title),
        "description" => description,
        "research_goal" => research_goal,
        "agent_context" => agent_context,
        "tags" => String.(tags),
    )
    default_style === nothing || (payload["default_style"] = _json_object(default_style))
    return _parse_model(
        ResearchProject,
        _request_json(client, "POST", "/api/v1/research-projects"; body=payload),
    )
end

function update_project(
    client::VaultClient,
    project_id;
    title,
    description=nothing,
    research_goal=nothing,
    agent_context=nothing,
    tags=String[],
    default_style=Dict{String,Any}(),
)
    payload = Dict(
        "title" => String(title),
        "description" => description,
        "research_goal" => research_goal,
        "agent_context" => agent_context,
        "tags" => String.(tags),
        "default_style" => _json_object(default_style),
    )
    return _parse_model(
        ResearchProject,
        _request_json(
            client,
            "PATCH",
            "/api/v1/research-projects/$(_segment(project_id))";
            body=payload,
        ),
    )
end

function project_resources(client::VaultClient, project_id)
    return _items(
        _request_json(
            client,
            "GET",
            "/api/v1/research-projects/$(_segment(project_id))/resources",
        ),
        ProjectResource,
    )
end

function attach_resource(
    client::VaultClient,
    project_id,
    resource_type,
    resource_id;
    role="reference",
    note=nothing,
)
    payload = Dict(
        "resource_type" => String(resource_type),
        "resource_id" => String(resource_id),
        "role" => String(role),
        "note" => note,
    )
    return _parse_model(
        ProjectResource,
        _request_json(
            client,
            "POST",
            "/api/v1/research-projects/$(_segment(project_id))/resources";
            body=payload,
        ),
    )
end

function datasets(
    client::VaultClient;
    include_deleted::Bool=false,
    query=nothing,
    kind=nothing,
    tag=nothing,
    status=nothing,
    limit::Integer=50,
    cursor::Integer=0,
)
    1 <= limit <= 100 || throw(ArgumentError("dataset limit must be between 1 and 100"))
    cursor >= 0 || throw(ArgumentError("dataset cursor cannot be negative"))
    path = _query_path(
        "/api/v1/datasets",
        [
            "include_deleted" => include_deleted,
            "query" => query,
            "kind" => kind,
            "tag" => tag,
            "status" => status,
            "limit" => limit,
            "cursor" => cursor,
        ],
    )
    return _items(_request_json(client, "GET", path), Dataset)
end

dataset(client::VaultClient, dataset_id) = _parse_model(
    Dataset,
    _request_json(client, "GET", "/api/v1/datasets/$(_segment(dataset_id))"),
)

function update_dataset(
    client::VaultClient,
    dataset_id;
    title,
    description=nothing,
    tags=String[],
    source_summary=nothing,
)
    payload = Dict(
        "title" => String(title),
        "description" => description,
        "tags" => String.(tags),
        "source_summary" => source_summary,
    )
    return _parse_model(
        Dataset,
        _request_json(
            client,
            "PATCH",
            "/api/v1/datasets/$(_segment(dataset_id))";
            body=payload,
        ),
    )
end


function _import_payload(
    source_path;
    title,
    description,
    kind,
    tags,
    source_summary,
    source,
    provenance,
    scientific_metadata,
    warnings,
    format_contract=nothing,
)
    path = abspath(expanduser(String(source_path)))
    ispath(path) || throw(ArgumentError("import source does not exist"))
    metadata = _json_object(scientific_metadata)
    if format_contract !== nothing
        haskey(metadata, "tabular_contract") && throw(ArgumentError("supply the format contract once"))
        metadata["tabular_contract"] = _json_object(format_contract)
    end
    return Dict{String,Any}(
        "source_path" => path,
        "title" => String(title),
        "description" => description,
        "kind" => String(kind),
        "tags" => String.(tags),
        "source_summary" => source_summary,
        "source" => source === nothing ? nothing : _json_object(source),
        "provenance" => provenance === nothing ? nothing : String(provenance),
        "scientific_metadata" => metadata,
        "warnings" => String.(warnings),
    )
end

function import_dataset(
    client::VaultClient,
    source_path;
    title,
    description=nothing,
    kind=:generic,
    tags=String[],
    source_summary=nothing,
    source=nothing,
    provenance=nothing,
    scientific_metadata=Dict{String,Any}(),
    warnings=String[],
    format_contract=nothing,
)
    if client.mode == :team
        return _team_import(
            client,
            source_path;
            title,
            description,
            kind,
            tags,
            source_summary,
            source,
            provenance,
            scientific_metadata,
            warnings,
            format_contract,
        )
    end
    payload = _import_payload(
        source_path;
        title,
        description,
        kind,
        tags,
        source_summary,
        source,
        provenance,
        scientific_metadata,
        warnings,
        format_contract,
    )
    return _task_response(
        _request_json(client, "POST", "/api/v1/datasets/import-local"; body=payload),
    )
end

function import_dataset_version(
    client::VaultClient,
    dataset_id,
    source_path;
    title,
    description=nothing,
    kind=:generic,
    tags=String[],
    source_summary=nothing,
    source=nothing,
    provenance=nothing,
    scientific_metadata=Dict{String,Any}(),
    warnings=String[],
    format_contract=nothing,
)
    if client.mode == :team
        return _team_import(
            client,
            source_path;
            target_dataset_id=String(dataset_id),
            title,
            description,
            kind,
            tags,
            source_summary,
            source,
            provenance,
            scientific_metadata,
            warnings,
            format_contract,
        )
    end
    payload = _import_payload(
        source_path;
        title,
        description,
        kind,
        tags,
        source_summary,
        source,
        provenance,
        scientific_metadata,
        warnings,
        format_contract,
    )
    return _task_response(
        _request_json(
            client,
            "POST",
            "/api/v1/datasets/$(_segment(dataset_id))/versions/import-local";
            body=payload,
        ),
    )
end

function _scientific_import(client, route, source_path; options=Dict{String,Any}())
    client.mode == :team &&
        throw(VaultConnectionError("team capability unavailable: scientific_import"))
    path = abspath(expanduser(String(source_path)))
    isfile(path) || throw(ArgumentError("scientific import source must be a regular file"))
    payload = Dict("source_path" => path, "options" => _json_object(options))
    return _task_response(_request_json(client, "POST", route; body=payload))
end

import_weather_dataset(client::VaultClient, source_path; options=Dict{String,Any}()) =
    _scientific_import(client, "/api/v1/weather-datasets/import-local", source_path; options)
import_equipment_curve(client::VaultClient, source_path; options=Dict{String,Any}()) =
    _scientific_import(client, "/api/v1/equipment-curves/import-local", source_path; options)

function dataset_versions(client::VaultClient, dataset_id)
    return _items(
        _request_json(
            client,
            "GET",
            "/api/v1/datasets/$(_segment(dataset_id))/versions",
        ),
        DatasetVersion,
    )
end

dataset_version(client::VaultClient, version_id) = _parse_model(
    DatasetVersion,
    _request_json(client, "GET", "/api/v1/dataset-versions/$(_segment(version_id))"),
)

dataset_manifest(client::VaultClient, version_id) = _open_object(
    _request_json(client, "GET", "/api/v1/dataset-versions/$(_segment(version_id))/manifest"),
    "dataset manifest",
)

"""Read a version's saved contract, file mapping and validation summary."""
dataset_format(client::VaultClient, version_id) = _open_object(
    _request_json(client, "GET", "/api/v1/dataset-versions/$(_segment(version_id))/format-contract"),
    "dataset format",
)

"""Create an immutable successor reusing original Blobs; stale bases raise VaultError."""
function revise_dataset_format(client::VaultClient, version_id, contract; reason)
    value = _strict_object(_request_json(client, "POST",
        "/api/v1/dataset-versions/$(_segment(version_id))/format-revisions";
        body=Dict("contract" => _json_object(contract), "reason" => String(reason))),
        ("dataset", "version", "manifest", "deduplicated_files"))
    return (dataset=_parse_model(Dataset, value["dataset"]),
        version=_parse_model(DatasetVersion, value["version"]),
        manifest=_open_object(value["manifest"], "manifest"),
        deduplicated_files=value["deduplicated_files"])
end
dataset_usage(client::VaultClient, dataset_id) = _open_object(
    _request_json(client, "GET", "/api/v1/datasets/$(_segment(dataset_id))/usage"),
    "dataset usage",
)

function machine_views(client::VaultClient, version_id)
    return _items(
        _request_json(
            client,
            "GET",
            "/api/v1/dataset-versions/$(_segment(version_id))/views",
        ),
        MachineView,
    )
end

function create_machine_view(client::VaultClient, version_id; logical_path=nothing)
    return _parse_model(
        MachineView,
        _request_json(
            client,
            "POST",
            "/api/v1/dataset-versions/$(_segment(version_id))/views";
            body=Dict("logical_path" => logical_path),
        ),
    )
end

function query_dataset(client::VaultClient, version_id, query::QuerySpec; logical_path=nothing)
    value = _request_json(
        client,
        "POST",
        "/api/v1/dataset-versions/$(_segment(version_id))/query";
        body=Dict("logical_path" => logical_path, "query" => _wire(query)),
    )
    return _vault_table(value)
end

function start_scenario_run(client::VaultClient, request::ScenarioRunRequest)
    client.mode == :team &&
        throw(VaultConnectionError("team capability unavailable: scientific_compute"))
    return _task_response(
        _request_json(
            client,
            "POST",
            "/api/v1/scenario-runs";
            body=request.payload,
        ),
    )
end

start_scenario_run(client::VaultClient, request) =
    start_scenario_run(client, ScenarioRunRequest(request))

function runs(client::VaultClient; include_deleted::Bool=false)
    path = _query_path("/api/v1/runs", ["include_deleted" => include_deleted])
    return _items(_request_json(client, "GET", path), Run)
end

run(client::VaultClient, run_id) = _parse_model(
    RunRecord,
    _request_json(client, "GET", "/api/v1/runs/$(_segment(run_id))"),
)
run_preview(client::VaultClient, run_id) = _open_object(
    _request_json(client, "GET", "/api/v1/runs/$(_segment(run_id))/preview"),
    "run preview",
)
run_result(client::VaultClient, run_id) = _open_object(
    _request_json(client, "GET", "/api/v1/runs/$(_segment(run_id))/result"),
    "run result",
)

function query_run(
    client::VaultClient,
    run_id;
    variables,
    start,
    stop,
    max_points::Integer=4_000,
    scenario_indices=nothing,
)
    normalized_variables = String.(variables)
    1 <= length(normalized_variables) <= 32 ||
        throw(ArgumentError("run query requires between 1 and 32 variables"))
    10 <= max_points <= 4_000 ||
        throw(ArgumentError("run query max_points must be between 10 and 4000"))
    parse_rfc3339(String(start))
    parse_rfc3339(String(stop))
    normalized_indices = scenario_indices === nothing ? nothing : Int.(scenario_indices)
    if normalized_indices !== nothing
        1 <= length(normalized_indices) <= 10 ||
            throw(ArgumentError("scenario_indices must contain between 1 and 10 values"))
        length(unique(normalized_indices)) == length(normalized_indices) ||
            throw(ArgumentError("scenario_indices cannot contain duplicates"))
        all(>=(0), normalized_indices) ||
            throw(ArgumentError("scenario_indices are zero-based and cannot be negative"))
    end
    value = _request_json(
        client,
        "POST",
        "/api/v1/runs/$(_segment(run_id))/query";
        body=Dict(
            "variables" => normalized_variables,
            "start" => String(start),
            "end" => String(stop),
            "max_points" => Int(max_points),
            "scenario_indices" => normalized_indices,
        ),
    )
    return _run_window_table(value, normalized_variables)
end

function export_run(
    client::VaultClient,
    run_id,
    destination;
    format=:csv_zip,
    power_unit=:MW,
)
    client.mode == :team &&
        throw(VaultConnectionError("server-local path export is unavailable through a team connection"))
    format in (:csv_zip, :parquet_zip, "csv_zip", "parquet_zip") ||
        throw(ArgumentError("run export format must be csv_zip or parquet_zip"))
    power_unit in (:MW, :kW, "MW", "kW") ||
        throw(ArgumentError("power_unit must be MW or kW"))
    payload = Dict(
        "format" => String(format),
        "destination" => abspath(expanduser(String(destination))),
        "power_unit" => String(power_unit),
    )
    return _task_response(
        _request_json(
            client,
            "POST",
            "/api/v1/runs/$(_segment(run_id))/export";
            body=payload,
        ),
    )
end

task(client::VaultClient, task_id) = _parse_model(
    VaultTask,
    _request_json(client, "GET", "/api/v1/tasks/$(_segment(task_id))"),
)
task_result(client::VaultClient, task_id) = _open_object(
    _request_json(client, "GET", "/api/v1/tasks/$(_segment(task_id))/result"),
    "task result",
)
cancel_task(client::VaultClient, task_id) = _parse_model(
    VaultTask,
    _request_json(client, "POST", "/api/v1/tasks/$(_segment(task_id))/cancel"; body=Dict()),
)

function wait_task(
    client::VaultClient,
    task_id;
    on_progress=(_task -> nothing),
    timeout::Real=600.0,
    poll_interval::Real=0.25,
    cancel_on_timeout::Bool=false,
    cancel_on_interrupt::Bool=false,
)
    timeout > 0 || throw(ArgumentError("timeout must be positive"))
    poll_interval > 0 || throw(ArgumentError("poll_interval must be positive"))
    normalized_id = String(task_id)
    deadline = time() + Float64(timeout)
    last_state = nothing
    try
        while time() < deadline
            current = task(client, normalized_id)
            state = (
                current.status,
                current.phase,
                current.progress,
                current.completed_units,
                current.total_units,
                current.message,
            )
            if state != last_state
                on_progress(current)
                last_state = state
            end
            terminal(current) && return current
            sleep(Float64(poll_interval))
        end
    catch error
        if error isa InterruptException && cancel_on_interrupt
            try
                cancel_task(client, normalized_id)
            catch
            end
        end
        rethrow()
    end
    cancel_on_timeout && cancel_task(client, normalized_id)
    throw(VaultTaskTimeoutError(normalized_id, Float64(timeout)))
end

function wait_success(client::VaultClient, task_id; kwargs...)
    completed = wait_task(client, task_id; kwargs...)
    completed.status == "completed" || throw(VaultTaskError(completed))
    return completed
end

function figures(client::VaultClient; include_deleted::Bool=false)
    path = _query_path("/api/v1/figures", ["include_deleted" => include_deleted])
    return _items(_request_json(client, "GET", path), Figure)
end

figure(client::VaultClient, figure_id) = _parse_model(
    FigureRecord,
    _request_json(client, "GET", "/api/v1/figures/$(_segment(figure_id))"),
)

function create_figure(
    client::VaultClient,
    project_id;
    title,
    kind,
    description=nothing,
    tags=String[],
)
    payload = Dict(
        "title" => String(title),
        "description" => description,
        "tags" => String.(tags),
        "kind" => String(kind),
    )
    return _parse_model(
        Figure,
        _request_json(
            client,
            "POST",
            "/api/v1/research-projects/$(_segment(project_id))/figures";
            body=payload,
        ),
    )
end

function update_figure(
    client::VaultClient,
    figure_id;
    title,
    description=nothing,
    tags=String[],
)
    payload = Dict(
        "title" => String(title),
        "description" => description,
        "tags" => String.(tags),
    )
    return _parse_model(
        Figure,
        _request_json(
            client,
            "PATCH",
            "/api/v1/figures/$(_segment(figure_id))";
            body=payload,
        ),
    )
end

function figure_revisions(client::VaultClient, figure_id)
    return _items(
        _request_json(
            client,
            "GET",
            "/api/v1/figures/$(_segment(figure_id))/revisions",
        ),
        FigureRevision,
    )
end

figure_revision(client::VaultClient, revision_id) = _parse_model(
    FigureRevisionRecord,
    _request_json(client, "GET", "/api/v1/figure-revisions/$(_segment(revision_id))"),
)
figure_revision_usage(client::VaultClient, revision_id) = _open_object(
    _request_json(
        client,
        "GET",
        "/api/v1/figure-revisions/$(_segment(revision_id))/usage",
    ),
    "figure revision usage",
)

function revise_figure(
    client::VaultClient,
    figure_id,
    base_revision_id,
    spec;
    inputs=Any[],
    client_summary=nothing,
    renderer_requirements=Dict{String,Any}(),
    warnings=String[],
)
    payload = Dict(
        "base_revision_id" => base_revision_id,
        "spec" => _json_object(spec),
        "inputs" => [_json_object(input) for input in inputs],
        "source" => "sdk",
        "client_summary" => client_summary,
        "renderer_requirements" => _json_object(renderer_requirements),
        "warnings" => String.(warnings),
    )
    return _parse_model(
        FigureRevisionRecord,
        _request_json(
            client,
            "POST",
            "/api/v1/figures/$(_segment(figure_id))/revisions";
            body=payload,
        ),
    )
end

function compare_figure_revisions(client::VaultClient, from_revision_id, to_revision_id)
    from_record = figure_revision(client, from_revision_id)
    path = _query_path(
        "/api/v1/figures/$(_segment(from_record.revision.figure_id))/diff",
        ["from" => from_revision_id, "to" => to_revision_id],
    )
    return _open_object(_request_json(client, "GET", path), "figure revision diff")
end

function render_figure(client::VaultClient, revision_id; formats=[:png, :svg, :pdf])
    client.mode == :team &&
        throw(VaultConnectionError("team capability unavailable: headless_render"))
    normalized = String.(formats)
    all(format -> format in ("png", "svg", "pdf"), normalized) ||
        throw(ArgumentError("render formats must be png, svg, or pdf"))
    return _task_response(
        _request_json(
            client,
            "POST",
            "/api/v1/figure-revisions/$(_segment(revision_id))/render";
            body=Dict("formats" => normalized),
        ),
    )
end

figure_renders(client::VaultClient, figure_id) = _open_object(
    _request_json(client, "GET", "/api/v1/figures/$(_segment(figure_id))/renders"),
    "figure renders",
)
figure_templates(client::VaultClient) = _open_object(
    _request_json(client, "GET", "/api/v1/figure-templates"),
    "figure templates",
)

function restore_figure_revision(client::VaultClient, figure_id, target_revision_id, base_revision_id)
    payload = Dict(
        "target_revision_id" => String(target_revision_id),
        "base_revision_id" => String(base_revision_id),
    )
    return _parse_model(
        FigureRevisionRecord,
        _request_json(
            client,
            "POST",
            "/api/v1/figures/$(_segment(figure_id))/restore-revision";
            body=payload,
        ),
    )
end

function create_figure_from_run(
    client::VaultClient,
    run_id;
    project_id,
    title,
    y_columns,
    description=nothing,
    tags=String[],
    artifact_logical_name=nothing,
    x_column="timestamp",
)
    payload = Dict(
        "project_id" => String(project_id),
        "title" => String(title),
        "description" => description,
        "tags" => String.(tags),
        "artifact_logical_name" => artifact_logical_name,
        "x_column" => String(x_column),
        "y_columns" => String.(y_columns),
    )
    value = _strict_object(
        _request_json(
            client,
            "POST",
            "/api/v1/runs/$(_segment(run_id))/figures";
            body=payload,
        ),
        ("figure", "revision"),
    )
    revision = _parse_model(FigureRevisionRecord, value["revision"])
    figure_record = figure(client, revision.revision.figure_id)
    return (
        figure=figure_record.figure,
        revision=revision,
    )
end

function create_figure_from_dataset(
    client::VaultClient,
    version_id;
    project_id,
    title,
    x_column,
    y_column,
    description=nothing,
    tags=String[],
    logical_path=nothing,
    lower_column=nothing,
    upper_column=nothing,
)
    payload = Dict(
        "project_id" => String(project_id),
        "title" => String(title),
        "description" => description,
        "tags" => String.(tags),
        "logical_path" => logical_path,
        "x_column" => String(x_column),
        "y_column" => String(y_column),
        "lower_column" => lower_column,
        "upper_column" => upper_column,
    )
    value = _strict_object(
        _request_json(
            client,
            "POST",
            "/api/v1/dataset-versions/$(_segment(version_id))/figures";
            body=payload,
        ),
        ("figure", "revision"),
    )
    revision = _parse_model(FigureRevisionRecord, value["revision"])
    figure_record = figure(client, revision.revision.figure_id)
    return (
        figure=figure_record.figure,
        revision=revision,
    )
end

artifact(client::VaultClient, artifact_id) = _parse_model(
    Artifact,
    _request_json(client, "GET", "/api/v1/artifacts/$(_segment(artifact_id))"),
)

"""Passive service and Worker state; does not load or renew any Worker."""
runtime_status(client::VaultClient) = client.mode == :team ?
    throw(VaultConnectionError("server-local runtime control is unavailable through a team connection")) :
    _open_object(_request_json(client, "GET", "/api/v1/runtime"), "runtime status")
administrator(client::VaultClient) = client.mode == :team ?
    throw(VaultConnectionError("server-local administration is unavailable through a team connection")) :
    _open_object(_request_json(client, "GET", "/api/v1/administrator"), "administrator")

"""Discover installed font faces; paths and font files never leave the service."""
function figure_fonts(client::VaultClient; search="", offset=0, limit=100)
    return _open_object(_request_json(client, "GET", _query_path("/api/v1/fonts",
        ["search" => search, "offset" => offset, "limit" => limit])), "font catalog")
end

figure_render_batches(client::VaultClient, figure_id) = _open_object(
    _request_json(client, "GET", "/api/v1/figures/$(_segment(figure_id))/render-batches"), "render batches")

"""Prepare a rebuildable interactive cache; return ready data or a pollable task, not a render Run."""
function prepare_figure_preview(client::VaultClient, revision_id; run_id=nothing, artboard_id=nothing,
                                window=nothing, max_points=4000)
    client.mode == :team &&
        throw(VaultConnectionError("Julia headless figure preview is unavailable through a team connection"))
    return _open_object(_request_json(client, "POST", "/api/v1/figure-revisions/$(_segment(revision_id))/interactive-preview";
        body=Dict("run_id"=>run_id, "artboard_id"=>artboard_id, "window"=>window, "max_points"=>max_points)), "interactive preview")
end

function figure_preview(client::VaultClient, preview_id)
    occursin(r"^fpv_[0-9a-f]{64}$", String(preview_id)) || throw(ArgumentError("expected preview ID"))
    return _open_object(_request_json(client, "GET", "/api/v1/figure-previews/$preview_id"), "interactive preview")
end

function export_artifact(client::VaultClient, artifact_id, destination)
    client.mode == :team &&
        throw(VaultConnectionError("server-local path export is unavailable through a team connection"))
    return _open_object(
        _request_json(
            client,
            "POST",
            "/api/v1/artifacts/$(_segment(artifact_id))/export";
            body=Dict("destination" => abspath(expanduser(String(destination)))),
        ),
        "artifact export",
    )
end
