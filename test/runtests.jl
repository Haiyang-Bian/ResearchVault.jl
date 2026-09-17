using ResearchVault
using Test
using JSON
using Dates
using DataFrames

@testset "ResearchVault package scaffold" begin
    @test ResearchVault.CLIENT_VERSION == v"0.6.0"
    @test ResearchVault.SERVICE_API_VERSION == 1
end

const FIXTURE_ROOT = joinpath(@__DIR__, "fixtures", "v1")
include("member_auth.jl")

@testset "font and interactive preview discovery" begin
    calls = []
    fake = function (method, url, headers, body, timeout)
        push!(calls, (method, url))
        return ResearchVault.TransportResponse(200, Pair{String,String}[], Vector{UInt8}(codeunits(JSON.json(Dict("items" => [], "kind" => "ready")))))
    end
    client = VaultClient("http://127.0.0.1:43123", "a"^64; request_function=fake)
    @test figure_fonts(client; search="宋体")["items"] == []
    @test figure_render_batches(client, "fig_test")["items"] == []
    @test prepare_figure_preview(client, "figv_test"; run_id="run_test")["kind"] == "ready"
    @test figure_preview(client, "fpv_" * "a"^64)["kind"] == "ready"
    @test_throws ArgumentError figure_preview(client, "../bad")
    @test length(calls) == 4
    @test endswith(calls[3][2], "/interactive-preview")
    close(client)
end

read_fixture(name) = JSON.parse(read(joinpath(FIXTURE_ROOT, name), String))

@testset "immutable format contract workflow" begin
    fake = function (method, url, headers, body, timeout)
        if method == "GET"
            @test endswith(url, "/dsv_fixture/format-contract")
            return ResearchVault.TransportResponse(200, Pair{String,String}[], Vector{UInt8}(codeunits(JSON.json(Dict("contract" => nothing, "files" => ["power-hourly.csv"])))))
        end
        @test endswith(url, "/dsv_fixture/format-revisions")
        @test Set(keys(JSON.parse(String(body)))) == Set(["contract", "reason"])
        problem = Dict("code" => "dataset_version_conflict", "message" => "stale base", "request_id" => "req_test", "details" => Dict("current_version_id" => "dsv_current"))
        return ResearchVault.TransportResponse(409, Pair{String,String}[], Vector{UInt8}(codeunits(JSON.json(problem))))
    end
    client = VaultClient("http://127.0.0.1:43123", "a"^64; request_function=fake)
    @test dataset_format(client, "dsv_fixture")["contract"] === nothing
    failure = try
        revise_dataset_format(client, "dsv_fixture", Dict("schema_version" => 1); reason="Read header")
        nothing
    catch error
        error
    end
    @test failure isa VaultError
    @test failure.details["current_version_id"] == "dsv_current"
    @test_throws ArgumentError dataset_format(client, "dsv_../admin")
    close(client)
end

@testset "strict cross-language models" begin
    health = ResearchVault._parse_model(Health, read_fixture("health.json"))
    @test health.product == "Research Vault"
    @test health.healthy

    project = ResearchVault._parse_model(ResearchProject, read_fixture("project.json"))
    @test project.title == "Experiment"
    @test project.research_goal == "Compare simulated and measured output"

    task_fixture = read_fixture("task.json")
    task = ResearchVault._parse_model(VaultTask, task_fixture)
    @test terminal(task)
    @test task.progress == 1.0

    task_fixture["unexpected"] = true
    captured = try
        ResearchVault._parse_model(VaultTask, task_fixture)
        nothing
    catch error
        error
    end
    @test captured isa VaultError
    @test captured.code == "invalid_service_response"
end

