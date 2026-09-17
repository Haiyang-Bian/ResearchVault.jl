const JsonObject = Dict{String,Any}

struct Health
    product::String
    version::String
    healthy::Bool
    engine::Union{Nothing,JsonObject}
end

struct IdentityContext
    server_id::String
    workspace_id::String
    user_id::String
    role::String
    permissions::Vector{String}
    capabilities::Vector{String}
    limits::JsonObject
end

struct ResearchProject
    id::String
    workspace_id::String
    title::String
    description::Union{Nothing,String}
    research_goal::Union{Nothing,String}
    agent_context::Union{Nothing,String}
    tags::Vector{String}
    default_style::JsonObject
    status::String
    created_at::String
    updated_at::String
    deleted_at::Union{Nothing,String}
end

struct ProjectResource
    project_id::String
    resource_type::String
    resource_id::String
    role::String
    added_by::String
    note::Union{Nothing,String}
    created_at::String
end

struct Dataset
    id::String
    workspace_id::String
    title::String
    description::Union{Nothing,String}
    kind::String
    tags::Vector{String}
    source_summary::Union{Nothing,String}
    status::String
    created_at::String
    updated_at::String
    deleted_at::Union{Nothing,String}
end

struct DatasetVersion
    id::String
    dataset_id::String
    ordinal::Int
    status::String
    manifest_hash::String
    file_count::Int
    size_bytes::Int
    source::JsonObject
    provenance::String
    schema_version::Int
    created_at::String
    created_by::String
end

struct MachineView
    id::String
    source_version_id::String
    logical_path::Union{Nothing,String}
    kind::String
    generator::String
    generator_version::String
    source_manifest_hash::String
    status::String
    blob_hash::Union{Nothing,String}
    inline_json::Any
    created_at::String
    error::Union{Nothing,String}
end

struct Run
    id::String
    workspace_id::String
    task_id::Union{Nothing,String}
    kind::String
    status::String
    retention::String
    request::Any
    parameters::Any
    seed::Union{Nothing,Int}
    model_versions::Any
    protocol_version::Int
    environment::Any
    git::JsonObject
    started_at::String
    finished_at::Union{Nothing,String}
    warnings::Vector{String}
    error::Any
    deleted_at::Union{Nothing,String}
end

struct VaultTask
    id::String
    workspace_id::String
    kind::String
    status::String
    phase::String
    completed_units::Int
    total_units::Int
    progress::Float64
    message::String
    request_id::String
    started_at::Union{Nothing,String}
    finished_at::Union{Nothing,String}
    error::Any
    result_resource_id::Union{Nothing,String}
end

terminal(task::VaultTask) = task.status in ("completed", "failed", "cancelled", "interrupted")

struct VaultTaskError <: AbstractVaultException
    task::VaultTask
end

function Base.showerror(io::IO, error::VaultTaskError)
    print(io, "Research Vault task ", error.task.id, " ended as ", error.task.status)
end

struct Artifact
    id::String
    run_id::String
    name::String
    role::String
    blob_hash::String
    media_type::String
    size_bytes::Int
    metadata::Any
    created_at::String
end

struct Figure
    id::String
    primary_project_id::String
    title::String
    description::Union{Nothing,String}
    tags::Vector{String}
    kind::String
    head_revision_id::Union{Nothing,String}
    published_revision_id::Union{Nothing,String}
    status::String
    created_at::String
    updated_at::String
    deleted_at::Union{Nothing,String}
end

struct FigureRevision
    id::String
    figure_id::String
    parent_revision_id::Union{Nothing,String}
    ordinal::Int
    spec_blob_hash::String
    normalized_spec_hash::String
    schema_version::Int
    source::String
    client_summary::Union{Nothing,String}
    renderer_requirements::Any
    warnings::Vector{String}
    created_at::String
    created_by::String
end

struct FigureRevisionRecord
    revision::FigureRevision
    spec::Any
    inputs::Vector{Any}
end

struct FigureRender
    payload::JsonObject
end

struct RunRecord
    run::Run
    inputs::Vector{Any}
    artifacts::Vector{Artifact}
end

struct FigureRecord
    figure::Figure
    revisions::Vector{FigureRevision}
end

