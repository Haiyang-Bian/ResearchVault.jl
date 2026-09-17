# Explicit Windows integration probe: creates its own Vaults and never accepts an app-data path.
using ResearchVault, JSON, Test, Dates

function wait_client(root, process)
    deadline = time() + 40
    while time() < deadline
        process_exited(process) && error("Owned service exited; inspect retained probe logs")
        try
            return connect_local(app_data=root, auto_start=false, request_timeout=180)
        catch error
            error isa ResearchVault.AbstractVaultException || rethrow()
            sleep(0.1)
        end
    end
    error("Owned service readiness timed out")
end

function stop_owned(client, process)
    ResearchVault._request_json(client, "POST", "/api/v1/admin/runtime/stop"; body=Dict("drain" => true))
    deadline = time() + 40
    while !process_exited(process) && time() < deadline
        sleep(0.1)
    end
    process_exited(process) || error("Owned service still draining; retained without force termination")
    close(client)
end

function start_owned(executable, root, label)
    command = Cmd(Cmd([executable, "--app-data", root, "--ephemeral-port"]); windows_hide=true)
    return Base.run(pipeline(command; stdin=devnull,
        stdout=joinpath(root, "$label.stdout.log"), stderr=joinpath(root, "$label.stderr.log")); wait=false)
end

function forget_owned_credentials(profile)
    for entry in profile["credentials"]
        token = entry["token"]
        target = "ResearchVault/$(profile["server_id"])/$(profile["workspace_id"])/$(token["user_id"])/$(token["purpose"])/$(token["token_id"])"
        wide = transcode(UInt16, target * '\0')
        removed = GC.@preserve wide ccall((:CredDeleteW, "advapi32"), Int32,
            (Ptr{UInt16}, UInt32, UInt32), wide, 1, 0)
        removed != 0 || error("Could not remove this probe's native credential")
    end
end

function workflow(root, full)
    withenv("RESEARCH_VAULT_INTEGRATION_ROOT" => root,
            "RESEARCH_VAULT_FULL_INTEGRATION" => string(full)) do
        Base.include(Module(gensym(:SDKIntegration)), joinpath(@__DIR__, "integration.jl"))
    end
end

function permissions_probe(admin)
    request(method, path; body=nothing) = ResearchVault._request_json(admin, method, path; body)
    @test identity_context(admin).role == "administrator"
    for role in ("reader", "editor")
        member = request("POST", "/team/v1/members"; body=Dict("display_name" => "SDK $role fixture", "role" => role))
        scopes = role == "reader" ? ["read"] : ["read", "edit"]
        issued = request("POST", "/team/v1/tokens"; body=Dict("user_id" => member["user_id"], "purpose" => "desktop", "scopes" => scopes))
        client = VaultClient(admin.endpoint, issued["secret"])
        try
            @test identity_context(client).role == role
            @test projects(client) isa Vector
            if role == "reader"
                before = length(projects(admin))
                @test_throws VaultError create_project(client; title="must not exist")
                @test length(projects(admin)) == before
            else
                @test create_project(client; title="editor SDK fixture").title == "editor SDK fixture"
            end
            @test_throws VaultError ResearchVault._request_json(client, "GET", "/team/v1/members")
            request("DELETE", "/team/v1/tokens/$(issued["credential"]["token_id"])")
            @test_throws VaultError projects(client)
        finally
            close(client)
        end
    end
    member = request("POST", "/team/v1/members"; body=Dict("display_name" => "SDK narrowed editor fixture", "role" => "editor"))
    issued = request("POST", "/team/v1/tokens"; body=Dict("user_id" => member["user_id"], "purpose" => "desktop", "scopes" => ["read"]))
    client = VaultClient(admin.endpoint, issued["secret"])
    try
        @test identity_context(client).permissions == ["read"]
        @test_throws VaultError create_project(client; title="narrowed token must not write")
    finally
        close(client)
        request("DELETE", "/team/v1/tokens/$(issued["credential"]["token_id"])")
    end
end

function main()
    Sys.iswindows() && Sys.WORD_SIZE == 64 || error("Windows x64 probe required")
    length(ARGS) == 1 || error("Pass one complete installation directory; no app-data argument is accepted")
    executable = abspath(joinpath(only(ARGS), "research-vault-service.exe"))
    isfile(executable) || error("Service executable is missing")
    root = mktempdir(; prefix="vault-julia-release-", cleanup=false)
    println("SDK integration evidence: ", root)
    full = lowercase(get(ENV, "RESEARCH_VAULT_FULL_INTEGRATION", "false")) == "true"
    for member in (false, true)
        data = joinpath(root, member ? "member" : "legacy")
        mkpath(data)
        process = start_owned(executable, data, "legacy-bootstrap")
        client = nothing
        profile = nothing
        try
            client = wait_client(data, process)
            if member
                stop_owned(client, process)
                client = nothing
                command = Cmd(Cmd([executable, "identity", "initialize", "--app-data", data]); windows_hide=true)
                Base.run(pipeline(command; stdout=joinpath(data, "initialize.log"), stderr=joinpath(data, "initialize-error.log")))
                profile = JSON.parse(read(joinpath(data, "research-vault", "runtime", "identity.json"), String))
                process = start_owned(executable, data, "member")
                client = wait_client(data, process)
                @testset "real member permissions" permissions_probe(client)
            end
            workflow(data, full)
        finally
            if client !== nothing && !process_exited(process)
                stop_owned(client, process)
            end
            # No wildcard enumeration/deletion: only identities created for this new Vault.
            if profile !== nothing && process_exited(process)
                forget_owned_credentials(profile)
            end
        end
    end
    write(joinpath(root, "passed.json"), JSON.json(Dict("passed" => true, "client_version" => string(CLIENT_VERSION),
        "member_mode" => true, "legacy_mode" => true, "full_workflow" => full,
        "real_user_vault_used" => false, "time_utc" => string(Dates.now(Dates.UTC)))))
    println("SDK legacy/member integration passed; no real user Vault was accessed.")
end

main()