@testset "problem and transport contract" begin
    problem_body = Vector{UInt8}(codeunits(JSON.json(read_fixture("problem.json"))))
    fake = function (method, url, headers, body, timeout)
        @test method == "GET"
        @test url == "http://127.0.0.1:43123/api/v1/test"
        @test ("Authorization" => "Bearer $("a"^64)") in headers
        @test isempty(body)
        @test timeout == 12.0
        return ResearchVault.TransportResponse(409, Pair{String,String}[], problem_body)
    end
    client = VaultClient(
        "http://127.0.0.1:43123",
        "a"^64;
        timeout=12.0,
        request_function=fake,
    )
    captured = try
        ResearchVault._request_json(client, "GET", "/api/v1/test")
        nothing
    catch error
        error
    end
    @test captured isa VaultError
    @test captured.status == 409
    @test captured.code == "revision_conflict"
    close(client)
    @test !isopen(client)
    @test_throws VaultConnectionError ResearchVault._request_json(client, "GET", "/health")
end

@testset "local discovery contract" begin
    mktempdir() do root
        runtime = joinpath(root, "runtime")
        mkpath(runtime)
        write(
            joinpath(runtime, "service.json"),
            JSON.json(Dict("endpoint" => "http://127.0.0.1:43123")),
        )
        write(joinpath(runtime, "service.token"), "b"^64)
        connection = ResearchVault._read_connection(runtime; process_probe=(_)->:alive)
        @test connection.endpoint == "http://127.0.0.1:43123"
        @test connection.token == "b"^64
        @test isnothing(ResearchVault._read_connection(runtime; process_probe=(_)->:exited))
        @test_throws VaultConnectionError ResearchVault._read_connection(runtime; process_probe=(_)->:reused)
        @test_throws VaultConnectionError ResearchVault._read_connection(runtime; process_probe=(_)->:unknown)
        @test ResearchVault._process_identity(Dict("pid"=>getpid())) == :reused
        @test ResearchVault._process_identity(Dict("pid"=>typemax(UInt32))) ==
              (Sys.iswindows() ? :exited : :unknown)

        executable = joinpath(root, "research-vault-service.exe")
        touch(executable)
        write(
            joinpath(runtime, "service-launcher.json"),
            JSON.json(
                Dict(
                    "schema_version" => 1,
                    "executable" => abspath(executable),
                    "service_version" => "0.8.0",
                ),
            ),
        )
        @test ResearchVault._read_launcher(runtime) == abspath(executable)

        write(
            joinpath(runtime, "service.json"),
            JSON.json(Dict("endpoint" => "http://example.com:43123")),
        )
        @test isnothing(ResearchVault._read_connection(runtime))
    end
end

@testset "service executable name compatibility" begin
    if Sys.iswindows()
        @test ResearchVault._is_service_process_name("research-vault-service.exe")
        @test ResearchVault._is_service_process_name(
            "research-vault-service-x86_64-pc-windows-msvc.exe",
        )
        @test ResearchVault._is_service_process_name("scenario-service.exe")
        @test ResearchVault._is_service_process_name(
            "scenario-service-x86_64-pc-windows-msvc.exe",
        )
        @test ResearchVault._is_current_service_executable_name(
            "RESEARCH-VAULT-SERVICE.EXE",
        )
        @test !ResearchVault._is_current_service_executable_name("scenario-service.exe")
    else
        @test ResearchVault._is_service_process_name("research-vault-service")
        @test ResearchVault._is_service_process_name("scenario-service")
        @test !ResearchVault._is_service_process_name("unrelated-service")
    end
    @test !ResearchVault._is_service_process_name("julia.exe")
end


@testset "branded app-data legacy fallback" begin
    mktempdir() do root
        current = joinpath(root, "com.haiyangbian.research-vault")
        legacy = joinpath(root, "com.alice.scenarios-generate")
        @test !ResearchVault._contains_vault_state(current)
        mkpath(joinpath(legacy, "research-vault"))
        write(joinpath(legacy, "research-vault", "catalog.sqlite"), "legacy")
        @test ResearchVault._contains_vault_state(legacy)
        mkpath(joinpath(current, "research-vault", "runtime"))
        write(joinpath(current, "research-vault", "runtime", "service-task.json"), "{}")
        @test ResearchVault._contains_vault_state(current)
    end
end