struct ScenarioRunRequest
    payload::JsonObject

    function ScenarioRunRequest(value)
        payload = _json_object(value)
        get(payload, "type", "generate") == "generate" ||
            throw(ArgumentError("scenario request type must be generate"))
        payload["type"] = "generate"
        required = (
            "protocol_version",
            "timezone",
            "start",
            "end",
            "resolution_minutes",
            "interval_semantics",
            "scenario_count",
            "seed",
            "requested_variables",
            "temperature",
        )
        missing_keys = [key for key in required if !haskey(payload, key)]
        isempty(missing_keys) ||
            throw(ArgumentError("scenario request is missing: $(join(missing_keys, ", "))"))
        payload["protocol_version"] == 5 ||
            throw(ArgumentError("scenario request must use protocol_version 5"))
        payload["interval_semantics"] == "left_closed_right_open" ||
            throw(ArgumentError("scenario interval semantics must be left_closed_right_open"))
        payload["scenario_count"] isa Integer && payload["scenario_count"] > 0 ||
            throw(ArgumentError("scenario_count must be a positive integer"))
        start_time = parse_rfc3339(_string(payload["start"], "start"))
        end_time = parse_rfc3339(_string(payload["end"], "end"))
        end_time.utc > start_time.utc || throw(ArgumentError("scenario end must follow start"))
        return new(payload)
    end
end

function _json_value(value)
    if value isa NamedTuple || value isa AbstractDict
        return _json_object(value)
    elseif value isa AbstractVector || value isa Tuple
        return [_json_value(item) for item in value]
    elseif value isa Symbol
        return String(value)
    elseif value === missing
        return nothing
    end
    return value
end

function _json_object(value)
    (value isa NamedTuple || value isa AbstractDict) ||
        throw(ArgumentError("expected a dictionary or named tuple"))
    return Dict{String,Any}(String(key) => _json_value(item) for (key, item) in pairs(value))
end

struct Rfc3339Timestamp
    raw::String
    utc::DateTime
    offset_minutes::Int
end

function parse_rfc3339(value::AbstractString)
    raw = String(value)
    matched = match(
        r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})$",
        raw,
    )
    matched === nothing && throw(ArgumentError("timestamp is not RFC3339 with an offset"))
    parts = parse.(Int, matched.captures[1:6])
    fraction = something(matched.captures[7], "")
    truncated = isempty(fraction) ? "" : first(fraction, min(3, length(fraction)))
    milliseconds = isempty(truncated) ? 0 : parse(Int, rpad(truncated, 3, '0'))
    local_time = DateTime(parts..., milliseconds)
    offset_text = matched.captures[8]
    offset_minutes = if offset_text == "Z"
        0
    else
        sign = startswith(offset_text, "-") ? -1 : 1
        sign * (parse(Int, offset_text[2:3]) * 60 + parse(Int, offset_text[5:6]))
    end
    return Rfc3339Timestamp(raw, local_time - Minute(offset_minutes), offset_minutes)
end

function _strict_object(value, required::Tuple, optional::Tuple=())
    value isa AbstractDict || _invalid_response("expected a JSON object")
    object = Dict{String,Any}(String(key) => item for (key, item) in value)
    allowed = Set((required..., optional...))
    missing_keys = [key for key in required if !haskey(object, key)]
    unknown_keys = [key for key in keys(object) if !(key in allowed)]
    isempty(missing_keys) || _invalid_response("missing fields: $(join(missing_keys, ", "))")
    isempty(unknown_keys) || _invalid_response("unknown fields: $(join(sort(unknown_keys), ", "))")
    return object
end

_string(value, field) = value isa AbstractString ? String(value) : _invalid_response("$field must be a string")
_nullable_string(value, field) = isnothing(value) ? nothing : _string(value, field)
_integer(value, field) = value isa Integer ? Int(value) : _invalid_response("$field must be an integer")
_nullable_integer(value, field) = isnothing(value) ? nothing : _integer(value, field)
_boolean(value, field) = value isa Bool ? value : _invalid_response("$field must be a boolean")
_number(value, field) = value isa Real ? Float64(value) : _invalid_response("$field must be a number")

function _object(value, field)
    value isa AbstractDict || _invalid_response("$field must be an object")
    return Dict{String,Any}(String(key) => item for (key, item) in value)
end

function _strings(value, field)
    value isa AbstractVector || _invalid_response("$field must be an array")
    return [_string(item, field) for item in value]
end

function _vector(value, field)
    value isa AbstractVector || _invalid_response("$field must be an array")
    return Any[value...]
end

function _parse_model(::Type{Health}, value)
    o = _strict_object(value, ("product", "version", "healthy", "engine"))
    engine = isnothing(o["engine"]) ? nothing : _object(o["engine"], "engine")
    return Health(_string(o["product"], "product"), _string(o["version"], "version"), _boolean(o["healthy"], "healthy"), engine)
end

