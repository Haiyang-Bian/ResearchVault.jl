const _TEAM_CONNECTIONS_RELATIVE = joinpath("research-vault-client", "connections.json")
const _TEAM_UPLOAD_CHUNK_BYTES = 8 * 1024 * 1024

function _team_configuration_root(app_data)
    return app_data === nothing ? _default_app_data() : abspath(expanduser(String(app_data)))
end

function _team_connection(
    name::AbstractString;
    app_data=nothing,
    credential_reader=_windows_credential,
)
    Sys.iswindows() && Sys.WORD_SIZE == 64 ||
        throw(VaultConnectionError("windows_x64_team_client_required"))
    root = _team_configuration_root(app_data)
    value = _read_json_file(joinpath(root, _TEAM_CONNECTIONS_RELATIVE))
    value isa AbstractDict || throw(VaultConnectionError("team_connections_missing"))
    get(value, "schema_version", nothing) == 1 ||
        throw(VaultConnectionError("team_connections_invalid"))
    entries = get(value, "connections", nothing)
    entries isa AbstractVector && length(entries) <= 128 ||
        throw(VaultConnectionError("team_connections_invalid"))
    selected = findfirst(entry -> entry isa AbstractDict && get(entry, "name", nothing) == String(name), entries)
    selected === nothing && throw(VaultConnectionError("team_connection_not_found"))
    entry = entries[selected]
    required = ("name", "origin", "ca_certificate_pem", "ca_sha256", "server_id",
                "workspace_id", "user_id", "credential")
    Set(String.(keys(entry))) == Set(required) ||
        throw(VaultConnectionError("team_connection_invalid"))
    origin = String(entry["origin"])
    occursin(r"^https://(?:\[[0-9A-Fa-f:]+\]|[A-Za-z0-9.-]+):[0-9]{1,5}$", origin) ||
        throw(VaultConnectionError("team_https_origin_invalid"))
    ca_pem = String(entry["ca_certificate_pem"])
    ca_sha256 = lowercase(String(entry["ca_sha256"]))
    bytes2hex(sha256(codeunits(ca_pem))) == ca_sha256 ||
        throw(VaultIntegrityError("team CA fingerprint does not match the saved connection"))
    server = _identity_uuid(entry["server_id"])
    workspace = _identity_uuid(entry["workspace_id"], "ws_")
    user = _identity_uuid(entry["user_id"], "actor_")
    credential = entry["credential"]
    credential isa AbstractDict || throw(VaultConnectionError("team_credential_invalid"))
    allowed_token = Set(("token_id", "user_id", "purpose", "scopes", "created_at", "expires_at", "revoked"))
    Set(String.(keys(credential))) == allowed_token ||
        throw(VaultConnectionError("team_credential_invalid"))
    token_id = _identity_uuid(credential["token_id"])
    _identity_uuid(credential["user_id"], "actor_") == user ||
        throw(VaultConnectionError("team_credential_identity_mismatch"))
    credential["purpose"] == "desktop" ||
        throw(VaultConnectionError("team_desktop_credential_required"))
    credential["revoked"] === false || throw(VaultConnectionError("team_credential_revoked"))
    expires = try
        parse_rfc3339(String(credential["expires_at"])).utc
    catch
        throw(VaultConnectionError("team_credential_invalid"))
    end
    expires > Dates.now(Dates.UTC) || throw(VaultConnectionError("team_credential_expired"))
    if expires <= Dates.now(Dates.UTC) + Dates.Day(14)
        @warn "Research Vault team credential expires soon; rotate it in the team-client desktop" expires_at=String(credential["expires_at"])
    end
    target = "ResearchVault/$server/$workspace/$user/desktop/$token_id"
    token = try
        _validate_token(credential_reader(target))
    catch error
        error isa InterruptException && rethrow()
        throw(VaultConnectionError("team_credential_unavailable"))
    end
    return (
        root=root,
        origin=origin,
        ca_pem=ca_pem,
        identity=(server_id=server, workspace_id=workspace, user_id=user),
        token=token,
    )