@testset "native scheduled-task activation" begin
    if Sys.iswindows()
        mktempdir() do root
            runtime = joinpath(root, "research-vault", "runtime")
            mkpath(runtime)
            executable = joinpath(root, "research-vault-service.exe")
            write(executable, "fixture")
            for schema_version in (1, 2)
                write(
                    joinpath(runtime, "service-task.json"),
                    JSON.json(
                        Dict(
                            "schema_version" => schema_version,
                            "executable" => executable,
                        ),
                    ),
                )
                @test ResearchVault._read_task_executable(runtime) == abspath(executable)
            end
            withenv("RESEARCH_VAULT_SERVICE" => nothing) do
                @test ResearchVault._resolve_service_executable(runtime, nothing) ==
                      abspath(executable)
            end
            command = ResearchVault._service_start_command(executable, root)
            @test command.exec == [
                abspath(executable),
                "service-task",
                "start",
                "--app-data",
                root,
            ]

            target_executable = joinpath(
                root,
                "research-vault-service-x86_64-pc-windows-msvc.exe",
            )
            write(target_executable, "fixture")
            target_command = ResearchVault._service_start_command(target_executable, root)
            @test first(target_command.exec) == abspath(target_executable)

            legacy_executable = joinpath(root, "scenario-service.exe")
            write(legacy_executable, "fixture")
            @test_throws VaultConnectionError ResearchVault._checked_executable(
                legacy_executable,
                "service task record",
            )
            @test_throws VaultConnectionError ResearchVault._service_start_command(
                legacy_executable,
                root,
            )
        end
    end
end

@testset "RFC3339 preserves source offset" begin
    timestamp = parse_rfc3339("2026-01-01T08:00:00.125+08:00")
    @test timestamp.raw == "2026-01-01T08:00:00.125+08:00"
    @test timestamp.offset_minutes == 480
    @test timestamp.utc == DateTime(2026, 1, 1, 0, 0, 0, 125)
    @test_throws ArgumentError parse_rfc3339("2026-01-01T08:00:00")
end

@testset "bounded query DSL and Tables integration" begin
    @test_throws ArgumentError QuerySpec(limit=4_001)
    @test_throws ArgumentError QueryFilter("category", "in")
    @test_throws ArgumentError QueryFilter("value", "between"; values=[1])
    query = QuerySpec(
        columns=["timestamp", "power_mw"],
        filters=[QueryFilter("power_mw", "gte"; value=0)],
        order_by=[QueryOrder("timestamp")],
        limit=100,
    )
    @test query.limit == 100

    table = ResearchVault._vault_table(read_fixture("query-result.json"))
    @test length(table) == 2
    @test Tables.columnnames(table) == (:timestamp, :power_mw)
    @test table[2].power_mw === missing
    frame = DataFrame(table)
    @test names(frame) == ["timestamp", "power_mw"]
    @test isequal(frame.power_mw, [1.5, missing])

    empty_fixture = read_fixture("query-result.json")
    empty_fixture["rows"] = []
    empty_fixture["row_count"] = 0
    empty_table = ResearchVault._vault_table(empty_fixture)
    @test isempty(empty_table)
    @test Tables.columnnames(empty_table) == (:timestamp, :power_mw)
end

@testset "typed project and dataset API" begin
    project_fixture = read_fixture("project.json")
    query_fixture = read_fixture("query-result.json")
    seen_query = Ref{Any}(nothing)
    fake = function (method, url, headers, body, timeout)
        @test ("Authorization" => "Bearer $("a"^64)") in headers
        if occursin("/research-projects", url)
            return ResearchVault.TransportResponse(
                200,
                Pair{String,String}[],
                Vector{UInt8}(codeunits(JSON.json(Dict("items" => [project_fixture])))),
            )
        elseif occursin("/query", url)
            seen_query[] = JSON.parse(String(body))
            return ResearchVault.TransportResponse(
                200,
                Pair{String,String}[],
                Vector{UInt8}(codeunits(JSON.json(query_fixture))),
            )
        end
        error("unexpected route")
    end
    client = VaultClient(
        "http://127.0.0.1:43123",
        "a"^64;
        request_function=fake,
    )
    @test only(projects(client)).title == "Experiment"
    table = query_dataset(
        client,
        "dsv_019d0000-0000-7000-8000-000000000007",
        QuerySpec(columns=["timestamp", "power_mw"], limit=10);
        logical_path="experiment.csv",
    )
    @test length(table) == 2
    @test seen_query[]["logical_path"] == "experiment.csv"
    @test !haskey(seen_query[]["query"], "sql")
    close(client)
