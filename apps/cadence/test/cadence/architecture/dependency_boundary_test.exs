defmodule Cadence.Architecture.DependencyBoundaryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Architecture.DependencyBoundary

  test "finds root-facade, horizontal schema, and cross-context row dependencies" do
    graph = %{
      "lib/cadence/accounts.ex" => %{
        "lib/cadence/organizations/organization_row.ex" => "export"
      },
      "lib/cadence/catalog/importer.ex" => %{
        "lib/cadence/catalog/artifact_row.ex" => "export"
      },
      "lib/cadence/dashboards/source.ex" => %{
        "lib/cadence.ex" => "runtime",
        "lib/cadence/accounts/user_row.ex" => "export",
        "lib/cadence/persistence/schemas/dashboard_row.ex" => "export"
      },
      "lib/cadence/persistence.ex" => %{
        "lib/cadence/persistence/schemas/dashboard_row.ex" => "runtime"
      },
      "lib/cadence/persistence/organization_scope.ex" => %{
        "lib/cadence/missions/mission_row.ex" => "export"
      },
      "lib/cadence/persistence/store.ex" => %{
        "lib/cadence/persistence/schemas/dashboard_row.ex" => "runtime"
      },
      "lib/cadence/source_endpoints.ex" => %{
        "lib/cadence/comms/transport_row.ex" => "export"
      }
    }

    assert [
             %{
               kind: :context_schema,
               source: "lib/cadence/dashboards/source.ex",
               sink: "lib/cadence/accounts/user_row.ex"
             },
             %{
               kind: :context_schema,
               source: "lib/cadence/persistence/organization_scope.ex",
               sink: "lib/cadence/missions/mission_row.ex"
             },
             %{
               kind: :persistence_schema,
               source: "lib/cadence/dashboards/source.ex",
               label: "export"
             },
             %{
               kind: :root_facade,
               source: "lib/cadence/dashboards/source.ex",
               label: "runtime"
             }
           ] = DependencyBoundary.findings(graph)
  end

  test "protects limits jobs and notifications rows through their owning contexts" do
    graph = %{
      "lib/cadence/accounts.ex" => %{
        "lib/cadence/notifications/notification_row.ex" => "export"
      },
      "lib/cadence/dashboards/source.ex" => %{
        "lib/cadence/limits/governed_limit_definition_row.ex" => "export"
      },
      "lib/cadence/jobs.ex" => %{
        "lib/cadence/jobs/background_job_row.ex" => "export"
      },
      "lib/cadence/limits/definition_lifecycle.ex" => %{
        "lib/cadence/limits/governed_limit_definition_row.ex" => "export"
      },
      "lib/cadence/notifications.ex" => %{
        "lib/cadence/notifications/notification_row.ex" => "export"
      },
      "lib/cadence/telemetry/storage.ex" => %{
        "lib/cadence/jobs/background_job_row.ex" => "export"
      }
    }

    assert [
             %{
               kind: :context_schema,
               source: "lib/cadence/accounts.ex",
               sink: "lib/cadence/notifications/notification_row.ex"
             },
             %{
               kind: :context_schema,
               source: "lib/cadence/dashboards/source.ex",
               sink: "lib/cadence/limits/governed_limit_definition_row.ex"
             },
             %{
               kind: :context_schema,
               source: "lib/cadence/telemetry/storage.ex",
               sink: "lib/cadence/jobs/background_job_row.ex"
             }
           ] = DependencyBoundary.findings(graph)
  end

  test "protects projection rows through the projections context" do
    graph = %{
      "lib/cadence/dashboards/source.ex" => %{
        "lib/cadence/projections/telemetry_latest_values/rebuild_run_row.ex" => "export"
      },
      "lib/cadence/projections/telemetry_latest_values.ex" => %{
        "lib/cadence/projections/telemetry_latest_values/rebuild_run_row.ex" => "export"
      }
    }

    assert [
             %{
               kind: :context_schema,
               source: "lib/cadence/dashboards/source.ex",
               sink: "lib/cadence/projections/telemetry_latest_values/rebuild_run_row.ex"
             }
           ] = DependencyBoundary.findings(graph)
  end

  test "compares current edges with the checked-in debt baseline" do
    findings =
      DependencyBoundary.findings(%{
        "lib/cadence/dashboards/source.ex" => %{"lib/cadence.ex" => "runtime"}
      })

    [finding] = findings

    baseline = %{
      owner: "Core architecture",
      review_by: ~D[2026-10-18],
      rationale: "Retire transitional edges",
      allowed: MapSet.new([finding.fingerprint, "root_facade|resolved|edge"])
    }

    assert %{
             new: [],
             resolved: ["root_facade|resolved|edge"],
             expired?: false
           } = DependencyBoundary.compare(findings, baseline, ~D[2026-07-18])

    assert %{expired?: true} =
             DependencyBoundary.compare(findings, baseline, ~D[2026-10-19])
  end

  test "reports an edge missing from the baseline" do
    findings =
      DependencyBoundary.findings(%{
        "lib/cadence/dashboards/source.ex" => %{"lib/cadence.ex" => "runtime"}
      })

    baseline = %{
      owner: "Core architecture",
      review_by: ~D[2026-10-18],
      rationale: "Retire transitional edges",
      allowed: MapSet.new()
    }

    assert %{new: [%{kind: :root_facade}], resolved: []} =
             DependencyBoundary.compare(findings, baseline, ~D[2026-07-18])
  end

  test "loads required ownership and expiry metadata" do
    path =
      Path.join(
        System.tmp_dir!(),
        "cadence-dependency-baseline-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.write!(path, """
    # owner: Core architecture
    # review-by: 2026-10-18
    # rationale: Remove transitional dependencies

    root_facade|lib/cadence/source.ex|lib/cadence.ex
    """)

    on_exit(fn -> File.rm!(path) end)

    assert %{
             owner: "Core architecture",
             review_by: ~D[2026-10-18],
             rationale: "Remove transitional dependencies",
             allowed: allowed
           } = DependencyBoundary.read_baseline!(path)

    assert MapSet.member?(
             allowed,
             "root_facade|lib/cadence/source.ex|lib/cadence.ex"
           )
  end
end
