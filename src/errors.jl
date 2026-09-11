abstract type AbstractVaultException <: Exception end

struct VaultConnectionError <: AbstractVaultException
    message::String
end

struct VaultError <: AbstractVaultException
    status::Int
    code::String
    message::String
    request_id::String
    details::Union{Nothing,Dict{String,Any}}
end

struct VaultIntegrityError <: AbstractVaultException
    message::String
end

struct VaultTaskTimeoutError <: AbstractVaultException
    task_id::String
    timeout::Float64
end

function Base.showerror(io::IO, error::VaultConnectionError)
    print(io, "Research Vault connection failed: ", error.message)
end

function Base.showerror(io::IO, error::VaultError)
    print(io, error.code, ": ", error.message, " (request ", error.request_id, ")")
end

function Base.showerror(io::IO, error::VaultIntegrityError)
    print(io, "Research Vault integrity check failed: ", error.message)
end

function Base.showerror(io::IO, error::VaultTaskTimeoutError)
    print(io, "Research Vault task ", error.task_id, " did not finish within ", error.timeout, " seconds")
end

function _invalid_response(message::AbstractString)
    throw(VaultError(502, "invalid_service_response", String(message), "req_client", nothing))
end