end

@testset "task progress polling" begin
    fixture = read_fixture("task.json")
    states = [
        merge(copy(fixture), Dict("status" => "queued", "phase" => "queued", "progress" => 0.0)),
        merge(copy(fixture), Dict("status" => "running", "phase" => "writing", "progress" => 0.5)),
        fixture,
    ]
    index = Ref(0)
    fake = function (method, url, headers, body, timeout)
        index[] = min(index[] + 1, length(states))
        return ResearchVault.TransportResponse(
            200,
            Pair{String,String}[],
            Vector{UInt8}(codeunits(JSON.json(states[index[]]))),
        )
    end
    client = VaultClient(
        "http://127.0.0.1:43123",
        "a"^64;
        request_function=fake,
    )
    progress = Float64[]
    completed = wait_success(
        client,
        fixture["id"];
        timeout=1,
        poll_interval=0.001,
        on_progress=current -> push!(progress, current.progress),
    )
    @test completed.status == "completed"
    @test progress == [0.0, 0.5, 1.0]
    close(client)
end

@testset "run query becomes a long Tables table" begin
    response = Dict(
        "timestamps" => ["2026-01-01T00:00:00+08:00", "2026-01-01T01:00:00+08:00"],
        "scenario_indices" => [0, 2],
        "scenarios" => [
            Dict("pv" => [1.0, 2.0], "wind" => [3.0, 4.0]),
            Dict("pv" => [5.0, 6.0], "wind" => [7.0, 8.0]),
        ],
    )
    table = ResearchVault._run_window_table(response, ["pv", "wind"])
    @test length(table) == 4
    @test table[3].scenario_index == 2
    @test table[4].wind == 8.0
end

@testset "scenario request validates the protocol boundary" begin
    request = ScenarioRunRequest(
        Dict(
            "protocol_version" => 5,
            "timezone" => "Asia/Shanghai",
            "start" => "2026-01-01T00:00:00+08:00",
            "end" => "2026-01-02T00:00:00+08:00",
            "resolution_minutes" => 60,
            "interval_semantics" => "left_closed_right_open",
            "scenario_count" => 1,
            "seed" => 20260831,
            "requested_variables" => ["temperature"],
            "temperature" => Dict{String,Any}(),
        ),
    )
    @test request.payload["type"] == "generate"
    invalid = copy(request.payload)
    invalid["protocol_version"] = 4
    @test_throws ArgumentError ScenarioRunRequest(invalid)
end

@testset "artifact download is streamed and verified" begin
    artifact_fixture = read_fixture("artifact.json")
    content = Vector{UInt8}(codeunits("artifact fixture\n"))
    request_fake = function (method, url, headers, body, timeout)
        return ResearchVault.TransportResponse(
            200,
            Pair{String,String}[],
            Vector{UInt8}(codeunits(JSON.json(artifact_fixture))),
        )
    end
    download_fake = function (url, headers, destination, timeout)
        write(destination, content)
        return ResearchVault.TransportResponse(
            200,
            ["Content-Length" => string(length(content))],
            UInt8[],
        )
    end
    client = VaultClient(
        "http://127.0.0.1:43123",
        "a"^64;
        request_function=request_fake,
        download_function=download_fake,
    )
    mktempdir() do directory
        destination = joinpath(directory, "figure.txt")
        @test download_artifact(client, artifact_fixture["id"], destination) == destination
        @test read(destination) == content
        @test_throws ArgumentError download_artifact(client, artifact_fixture["id"], destination)
    end
    close(client)
end
