struct ServiceConnection
    endpoint::String
    token::String
end

const _WINDOWS_CURRENT_SERVICE_NAMES = (
    "research-vault-service.exe",
    "research-vault-service-x86_64-pc-windows-msvc.exe",
)
const _WINDOWS_LEGACY_SERVICE_NAMES = (
    "scenario-service.exe",
    "scenario-service-x86_64-pc-windows-msvc.exe",
)
const _UNIX_CURRENT_SERVICE_NAMES = ("research-vault-service",)
const _UNIX_LEGACY_SERVICE_NAMES = ("scenario-service",)

function _normalized_executable_name(value::AbstractString)
    name = basename(String(value))
    return Sys.iswindows() ? lowercase(name) : name
end

function _is_service_process_name(value::AbstractString)
    name = _normalized_executable_name(value)
    supported = Sys.iswindows() ?
        (_WINDOWS_CURRENT_SERVICE_NAMES..., _WINDOWS_LEGACY_SERVICE_NAMES...) :
        (_UNIX_CURRENT_SERVICE_NAMES..., _UNIX_LEGACY_SERVICE_NAMES...)
    return name in supported
end

function _is_current_service_executable_name(value::AbstractString)
    name = _normalized_executable_name(value)
    supported = Sys.iswindows() ?
        _WINDOWS_CURRENT_SERVICE_NAMES : _UNIX_CURRENT_SERVICE_NAMES
    return name in supported
end

_current_service_executable_names() = Sys.iswindows() ?
    _WINDOWS_CURRENT_SERVICE_NAMES : _UNIX_CURRENT_SERVICE_NAMES

function _validate_loopback_endpoint(value::AbstractString)
    endpoint = String(value)
    matched = match(r"^http://(?:127\.0\.0\.1|localhost):([0-9]{1,5})$", endpoint)
    matched === nothing &&
        throw(ArgumentError("service endpoint must be loopback HTTP with a port"))
    port = parse(Int, matched.captures[1])
    1 <= port <= 65535 || throw(ArgumentError("service endpoint port is invalid"))
    return endpoint
end

function _validate_token(value::AbstractString)
    token = String(value)
    occursin(r"^[0-9a-fA-F]{64}$", token) ||
        throw(ArgumentError("service token is invalid"))
    return token
end

function _default_app_data()
    override = get(ENV, "RESEARCH_VAULT_APP_DATA", "")
    !isempty(override) && return abspath(expanduser(override))
    if Sys.iswindows() && haskey(ENV, "APPDATA")
        current = joinpath(ENV["APPDATA"], "com.haiyangbian.research-vault")
        legacy = joinpath(ENV["APPDATA"], "com.alice.scenarios-generate")
        return _contains_vault_state(current) || !_contains_vault_state(legacy) ? current : legacy
    end
    return abspath(".vault-dev")
end

function _contains_vault_state(root::AbstractString)
    vault = joinpath(root, "research-vault")
    return any(isfile, (
        joinpath(vault, "catalog.sqlite"),
        joinpath(vault, "runtime", "service.json"),
        joinpath(vault, "runtime", "service-task.json"),
    ))
end

_runtime_directory(app_data::AbstractString) =
    joinpath(app_data, "research-vault", "runtime")

function _read_json_file(path::AbstractString)
    try
        return JSON.parse(read(path, String))
    catch
        return nothing
    end
end

function _process_identity(discovery::AbstractDict)
    pid = get(discovery, "pid", nothing)
    pid isa Integer && 0 < pid <= typemax(UInt32) || return :unknown
    if !Sys.iswindows()
        status = ccall(:kill, Cint, (Cint, Cint), pid, 0)
        status != 0 && return Base.Libc.errno() == 3 ? :exited : :unknown
        path = try readlink("/proc/$pid/exe") catch; return :unknown end
        return _is_service_process_name(path) ? :alive : :reused
    end
    handle = ccall((:OpenProcess, "kernel32"), Ptr{Cvoid}, (UInt32, Int32, UInt32), 0x101000, 0, pid)
    if handle == C_NULL
        return ccall((:GetLastError, "kernel32"), UInt32, ()) == 87 ? :exited : :unknown
    end
    try
        ccall((:WaitForSingleObject, "kernel32"), UInt32, (Ptr{Cvoid}, UInt32), handle, 0) == 0 && return :exited
        size = Ref{UInt32}(32768)
        buffer = zeros(UInt16, Int(size[]))
        ok = ccall((:QueryFullProcessImageNameW, "kernel32"), Int32,
            (Ptr{Cvoid}, UInt32, Ptr{UInt16}, Ref{UInt32}), handle, 0, buffer, size)
        ok == 0 && return :unknown
        name = transcode(String, buffer[1:Int(size[])])
        _is_service_process_name(name) || return :reused
        created, exited, kernel, user = Ref{UInt64}(0), Ref{UInt64}(0), Ref{UInt64}(0), Ref{UInt64}(0)
        ok = ccall((:GetProcessTimes, "kernel32"), Int32,
            (Ptr{Cvoid}, Ref{UInt64}, Ref{UInt64}, Ref{UInt64}, Ref{UInt64}), handle, created, exited, kernel, user)
        ok == 0 && return :unknown
        start = Int64(created[] ÷ 10_000_000) - 11644473600
        expected = get(discovery, "process_started_at_unix", nothing)
        expected === nothing || return start == expected ? :alive : :reused
        published = try parse_rfc3339(String(discovery["started_at"])) catch; return :unknown end
        return start <= Dates.datetime2unix(published.utc) ? :alive : :reused
    finally
        ccall((:CloseHandle, "kernel32"), Int32, (Ptr{Cvoid},), handle)
    end
end

