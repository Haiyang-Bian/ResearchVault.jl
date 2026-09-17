@testset "named team connection is strict and contains no credential" begin
    mktempdir() do root
        ca = "-----BEGIN CERTIFICATE-----\ntest-only\n-----END CERTIFICATE-----\n"
        server = "11111111-1111-1111-1111-111111111111"
        workspace = "ws_22222222-2222-2222-2222-222222222222"
        user = "actor_33333333-3333-3333-3333-333333333333"
        token_id = "44444444-4444-4444-4444-444444444444"
        expires = ResearchVault.Dates.format(
            ResearchVault.Dates.now(ResearchVault.Dates.UTC) + ResearchVault.Dates.Day(30),
            dateformat"yyyy-mm-ddTHH:MM:SS.sssZ",
        )
        profile = Dict(
            "schema_version" => 1,
            "active" => "lab",
            "connections" => [Dict(
                "name" => "lab",
                "origin" => "https://10.180.16.127:54443",
                "ca_certificate_pem" => ca,
                "ca_sha256" => bytes2hex(ResearchVault.sha256(codeunits(ca))),
                "server_id" => server,
                "workspace_id" => workspace,
                "user_id" => user,
                "credential" => Dict(
                    "token_id" => token_id,
                    "user_id" => user,
                    "purpose" => "desktop",
                    "scopes" => ["read"],
                    "created_at" => "2026-01-01T00:00:00Z",
                    "expires_at" => expires,
                    "revoked" => false,
                ),
            )],
        )
        directory = joinpath(root, "research-vault-client")
        mkpath(directory)
        write(joinpath(directory, "connections.json"), JSON.json(profile))
        targets = String[]
        selected = ResearchVault._team_connection(
            "lab";
            app_data=root,
            credential_reader=target -> (push!(targets, target); "a"^64),
            require_windows=false,
        )
        @test selected.origin == "https://10.180.16.127:54443"
        @test selected.identity.user_id == user
        @test selected.token == "a"^64
        @test targets == ["ResearchVault/$server/$workspace/$user/desktop/$token_id"]
        @test !occursin("a"^64, read(joinpath(directory, "connections.json"), String))

        profile["connections"][1]["ca_sha256"] = "0"^64
        write(joinpath(directory, "connections.json"), JSON.json(profile))
        @test_throws VaultIntegrityError ResearchVault._team_connection(
            "lab";
            app_data=root,
            credential_reader=target -> "a"^64,
            require_windows=false,
        )
        if !Sys.iswindows()
            error = try
                connect_team("lab"; app_data=root)
                nothing
            catch caught
                caught
            end
            @test error isa VaultConnectionError
            @test occursin("windows_x64_team_client_required", sprint(showerror, error))
        end
    end
end

@testset "team import streams bytes and never sends a local path" begin
    mktempdir() do root
        source = joinpath(root, "private-name.csv")
        write(source, "x,y\n1,2\n")
        requests = NamedTuple[]
        context = Dict(
            "server_id" => "11111111-1111-1111-1111-111111111111",
            "workspace_id" => "ws_22222222-2222-2222-2222-222222222222",
            "user_id" => "actor_33333333-3333-3333-3333-333333333333",
            "role" => "editor",
            "permissions" => ["read", "edit"],
            "capabilities" => ["resumable_upload", "version_download", "dataset_import"],
            "limits" => Dict{String,Any}(),
        )
        task = JSON.parse(read(joinpath(@__DIR__, "fixtures", "v1", "task.json"), String))
        fake = function (method, url, headers, body, timeout)
            push!(requests, (; method, url, headers, body=copy(body), timeout))
            value = if endswith(url, "/team/v1/context")
                context
            elseif method == "POST" && endswith(url, "/uploads")
                Dict("upload_id" => "55555555-5555-5555-5555-555555555555")
            elseif method == "POST" && endswith(url, "/dataset-imports")
                Dict("task" => task)
            else
                Dict{String,Any}()
            end
            return ResearchVault.TransportResponse(200, Pair{String,String}[], Vector{UInt8}(codeunits(JSON.json(value))))
        end
        client = VaultClient(
            "https://10.180.16.127:54443",
            "a"^64,
            30.0,
            fake,
            (args...) -> error("not used"),
            false,
            :team,
            nothing,
            String[],
        )
        imported = import_dataset(client, source; title="remote test")
        @test imported.id == task["id"]
        @test any(request -> request.method == "PUT", requests)
        submitted = only(filter(request -> request.method == "POST" && endswith(request.url, "/dataset-imports"), requests))
        payload = JSON.parse(String(submitted.body))
        @test !haskey(payload, "source_path")
        @test payload["upload_id"] == "55555555-5555-5555-5555-555555555555"
        @test !occursin(root, String(submitted.body))
        close(client)
    end
end
