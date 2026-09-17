using UUIDs

function member_fixture()
    token = Dict{String,Any}("token_id" => string(uuid4()), "user_id" => "actor_$(uuid4())",
        "purpose" => "desktop", "revoked" => false, "expires_at" => "2099-01-01T00:00:00Z")
    return Dict{String,Any}("schema_version" => 1, "server_id" => string(uuid4()),
        "workspace_id" => "ws_$(uuid4())", "active_desktop" => token["token_id"],
        "credentials" => [Dict("token" => token)])
end

@testset "member identity discovery fails closed" begin
    mktempdir() do root
        profile = member_fixture()
        file = joinpath(root, "identity.json")
        save() = write(file, JSON.json(profile))
        save()
        write(joinpath(root, "service.json"), JSON.json(Dict("endpoint" => "http://127.0.0.1:43123")))
        write(joinpath(root, "service.token"), "b"^64) # Must never rescue a broken member profile.
        calls = String[]
        reader = target -> (push!(calls, target); "a"^64)
        connection = ResearchVault._read_connection(root; process_probe=(_)->:alive, credential_reader=reader)
        @test connection.token == "a"^64
        token = profile["credentials"][1]["token"]
        expected = "ResearchVault/$(profile["server_id"])/$(profile["workspace_id"])/$(token["user_id"])/desktop/$(token["token_id"])"
        @test only(calls) == expected
        @test connection.identity.user_id == token["user_id"]
        @test !occursin("a"^64, sprint(show, connection))
        @test_throws VaultConnectionError ResearchVault._read_connection(root; process_probe=(_)->:alive,
            credential_reader=(_)->error("secret should not escape"))
        @test_throws VaultConnectionError ResearchVault._member_credential(root; credential_reader=reader, credential_id=string(uuid4()))
        token["purpose"] = "mcp"; save()
        @test_throws VaultConnectionError ResearchVault._member_credential(root; credential_reader=reader)
        token["purpose"] = "desktop"; token["revoked"] = true; save()
        @test_throws VaultConnectionError ResearchVault._member_credential(root; credential_reader=reader)
        token["revoked"] = false; token["expires_at"] = "2000-01-01T00:00:00Z"; save()
        @test_throws VaultConnectionError ResearchVault._member_credential(root; credential_reader=reader)
        token["expires_at"] = "2099-01-01T00:00:00Z"
        push!(profile["credentials"], Dict("token" => deepcopy(token))); save()
        @test_throws VaultConnectionError ResearchVault._member_credential(root; credential_reader=reader)
        pop!(profile["credentials"]); profile["workspace_id"] = "../another-vault"; save()
        @test_throws VaultConnectionError ResearchVault._member_credential(root; credential_reader=reader)
        write(file, "invalid JSON")
        @test_throws VaultConnectionError ResearchVault._read_connection(root; process_probe=(_)->:alive, credential_reader=reader)
        @test length(calls) == 1
    end
    mktempdir() do root
        mkdir(joinpath(root, "identity.json"))
        @test_throws VaultConnectionError ResearchVault._member_credential(
            root;
            credential_reader=(_)->"a"^64,
        )
    end
end

@testset "member context and display" begin
    expected = (server_id=string(uuid4()), workspace_id="ws_$(uuid4())", user_id="actor_$(uuid4())")
    context = Dict{String,Any}(String(key) => value for (key, value) in pairs(expected))
    merge!(context, Dict(
        "role" => "administrator",
        "permissions" => ["read", "edit"],
        "capabilities" => String[],
        "limits" => Dict("token_lifetime_days" => 90),
    ))
    fake = function (method, url, headers, body, timeout)
        @test method == "GET" && endswith(url, "/team/v1/context")
        return ResearchVault.TransportResponse(200, Pair{String,String}[], Vector{UInt8}(codeunits(JSON.json(context))))
    end
    client = VaultClient("http://127.0.0.1:43123", "a"^64; request_function=fake)
    @test !occursin("a"^64, sprint(show, client))
    @test !occursin("a"^64, sprint(show, MIME("text/plain"), client))
    actual = identity_context(client)
    @test actual isa IdentityContext
    @test actual.role == "administrator"
    @test actual.permissions == ["read", "edit"]
    @test ResearchVault._verify_identity_context(client, expected) === nothing
    for key in ("server_id", "workspace_id", "user_id")
        saved = context[key]; context[key] = "wrong"
        @test_throws VaultConnectionError ResearchVault._verify_identity_context(client, expected)
        context[key] = saved
    end
    context["unexpected"] = true
    @test_throws VaultError identity_context(client)
    delete!(context, "unexpected")
    close(client)
end

@testset "owned native Windows credential" begin
    if Sys.iswindows() && Sys.WORD_SIZE == 64
        @test sizeof(ResearchVault._WindowsCredential) == 80
        target = "ResearchVault/sdk-test/$(uuid4())"
        wide = transcode(UInt16, target * '\0')
        bytes = Vector{UInt8}(codeunits("c"^64))
        native = ResearchVault._WindowsCredential(0, 1, pointer(wide), C_NULL, 0,
            length(bytes), pointer(bytes), 1, 0, C_NULL, C_NULL, C_NULL)
        written = GC.@preserve wide bytes ccall((:CredWriteW, "advapi32"), Int32,
            (Ref{ResearchVault._WindowsCredential}, UInt32), native, 0)
        @test written != 0
        if written != 0
            try
                @test ResearchVault._windows_credential(target) == "c"^64
                @test_throws VaultConnectionError ResearchVault._windows_credential(target * "/other")
            finally
                deleted = GC.@preserve wide ccall((:CredDeleteW, "advapi32"), Int32,
                    (Ptr{UInt16}, UInt32, UInt32), wide, 1, 0)
                @test deleted != 0
            end
            @test_throws VaultConnectionError ResearchVault._windows_credential(target)
        end
    else
        @test_throws VaultConnectionError ResearchVault._windows_credential("unused-test-target")
    end
end