function _parse_model(::Type{IdentityContext}, value)
    o = _strict_object(value, ("server_id", "workspace_id", "user_id", "role", "permissions", "capabilities", "limits"))
    return IdentityContext(
        _string(o["server_id"], "server_id"),
        _string(o["workspace_id"], "workspace_id"),
        _string(o["user_id"], "user_id"),
        _string(o["role"], "role"),
        _strings(o["permissions"], "permissions"),
        _strings(o["capabilities"], "capabilities"),
        _object(o["limits"], "limits"),
    )
end


function _parse_model(::Type{ResearchProject}, value)
    o = _strict_object(value, ("id", "workspace_id", "title", "description", "research_goal", "agent_context", "tags", "default_style", "status", "created_at", "updated_at", "deleted_at"))
    return ResearchProject(_string(o["id"], "id"), _string(o["workspace_id"], "workspace_id"), _string(o["title"], "title"), _nullable_string(o["description"], "description"), _nullable_string(o["research_goal"], "research_goal"), _nullable_string(o["agent_context"], "agent_context"), _strings(o["tags"], "tags"), _object(o["default_style"], "default_style"), _string(o["status"], "status"), _string(o["created_at"], "created_at"), _string(o["updated_at"], "updated_at"), _nullable_string(o["deleted_at"], "deleted_at"))
end

function _parse_model(::Type{ProjectResource}, value)
    o = _strict_object(value, ("project_id", "resource_type", "resource_id", "role", "added_by", "note", "created_at"))
    return ProjectResource(_string(o["project_id"], "project_id"), _string(o["resource_type"], "resource_type"), _string(o["resource_id"], "resource_id"), _string(o["role"], "role"), _string(o["added_by"], "added_by"), _nullable_string(o["note"], "note"), _string(o["created_at"], "created_at"))
end

function _parse_model(::Type{Dataset}, value)
    o = _strict_object(value, ("id", "workspace_id", "title", "description", "kind", "tags", "source_summary", "status", "created_at", "updated_at", "deleted_at"))
    return Dataset(_string(o["id"], "id"), _string(o["workspace_id"], "workspace_id"), _string(o["title"], "title"), _nullable_string(o["description"], "description"), _string(o["kind"], "kind"), _strings(o["tags"], "tags"), _nullable_string(o["source_summary"], "source_summary"), _string(o["status"], "status"), _string(o["created_at"], "created_at"), _string(o["updated_at"], "updated_at"), _nullable_string(o["deleted_at"], "deleted_at"))
end

function _parse_model(::Type{DatasetVersion}, value)
    o = _strict_object(value, ("id", "dataset_id", "ordinal", "status", "manifest_hash", "file_count", "size_bytes", "source", "provenance", "schema_version", "created_at", "created_by"))
    return DatasetVersion(_string(o["id"], "id"), _string(o["dataset_id"], "dataset_id"), _integer(o["ordinal"], "ordinal"), _string(o["status"], "status"), _string(o["manifest_hash"], "manifest_hash"), _integer(o["file_count"], "file_count"), _integer(o["size_bytes"], "size_bytes"), _object(o["source"], "source"), _string(o["provenance"], "provenance"), _integer(o["schema_version"], "schema_version"), _string(o["created_at"], "created_at"), _string(o["created_by"], "created_by"))
end

function _parse_model(::Type{MachineView}, value)
    o = _strict_object(value, ("id", "source_version_id", "logical_path", "kind", "generator", "generator_version", "source_manifest_hash", "status", "blob_hash", "inline_json", "created_at", "error"))
    return MachineView(_string(o["id"], "id"), _string(o["source_version_id"], "source_version_id"), _nullable_string(o["logical_path"], "logical_path"), _string(o["kind"], "kind"), _string(o["generator"], "generator"), _string(o["generator_version"], "generator_version"), _string(o["source_manifest_hash"], "source_manifest_hash"), _string(o["status"], "status"), _nullable_string(o["blob_hash"], "blob_hash"), o["inline_json"], _string(o["created_at"], "created_at"), _nullable_string(o["error"], "error"))
end

function _parse_model(::Type{VaultTask}, value)
    o = _strict_object(value, ("id", "workspace_id", "kind", "status", "phase", "completed_units", "total_units", "progress", "message", "request_id", "started_at", "finished_at", "error", "result_resource_id"))
    return VaultTask(_string(o["id"], "id"), _string(o["workspace_id"], "workspace_id"), _string(o["kind"], "kind"), _string(o["status"], "status"), _string(o["phase"], "phase"), _integer(o["completed_units"], "completed_units"), _integer(o["total_units"], "total_units"), _number(o["progress"], "progress"), _string(o["message"], "message"), _string(o["request_id"], "request_id"), _nullable_string(o["started_at"], "started_at"), _nullable_string(o["finished_at"], "finished_at"), o["error"], _nullable_string(o["result_resource_id"], "result_resource_id"))
