function _header(headers, name::AbstractString)
    for (key, value) in headers
        lowercase(key) == lowercase(name) && return value
    end
    return nothing
end

function _throw_download_problem(status::Int, path::AbstractString)
    parsed = try
        JSON.parse(read(path, String))
    catch
        throw(
            VaultError(
                status,
                "invalid_service_response",
                "artifact endpoint returned an invalid error response",
                "req_client",
                nothing,
            ),
        )
    end
    object = _strict_object(parsed, ("code", "message", "request_id"), ("details",))
    details = get(object, "details", nothing)
    normalized_details = isnothing(details) ? nothing : _object(details, "details")
    throw(
        VaultError(
            status,
            _string(object["code"], "code"),
            _string(object["message"], "message"),
            _string(object["request_id"], "request_id"),
            normalized_details,
        ),
    )
end

function download_artifact(
    client::VaultClient,
    artifact_id,
    destination;
    overwrite::Bool=false,
)
    isopen(client) || throw(VaultConnectionError("client is closed"))
    record = artifact(client, artifact_id)
    requested = abspath(expanduser(String(destination)))
    target = isdir(requested) ? joinpath(requested, record.name) : requested
    ispath(target) && !overwrite && throw(ArgumentError("artifact destination already exists"))
    mkpath(dirname(target))
    temporary = tempname(dirname(target); cleanup=false)
    headers = Pair{String,String}["Authorization" => "Bearer $(client.token)"]
    response = try
        client.download_function(
            client.endpoint * "/api/v1/artifacts/$(_segment(artifact_id))/content",
            headers,
            temporary,
            client.timeout,
        )
    catch error
        isfile(temporary) && rm(temporary; force=true)
        error isa InterruptException && rethrow()
        error isa AbstractVaultException && rethrow()
        throw(VaultConnectionError("artifact download failed: $(typeof(error))"))
    end
    try
        response isa TransportResponse || _invalid_response("download transport returned an invalid response")
        200 <= response.status < 300 || _throw_download_problem(response.status, temporary)
        actual_size = filesize(temporary)
        actual_size == record.size_bytes || throw(
            VaultIntegrityError(
                "downloaded size $actual_size does not match Catalog size $(record.size_bytes)",
            ),
        )
        content_length = _header(response.headers, "content-length")
        if content_length !== nothing
            parsed_length = tryparse(Int, content_length)
            parsed_length == actual_size || throw(
                VaultIntegrityError("Content-Length does not match downloaded bytes"),
            )
        end
        actual_hash = open(sha256, temporary) |> bytes2hex
        lowercase(actual_hash) == lowercase(record.blob_hash) || throw(
            VaultIntegrityError("downloaded SHA-256 does not match the immutable Artifact"),
        )
        mv(temporary, target; force=overwrite)
        return target
    finally
        isfile(temporary) && rm(temporary; force=true)
    end
end

