using JSON
using ResearchVault
using Tables
using Test

root = get(ENV, "RESEARCH_VAULT_INTEGRATION_ROOT", "")
isempty(root) && error("RESEARCH_VAULT_INTEGRATION_ROOT is required")
full = lowercase(get(ENV, "RESEARCH_VAULT_FULL_INTEGRATION", "false")) == "true"

source = joinpath(root, "experimental.csv")
write(
    source,
    "timestamp,value,lower,upper\n" *
    "2026-01-01T00:00:00+08:00,1.0,0.8,1.2\n" *
    "2026-01-01T01:00:00+08:00,2.0,1.7,2.3\n",
)

@testset "local Research Vault service integration" begin
    connect_local(; app_data=root, auto_start=false, request_timeout=180) do vault
        @test health(vault).healthy
        project_record = create_project(
            vault;
            title="Julia integration project",
            research_goal="Verify the language-neutral local client contract",
            tags=["integration"],
        )
        importing = import_dataset(
            vault,
            source;
            title="Julia experimental observations",
            kind=:experimental_table,
            provenance=:measured,
        )
        imported = wait_success(vault, importing.id; timeout=60)
        version = dataset_version(vault, imported.result_resource_id)
        attached = attach_resource(
            vault,
            project_record.id,
            :dataset_version,
            version.id;
            role="evidence",
        )
        @test attached.resource_id == version.id

        # A format-only version preserves original files and old project links.
        contract = Dict("schema_version" => 1,
            "profiles" => Dict("experiment" => Dict("format" => "csv", "null_values" => ["NA"])),
            "files" => Dict("experimental.csv" => "experiment"),
            "declaration" => Dict("source" => "human", "description" => "Fixture CSV header"))
        revised = revise_dataset_format(vault, version.id, contract; reason="Declare experimental format")
        @test revised.version.ordinal == 2
        @test revised.deduplicated_files == 1
        @test dataset_format(vault, version.id)["contract"] === nothing
        @test dataset_format(vault, revised.version.id)["validation"][1]["status"] == "contract_pending"
        @test_throws VaultError revise_dataset_format(vault, version.id, contract; reason="stale base")
        version = revised.version

        view = create_machine_view(vault, version.id; logical_path="experimental.csv")
        @test view.status == "available"
        table = query_dataset(
            vault,
            version.id,
            QuerySpec(
                columns=["timestamp", "value", "lower", "upper"],
                order_by=[QueryOrder("timestamp")],
                limit=10,
            );
            logical_path="experimental.csv",
        )
        @test length(table) == 2
        @test Tables.columnnames(table) == (:timestamp, :value, :lower, :upper)

        created = create_figure_from_dataset(
            vault,
            version.id;
            project_id=project_record.id,
            title="Experimental observations",
            logical_path="experimental.csv",
            x_column="timestamp",
            y_column="value",
            lower_column="lower",
            upper_column="upper",
        )
        @test created.figure.head_revision_id == created.revision.revision.id

        if full
            rendering = render_figure(vault, created.revision.revision.id)
            rendered = wait_task(vault, rendering.id; timeout=240)
            rendered.status == "completed" || error("Figure integration failed: $(JSON.json(rendered.error))")
            render_run = ResearchVault.run(vault, rendered.result_resource_id)
            svg = only(filter(item -> endswith(item.name, ".svg"), render_run.artifacts))
            output = download_artifact(vault, svg.id, joinpath(root, "integration.svg"))
            @test isfile(output)

            request = JSON.parse(
                read(joinpath(@__DIR__, "fixtures", "v1", "scenario-request.json"), String),
            )
            request["research_project_id"] = project_record.id
            generation = start_scenario_run(vault, request)
            generated = wait_task(vault, generation.id; timeout=240)
            generated.status == "completed" || error("Scientific integration failed: $(JSON.json(generated.error))")
            @test startswith(generated.result_resource_id, "run_")
        end
    end
end
