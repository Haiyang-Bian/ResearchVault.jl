const _ConnectionIdentity = NamedTuple{(:server_id, :workspace_id, :user_id),Tuple{String,String,String}}

_credential_error(code="identity_configuration_invalid") = VaultConnectionError(code)

function _identity_uuid(value, prefix="")
    value isa AbstractString || throw(_credential_error())
    text = String(value)
    startswith(text, prefix) || throw(_credential_error())
    tail = chop(text; head=length(prefix), tail=0)
    parsed = try UUID(tail) catch; throw(_credential_error()) end
    string(parsed) == tail || throw(_credential_error())
    return text
end

function _member_credential(runtime; credential_id=nothing, credential_reader=_windows_credential)
    path = joinpath(runtime, "identity.json")
    ispath(path) || return nothing
    profile = try JSON.parse(read(path, String)) catch; throw(_credential_error()) end
    profile isa AbstractDict || throw(_credential_error())
    get(profile, "schema_version", nothing) === 1 || throw(_credential_error())
    server = _identity_uuid(get(profile, "server_id", nothing))
    workspace = _identity_uuid(get(profile, "workspace_id", nothing), "ws_")
    credentials = get(profile, "credentials", nothing)
    credentials isa AbstractVector && length(credentials) <= 1024 || throw(_credential_error())
    selected = _identity_uuid(credential_id === nothing ? get(profile, "active_desktop", nothing) : credential_id)
    found = nothing
    seen = Set{String}()
    for entry in credentials
        entry isa AbstractDict || throw(_credential_error())
        token = get(entry, "token", nothing)
        token isa AbstractDict || throw(_credential_error())
        id = _identity_uuid(get(token, "token_id", nothing))
        id in seen && throw(_credential_error())
        push!(seen, id)
        id == selected && (found = token)
    end
    found === nothing && throw(_credential_error("identity_credential_missing"))
    get(found, "purpose", nothing) == "desktop" || throw(_credential_error("identity_credential_purpose_invalid"))
    get(found, "revoked", nothing) === false || throw(_credential_error("identity_credential_revoked"))
    user = _identity_uuid(get(found, "user_id", nothing), "actor_")
    expires = try parse_rfc3339(String(found["expires_at"])).utc catch; throw(_credential_error()) end
    expires > Dates.now(Dates.UTC) || throw(_credential_error("identity_credential_expired"))
    target = "ResearchVault/$server/$workspace/$user/desktop/$selected"
    secret = try
        _validate_token(credential_reader(target))
    catch error
        error isa InterruptException && rethrow()
        throw(_credential_error("identity_credential_unavailable"))
    end
    return (token=secret, identity=(server_id=server, workspace_id=workspace, user_id=user))
end

# Win64 CREDENTIALW layout. Pointers returned by CredReadW belong to Windows and
# are freed exactly once after the 64-byte UTF-8 blob has been validated/copied.
struct _WindowsCredential
    flags::UInt32
    type::UInt32
    target::Ptr{UInt16}
    comment::Ptr{UInt16}
    last_written::UInt64
    blob_size::UInt32
    blob::Ptr{UInt8}
    persist::UInt32
    attribute_count::UInt32
    attributes::Ptr{Cvoid}
    target_alias::Ptr{UInt16}
    username::Ptr{UInt16}
end

function _windows_credential(target::String)
    Sys.iswindows() && Sys.WORD_SIZE == 64 || throw(_credential_error("windows_x64_credential_manager_required"))
    wide = transcode(UInt16, target * '\0')
    result = Ref{Ptr{_WindowsCredential}}(C_NULL)
    ok = GC.@preserve wide ccall((:CredReadW, "advapi32"), Int32,
        (Ptr{UInt16}, UInt32, UInt32, Ref{Ptr{_WindowsCredential}}), wide, 1, 0, result)
    ok != 0 && result[] != C_NULL || throw(_credential_error("identity_credential_missing"))
    try
        credential = unsafe_load(result[])
        credential.type == 1 && credential.blob_size == 64 && credential.blob != C_NULL ||
            throw(_credential_error("identity_credential_invalid"))
        bytes = unsafe_wrap(Vector{UInt8}, credential.blob, 64; own=false)
        all(b -> b in UInt8('0'):UInt8('9') || b in UInt8('a'):UInt8('f') || b in UInt8('A'):UInt8('F'), bytes) ||
            throw(_credential_error("identity_credential_invalid"))
        return String(copy(bytes))
    finally
        ccall((:CredFree, "advapi32"), Cvoid, (Ptr{Cvoid},), result[])
    end
end

"""Return the member-mode server identity and effective permissions without credentials."""
identity_context(client::VaultClient) = _parse_model(
    IdentityContext,
    _request_json(client, "GET", "/team/v1/context"),
)

function _verify_identity_context(client::VaultClient, expected::_ConnectionIdentity)
    context = identity_context(client)
    context.server_id == expected.server_id &&
        context.workspace_id == expected.workspace_id &&
        context.user_id == expected.user_id ||
        throw(_credential_error("identity_context_mismatch"))
    return nothing
end