function _read_connection(runtime::AbstractString; process_probe=_process_identity)
    discovery = _read_json_file(joinpath(runtime, "service.json"))
    discovery isa AbstractDict || return nothing
    haskey(discovery, "endpoint") || return nothing
    token = try
        strip(read(joinpath(runtime, "service.token"), String))
    catch
        return nothing
    end
    connection = try
        ServiceConnection(
            _validate_loopback_endpoint(discovery["endpoint"]),
            _validate_token(token),
        )
    catch
        return nothing
    end
    identity = process_probe(discovery)
    identity == :exited && return nothing
    identity == :alive || throw(VaultConnectionError("service_process_$identity: cannot establish process identity; no business request submitted"))
    return connection
end

function _read_launcher(runtime::AbstractString)
    launcher = _read_json_file(joinpath(runtime, "service-launcher.json"))
    launcher isa AbstractDict || return nothing
    get(launcher, "schema_version", nothing) == 1 || return nothing
    executable = get(launcher, "executable", nothing)
    executable isa AbstractString || return nothing
    isabspath(executable) && isfile(executable) || return nothing
    return abspath(executable)
end

function _checked_executable(value, source::AbstractString)
    value === nothing && return nothing
    path = abspath(expanduser(String(value)))
    isfile(path) && _is_current_service_executable_name(path) || throw(
        VaultConnectionError(
            "$source does not name an existing research-vault-service executable",
        ),
    )
    return path
end

function _read_task_executable(runtime::AbstractString)
    record = _read_json_file(joinpath(runtime, "service-task.json"))
    record isa AbstractDict || return nothing
    get(record, "schema_version", nothing) in (1, 2) || return nothing
    executable = get(record, "executable", nothing)
    executable isa AbstractString || return nothing
    try
        return _checked_executable(executable, "service task record")
    catch
        return nothing
    end
end


function _resolve_service_executable(runtime::AbstractString, explicit)
    explicit_path = _checked_executable(explicit, "service_executable")
    explicit_path === nothing || return explicit_path

    configured = get(ENV, "RESEARCH_VAULT_SERVICE", "")
    if !isempty(configured)
        return _checked_executable(configured, "RESEARCH_VAULT_SERVICE")
    end

    launcher = _read_launcher(runtime)
    launcher === nothing || return _checked_executable(launcher, "service launcher")

    task_executable = _read_task_executable(runtime)
    task_executable === nothing || return task_executable

    for name in _current_service_executable_names()
        located = Sys.which(name)
        located === nothing || return abspath(located)
    end
    throw(
        VaultConnectionError(
            "research-vault-service was not found; start Research Vault once, set " *
            "RESEARCH_VAULT_SERVICE, or pass service_executable",
        ),
    )
end

function _service_start_command(executable, app_data::AbstractString)
    (Sys.iswindows() && isfile(joinpath(_runtime_directory(app_data), "service-task.json"))) ||
        throw(VaultConnectionError("service_not_registered: repair the current-user login task or start the development service explicitly"))
    executable === nothing && throw(VaultConnectionError(
        "service_task_record_invalid: the registered service executable is unavailable",
    ))
    service = abspath(String(executable))
    isfile(service) && _is_current_service_executable_name(service) ||
        throw(VaultConnectionError(
            "service_task_record_invalid: the registered service executable is unavailable",
        ))
    command = Cmd([service, "service-task", "start", "--app-data", String(app_data)])
    return Cmd(command; windows_hide=true)
end

function _start_service(executable, app_data::AbstractString)
    command = _service_start_command(executable, app_data)
    try
        return Base.run(pipeline(command; stdin=devnull, stdout=devnull, stderr=devnull); wait=false)
    catch
        throw(VaultConnectionError("service_activation_failed: could not request the registered task; no business request submitted"))
    end
end

function _healthy_connection(connection::ServiceConnection; timeout::Real)
    client = VaultClient(connection.endpoint, connection.token; timeout=timeout)
    try
        status = health(client)
        return status.product == "Research Vault" && status.healthy
    catch
        return false
    finally
        close(client)
    end
end

function connect_local(
    ;
    app_data=nothing,
    auto_start::Bool=true,
    startup_timeout::Real=15.0,
    request_timeout::Real=30.0,
    service_executable=nothing,
)
    startup_timeout > 0 || throw(ArgumentError("startup_timeout must be positive"))
    root = app_data === nothing ?
        _default_app_data() : abspath(expanduser(String(app_data)))
    runtime = _runtime_directory(root)
    deadline = time() + Float64(startup_timeout)
    connection = _read_connection(runtime)
    if connection !== nothing &&
       _healthy_connection(connection; timeout=min(2.0, max(0.001, deadline-time())))
        return VaultClient(connection.endpoint, connection.token; timeout=request_timeout)
    end
    auto_start || throw(VaultConnectionError("Research Vault service is not available"))
    resolved_service = connection === nothing ?
        _resolve_service_executable(runtime, service_executable) : nothing
    control = connection === nothing ? _start_service(resolved_service, root) : nothing

    while time() < deadline
        if control !== nothing && process_exited(control) && control.exitcode != 0
            throw(VaultConnectionError("service_activation_failed: repair the current-user login task; no business request submitted"))
        end
        sleep(min(0.1, max(0.0, deadline-time())))
        time() >= deadline && break
        connection = _read_connection(runtime)
        if connection !== nothing &&
           _healthy_connection(connection; timeout=min(2.0, max(0.001, deadline-time())))
            return VaultClient(connection.endpoint, connection.token; timeout=request_timeout)
        end
    end
    throw(
        VaultConnectionError(
            "Research Vault service did not become healthy before the startup timeout",
        ),
    )
end

function connect_local(f::Function; kwargs...)
    client = connect_local(; kwargs...)
    try
        return f(client)
    finally
        close(client)
    end
end