end

function _team_http_client(ca_pem::String)
    ca_path, ca_io = mktemp()
    try
        write(ca_io, ca_pem)
        flush(ca_io)
    finally
        close(ca_io)
    end
    tls = Reseau.TLS.Config(
        verify_peer=true,
        verify_hostname=true,
        ca_file=ca_path,
        alpn_protocols=["http/1.1"],
    )
    transport = HTTP.Transport(tls_config=tls, proxy=HTTP.ProxyConfig())
    return HTTP.Client(transport=transport), ca_path
end

function _http_request_with_client(owner, method, url, headers, body, timeout)
    response = HTTP.request(
        method,
        url,
        headers,
        body;
        client=owner,
        status_exception=false,
        connect_timeout=timeout,
        request_timeout=timeout,
        retry=false,
        redirect=false,
    )
    return TransportResponse(
        response.status,
        [String(key) => String(value) for (key, value) in response.headers],
        Vector{UInt8}(response.body),
    )
end

function _http_download_with_client(owner, url, headers, destination, timeout)
    response = open(destination, "w") do output
        HTTP.request(
            "GET",
            url,
            headers;
            client=owner,
            response_stream=output,
            status_exception=false,
            connect_timeout=timeout,
            request_timeout=timeout,
            retry=false,
            redirect=false,
        )
    end
    return TransportResponse(
        response.status,
        [String(key) => String(value) for (key, value) in response.headers],
        UInt8[],
    )
end

"""Connect through a named Windows team-client connection without accepting a URL or token."""
function connect_team(name::AbstractString; app_data=nothing, request_timeout::Real=30.0)
    request_timeout > 0 || throw(ArgumentError("request_timeout must be positive"))
    configuration = _team_connection(name; app_data)
    owner, ca_path = try
        _team_http_client(configuration.ca_pem)
    catch error
        error isa InterruptException && rethrow()
        throw(VaultConnectionError("team_tls_configuration_invalid"))
    end
    client = VaultClient(
        configuration.origin,
        configuration.token,
        Float64(request_timeout),
        (method, url, headers, body, timeout) ->
            _http_request_with_client(owner, method, url, headers, body, timeout),
        (url, headers, destination, timeout) ->
            _http_download_with_client(owner, url, headers, destination, timeout),
        false,
        :team,
        owner,
        [ca_path],
    )
    try
        _verify_identity_context(client, configuration.identity)
        return client
    catch
        close(client)
        rethrow()
    end
end

function connect_team(f::Function, name::AbstractString; kwargs...)
    client = connect_team(name; kwargs...)
    try
        return f(client)
    finally
        close(client)
    end
end

function _team_file_hash(path::String)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

function _team_upload_files(source_path)
    source = abspath(expanduser(String(source_path)))
    ispath(source) || throw(ArgumentError("import source does not exist"))
    islink(source) && throw(ArgumentError("team imports reject symbolic links"))
    physical = String[]
    logical = String[]
    if isfile(source)
        push!(physical, source)
        push!(logical, basename(source))
    elseif isdir(source)
        for (root, dirs, names) in walkdir(source; follow_symlinks=false)
            any(name -> islink(joinpath(root, name)), dirs) &&
                throw(ArgumentError("team imports reject symbolic-link directories"))
            for name in sort(names)
                path = joinpath(root, name)
                islink(path) && throw(ArgumentError("team imports reject symbolic-link files"))
                isfile(path) || throw(ArgumentError("team imports accept regular files only"))
                push!(physical, path)
                push!(logical, replace(relpath(path, source), '\\' => '/'))
            end
        end
    else
        throw(ArgumentError("team imports accept a regular file or directory"))
    end
    isempty(physical) && throw(ArgumentError("team import source is empty"))
    length(physical) <= 1024 || throw(ArgumentError("team import contains more than 1024 files"))
    files = NamedTuple[]
    total = 0
    for (path, relative) in zip(physical, logical)
        size = filesize(path)
        total += size
        total <= 2 * 1024^3 || throw(ArgumentError("team import exceeds 2 GiB"))
        push!(files, (
            physical_path=path,
            logical_path=relative,
            size=size,
            sha256=_team_file_hash(path),
            media_type="application/octet-stream",
        ))
    end
    return files
