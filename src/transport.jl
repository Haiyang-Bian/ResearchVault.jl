struct TransportResponse
    status::Int
    headers::Vector{Pair{String,String}}
    body::Vector{UInt8}
end

mutable struct VaultClient
    endpoint::String
    token::String
    timeout::Float64
    request_function::Function
    download_function::Function
    closed::Bool

    function VaultClient(
        endpoint::AbstractString,
        token::AbstractString;
        timeout::Real=30.0,
        request_function::Function=_http_request,
        download_function::Function=_http_download,
    )
        normalized_endpoint = _validate_loopback_endpoint(endpoint)
        normalized_token = _validate_token(token)
        timeout > 0 || throw(ArgumentError("timeout must be positive"))
        return new(
            normalized_endpoint,
            normalized_token,
            Float64(timeout),
            request_function,
            download_function,
            false,
        )
    end
end

function _http_download(url, headers, destination, timeout)
    response = open(destination, "w") do output
        HTTP.request(
            "GET",
            url,
            headers;
            response_stream=output,
            status_exception=false,
            connect_timeout=timeout,
            request_timeout=timeout,
            retry=false,
            redirect=false,
            proxy=nothing,
        )
    end
    response_headers = [String(key) => String(value) for (key, value) in response.headers]
    return TransportResponse(response.status, response_headers, UInt8[])
end

function Base.close(client::VaultClient)
    client.closed = true
    return nothing
end

Base.isopen(client::VaultClient) = !client.closed

function _http_request(method, url, headers, body, timeout)
    response = HTTP.request(
        method,
        url,
        headers,
        body;
        status_exception=false,
        connect_timeout=timeout,
        request_timeout=timeout,
        retry=false,
        redirect=false,
        proxy=nothing,
    )
    response_headers = [String(key) => String(value) for (key, value) in response.headers]
    return TransportResponse(response.status, response_headers, Vector{UInt8}(response.body))
end

function _request_json(
    client::VaultClient,
    method::AbstractString,
    path::AbstractString;
    body=nothing,
    authenticated::Bool=true,
)
    isopen(client) || throw(VaultConnectionError("client is closed"))
    startswith(path, "/") || throw(ArgumentError("service path must be absolute"))
    occursin("..", path) && throw(ArgumentError("service path cannot contain parent segments"))
    headers = Pair{String,String}["Accept" => "application/json"]
    authenticated && push!(headers, "Authorization" => "Bearer $(client.token)")
    payload = body === nothing ? UInt8[] : Vector{UInt8}(codeunits(JSON.json(body)))
    body === nothing || push!(headers, "Content-Type" => "application/json")
    response = try
        client.request_function(
            String(method),
            client.endpoint * String(path),
            headers,
            payload,
            client.timeout,
        )
    catch error
        error isa InterruptException && rethrow()
        error isa AbstractVaultException && rethrow()
        throw(VaultConnectionError("local service request failed: $(typeof(error))"))
    end
    response isa TransportResponse || _invalid_response("transport returned an invalid response")
    parsed = if isempty(response.body)
        nothing
    else
        try
            JSON.parse(String(response.body))
        catch
            _invalid_response("service returned invalid JSON")
        end
    end
    if !(200 <= response.status < 300)
        object = _strict_object(parsed, ("code", "message", "request_id"), ("details",))
        details = get(object, "details", nothing)
        normalized_details = isnothing(details) ? nothing : _object(details, "details")
        throw(
            VaultError(
                response.status,
                _string(object["code"], "code"),
                _string(object["message"], "message"),
                _string(object["request_id"], "request_id"),
                normalized_details,
            ),
        )
    end
    return parsed
end

function health(client::VaultClient)
    return _parse_model(
        Health,
        _request_json(client, "GET", "/health"; authenticated=false),
    )
end