end

function _parse_model(::Type{Run}, value)
    o = _strict_object(value, ("id", "workspace_id", "task_id", "kind", "status", "retention", "request", "parameters", "seed", "model_versions", "protocol_version", "environment", "git", "started_at", "finished_at", "warnings", "error", "deleted_at"))
    return Run(_string(o["id"], "id"), _string(o["workspace_id"], "workspace_id"), _nullable_string(o["task_id"], "task_id"), _string(o["kind"], "kind"), _string(o["status"], "status"), _string(o["retention"], "retention"), o["request"], o["parameters"], _nullable_integer(o["seed"], "seed"), o["model_versions"], _integer(o["protocol_version"], "protocol_version"), o["environment"], _object(o["git"], "git"), _string(o["started_at"], "started_at"), _nullable_string(o["finished_at"], "finished_at"), _strings(o["warnings"], "warnings"), o["error"], _nullable_string(o["deleted_at"], "deleted_at"))
end

function _parse_model(::Type{Artifact}, value)
    o = _strict_object(value, ("id", "run_id", "name", "role", "blob_hash", "media_type", "size_bytes", "metadata", "created_at"))
    return Artifact(_string(o["id"], "id"), _string(o["run_id"], "run_id"), _string(o["name"], "name"), _string(o["role"], "role"), _string(o["blob_hash"], "blob_hash"), _string(o["media_type"], "media_type"), _integer(o["size_bytes"], "size_bytes"), o["metadata"], _string(o["created_at"], "created_at"))
end

function _parse_model(::Type{Figure}, value)
    o = _strict_object(value, ("id", "primary_project_id", "title", "description", "tags", "kind", "head_revision_id", "published_revision_id", "status", "created_at", "updated_at", "deleted_at"))
    return Figure(_string(o["id"], "id"), _string(o["primary_project_id"], "primary_project_id"), _string(o["title"], "title"), _nullable_string(o["description"], "description"), _strings(o["tags"], "tags"), _string(o["kind"], "kind"), _nullable_string(o["head_revision_id"], "head_revision_id"), _nullable_string(o["published_revision_id"], "published_revision_id"), _string(o["status"], "status"), _string(o["created_at"], "created_at"), _string(o["updated_at"], "updated_at"), _nullable_string(o["deleted_at"], "deleted_at"))
end

function _parse_model(::Type{FigureRevision}, value)
    o = _strict_object(value, ("id", "figure_id", "parent_revision_id", "ordinal", "spec_blob_hash", "normalized_spec_hash", "schema_version", "source", "client_summary", "renderer_requirements", "warnings", "created_at", "created_by"))
    return FigureRevision(_string(o["id"], "id"), _string(o["figure_id"], "figure_id"), _nullable_string(o["parent_revision_id"], "parent_revision_id"), _integer(o["ordinal"], "ordinal"), _string(o["spec_blob_hash"], "spec_blob_hash"), _string(o["normalized_spec_hash"], "normalized_spec_hash"), _integer(o["schema_version"], "schema_version"), _string(o["source"], "source"), _nullable_string(o["client_summary"], "client_summary"), o["renderer_requirements"], _strings(o["warnings"], "warnings"), _string(o["created_at"], "created_at"), _string(o["created_by"], "created_by"))
end

function _parse_model(::Type{FigureRevisionRecord}, value)
    o = _strict_object(value, ("revision", "spec", "inputs"))
    return FigureRevisionRecord(_parse_model(FigureRevision, o["revision"]), o["spec"], _vector(o["inputs"], "inputs"))
end

function _parse_model(::Type{RunRecord}, value)
    o = _strict_object(value, ("run", "inputs", "artifacts"))
    artifacts = [_parse_model(Artifact, item) for item in _vector(o["artifacts"], "artifacts")]
    return RunRecord(_parse_model(Run, o["run"]), _vector(o["inputs"], "inputs"), artifacts)
end

function _parse_model(::Type{FigureRecord}, value)
    o = _strict_object(value, ("figure", "revisions"))
    revisions = [_parse_model(FigureRevision, item) for item in _vector(o["revisions"], "revisions")]
    return FigureRecord(_parse_model(Figure, o["figure"]), revisions)
end