end

function _team_json_response(client::VaultClient, response::TransportResponse)
    parsed = isempty(response.body) ? nothing : try
        JSON.parse(String(response.body))
    catch
        _invalid_response("team service returned invalid JSON")
    end
    if !(200 <= response.status < 300)
        object = _strict_object(parsed, ("code", "message", "request_id"), ("details",))
        details = get(object, "details", nothing)
        throw(VaultError(
            response.status,
            _string(object["code"], "code"),
            _string(object["message"], "message"),
            _string(object["request_id"], "request_id"),
            isnothing(details) ? nothing : _object(details, "details"),
        ))
    end
    return parsed
end

function _team_put_chunk(client::VaultClient, path::String, offset::Int, bytes::Vector{UInt8})
    headers = Pair{String,String}[
        "Accept" => "application/json",
        "Authorization" => "Bearer $(client.token)",
        "Content-Type" => "application/octet-stream",
        "Upload-Offset" => string(offset),
        "X-Chunk-SHA256" => bytes2hex(sha256(bytes)),
    ]
    last_error = nothing
    for attempt in 1:3
        try
            response = client.request_function(
                "PUT", client.endpoint * path, headers, bytes, max(client.timeout, 120.0),
            )
            return _team_json_response(client, response)
        catch error
            error isa InterruptException && rethrow()
            error isa VaultError && rethrow()
            last_error = error
            attempt < 3 && sleep(0.25 * attempt)
        end
    end
    throw(VaultConnectionError("team upload chunk outcome unknown; the resumable session was preserved ($(typeof(last_error)))"))
end

function _team_upload(client::VaultClient, files)
    context = identity_context(client)
    "resumable_upload" in context.capabilities ||
        throw(VaultConnectionError("team capability unavailable: resumable_upload"))
    descriptors = [Dict(
        "logical_path" => file.logical_path,
        "size" => file.size,
        "sha256" => file.sha256,
        "media_type" => file.media_type,
    ) for file in files]
    base = "/team/v1/workspaces/$(_segment(context.workspace_id))/uploads"
    upload = _request_json(client, "POST", base; body=Dict("files" => descriptors))
    upload_id = _string(_object(upload, "upload")["upload_id"], "upload_id")
    try
        for (index, file) in enumerate(files)
            route = "$base/$(_segment(upload_id))/files/$(index - 1)"
            if file.size == 0
                _team_put_chunk(client, route, 0, UInt8[])
                continue
            end
            open(file.physical_path, "r") do io
                offset = 0
                while !eof(io)
                    chunk = read(io, _TEAM_UPLOAD_CHUNK_BYTES)
                    _team_put_chunk(client, route, offset, chunk)
                    offset += length(chunk)
                end
            end
        end
        _request_json(client, "POST", "$base/$(_segment(upload_id))/verify")
        return upload_id, context
    catch error
        # Preserve server state for transient transport failures. Definite service
        # rejection is safe to abort because no immutable DatasetVersion exists.
        if error isa VaultError || error isa ArgumentError || error isa VaultIntegrityError
            try
                _request_json(client, "DELETE", "$base/$(_segment(upload_id))")
            catch
            end
        end
        rethrow()
    end
end

function _team_import(
    client::VaultClient,
    source_path;
    target_dataset_id=nothing,
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
    files = _team_upload_files(source_path)
    upload_id, context = _team_upload(client, files)
    metadata = _json_object(scientific_metadata)
    if format_contract !== nothing
        haskey(metadata, "tabular_contract") && throw(ArgumentError("supply the format contract once"))
        metadata["tabular_contract"] = _json_object(format_contract)
    end
    payload = Dict{String,Any}(
        "upload_id" => upload_id,
        "target_dataset_id" => target_dataset_id === nothing ? nothing : String(target_dataset_id),
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
    encoded = JSON.json(payload)
    idempotency = "julia-" * bytes2hex(sha256(codeunits(upload_id * encoded)))
    route = "/team/v1/workspaces/$(_segment(context.workspace_id))/dataset-imports"
    headers = Pair{String,String}[
        "Accept" => "application/json",
        "Authorization" => "Bearer $(client.token)",
        "Content-Type" => "application/json",
        "Idempotency-Key" => idempotency,
    ]
    last_error = nothing
    for attempt in 1:2
        try
            response = client.request_function(
                "POST", client.endpoint * route, headers,
                Vector{UInt8}(codeunits(encoded)), max(client.timeout, 300.0),
            )
            return _task_response(_team_json_response(client, response))
        catch error
            error isa InterruptException && rethrow()
            error isa VaultError && rethrow()
            last_error = error
            attempt < 2 && sleep(0.5)
        end
    end
    throw(VaultConnectionError("team dataset import outcome unknown; retry is idempotent ($(typeof(last_error)))"))
end

function _header(response::TransportResponse, name::String)
    expected = lowercase(name)
    pair = findfirst(item -> lowercase(item.first) == expected, response.headers)
    return pair === nothing ? nothing : response.headers[pair].second
end

"""Download one immutable DatasetVersion file through the team transfer contract."""
function download_dataset_file(client::VaultClient, version_id, logical_path, destination)
    client.mode == :team || throw(ArgumentError("download_dataset_file requires a team connection"))
    context = identity_context(client)
    "version_download" in context.capabilities ||
        throw(VaultConnectionError("team capability unavailable: version_download"))
    manifest = _object(dataset_manifest(client, version_id), "dataset manifest")
    files = _vector(manifest["files"], "files")
    matching = filter(file -> file isa AbstractDict && get(file, "logical_path", nothing) == String(logical_path), files)
    length(matching) == 1 || throw(ArgumentError("logical path is not present exactly once in the immutable manifest"))
    expected_hash = _string(matching[1]["blob_hash"], "blob_hash")
    expected_size = _integer(matching[1]["size_bytes"], "size_bytes")
    target = abspath(expanduser(String(destination)))
    mkpath(dirname(target))
    partial = target * ".research-vault-part"
    offset = isfile(partial) ? filesize(partial) : 0
    0 <= offset < expected_size || (rm(partial; force=true); offset = 0)
    route = _query_path(
        "/team/v1/workspaces/$(_segment(context.workspace_id))/dataset-versions/$(_segment(version_id))/content",
        ["logical_path" => String(logical_path)],
    )
    headers = Pair{String,String}["Authorization" => "Bearer $(client.token)"]
    if offset > 0
        push!(headers, "Range" => "bytes=$offset-")
        push!(headers, "If-Match" => "\"$expected_hash\"")
    end
    response = open(partial, offset > 0 ? "a" : "w") do output
        HTTP.request(
            "GET", client.endpoint * route, headers;
            client=client.transport_owner,
            response_stream=output,
            status_exception=false,
            connect_timeout=client.timeout,
            request_timeout=max(client.timeout, 300.0),
            retry=false,
            redirect=false,
        )
    end
    response.status == (offset > 0 ? 206 : 200) ||
        throw(VaultConnectionError("team download returned status $(response.status); partial file was preserved"))
    actual_header = HTTP.header(response, "X-Content-SHA256", "")
    actual_header == expected_hash || throw(VaultIntegrityError("team download hash header mismatch"))
    filesize(partial) == expected_size || throw(VaultIntegrityError("team download size mismatch"))
    _team_file_hash(partial) == expected_hash || throw(VaultIntegrityError("team download content hash mismatch"))
    mv(partial, target; force=true)
    return target
end
