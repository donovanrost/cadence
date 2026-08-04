defmodule Cadence.Architecture.DependencyBoundaryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Architecture.DependencyBoundary

  test "dashboard adapters use reads and configured providers instead of owner IO" do
    graph = %{
      "lib/cadence/dashboards/sources/telemetry.ex" => %{
        "lib/cadence/reads/telemetry.ex" => "runtime",
        "lib/cadence/telemetry/storage.ex" => "runtime"
      },
      "lib/cadence/dashboards/data_link_resolver/command_targets.ex" => %{
        "lib/cadence/commanding.ex" => "runtime",
        "lib/cadence/reads/commands.ex" => "runtime"
      },
      "lib/cadence/dashboards/runtime_fact_consumer.ex" => %{
        "lib/cadence/telemetry/backfill_lifecycle_changed.ex" => "runtime",
        "lib/cadence/telemetry/storage/backfill_lifecycle_event.ex" => "runtime"
      },
      "lib/cadence/dashboards/source_registry/adapter_options.ex" => %{
        "lib/cadence/management/data_sources/credentials.ex" => "runtime",
        "lib/cadence/reads/data_sources.ex" => "runtime"
      }
    }

    assert [
             %{
               kind: :dashboard_io_boundary,
               source: "lib/cadence/dashboards/data_link_resolver/command_targets.ex",
               sink: "lib/cadence/commanding.ex"
             },
             %{
               kind: :dashboard_io_boundary,
               source: "lib/cadence/dashboards/runtime_fact_consumer.ex",
               sink: "lib/cadence/telemetry/storage/backfill_lifecycle_event.ex"
             },
             %{
               kind: :dashboard_io_boundary,
               source: "lib/cadence/dashboards/source_registry/adapter_options.ex",
               sink: "lib/cadence/management/data_sources/credentials.ex"
             },
             %{
               kind: :dashboard_io_boundary,
               source: "lib/cadence/dashboards/sources/telemetry.ex",
               sink: "lib/cadence/telemetry/storage.ex"
             }
           ] =
             graph
             |> DependencyBoundary.findings()
             |> Enum.filter(&(&1.kind == :dashboard_io_boundary))
  end

  test "enforces plane direction and explicit public cross-plane boundaries" do
    graph = %{
      "lib/cadence/control/activations/executor.ex" => %{
        "lib/cadence/runtime/managed_action_request.ex" => "export",
        "lib/cadence/runtime/mission_runtime_spec.ex" => "export",
        "lib/cadence/runtime/missions.ex" => "runtime",
        "lib/cadence/runtime/mission_coordinator.ex" => "runtime"
      },
      "lib/cadence/management/activations.ex" => %{
        "lib/cadence/runtime/managed_action_request.ex" => "export"
      },
      "lib/cadence/projections/mission_events.ex" => %{
        "lib/cadence/runtime/managed_action_request.ex" => "export"
      },
      "lib/cadence/runtime/mission_coordinator.ex" => %{
        "lib/cadence/management/activations.ex" => "runtime",
        "lib/cadence/runtime/mission_runtime.ex" => "runtime"
      }
    }

    findings = DependencyBoundary.findings(graph)

    assert Enum.any?(findings, fn finding ->
             finding.kind == :plane_internal and
               finding.source == "lib/cadence/control/activations/executor.ex" and
               finding.sink == "lib/cadence/runtime/mission_coordinator.ex"
           end)

    assert Enum.count(findings, &(&1.kind == :plane_direction)) == 2

    refute Enum.any?(findings, fn finding ->
             finding.sink == "lib/cadence/runtime/managed_action_request.ex" and
               finding.source in [
                 "lib/cadence/control/activations/executor.ex",
                 "lib/cadence/projections/mission_events.ex"
               ]
           end)

    refute Enum.any?(findings, fn finding ->
             finding.source == "lib/cadence/control/activations/executor.ex" and
               finding.sink in [
                 "lib/cadence/runtime/mission_runtime_spec.ex",
                 "lib/cadence/runtime/missions.ex"
               ]
           end)

    refute Enum.any?(findings, fn finding ->
             finding.source == "lib/cadence/runtime/mission_coordinator.ex" and
               finding.sink == "lib/cadence/runtime/mission_runtime.ex"
           end)
  end

  test "data-plane source does not reach into activation or governance persistence" do
    runtime_sources =
      ["lib/cadence/runtime.ex" | Path.wildcard("lib/cadence/runtime/**/*.ex")]

    forbidden_references = ["Cadence.Activations", "Cadence.Governance"]

    assert [] ==
             for(
               source <- runtime_sources,
               reference <- forbidden_references,
               String.contains?(File.read!(source), reference),
               do: {source, reference}
             )
  end

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

  test "protects application dashboard network and projection rows through owning contexts" do
    graph = %{
      "lib/cadence/accounts.ex" => %{
        "lib/cadence/applications/application_binding_store/binding_row.ex" => "export",
        "lib/cadence/dashboards/data_sources/data_source_row.ex" => "export",
        "lib/cadence/ground_networks/provider_accounts/account_row.ex" => "export"
      },
      "lib/cadence/applications/telemetry_decom.ex" => %{
        "lib/cadence/applications/application_binding_store/binding_row.ex" => "export"
      },
      "lib/cadence/dashboards/data_sources.ex" => %{
        "lib/cadence/dashboards/data_sources/data_source_row.ex" => "export"
      },
      "lib/cadence/ground_networks/provider_accounts.ex" => %{
        "lib/cadence/ground_networks/provider_accounts/account_row.ex" => "export"
      },
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
               source: "lib/cadence/accounts.ex",
               sink: "lib/cadence/applications/application_binding_store/binding_row.ex"
             },
             %{
               kind: :context_schema,
               source: "lib/cadence/accounts.ex",
               sink: "lib/cadence/dashboards/data_sources/data_source_row.ex"
             },
             %{
               kind: :context_schema,
               source: "lib/cadence/accounts.ex",
               sink: "lib/cadence/ground_networks/provider_accounts/account_row.ex"
             },
             %{
               kind: :context_schema,
               source: "lib/cadence/dashboards/source.ex",
               sink: "lib/cadence/projections/telemetry_latest_values/rebuild_run_row.ex"
             }
           ] = DependencyBoundary.findings(graph)
  end

  test "protects operational event rows through their owning context" do
    graph = %{
      "lib/cadence/dashboards/data_link_resolver.ex" => %{
        "lib/cadence/operational_events/event_row.ex" => "export"
      },
      "lib/cadence/operational_events.ex" => %{
        "lib/cadence/operational_events/event_row.ex" => "export"
      }
    }

    assert [
             %{
               kind: :context_schema,
               source: "lib/cadence/dashboards/data_link_resolver.ex",
               sink: "lib/cadence/operational_events/event_row.ex"
             }
           ] = DependencyBoundary.findings(graph)
  end

  test "protects contact profile rows through their owning context" do
    graph = %{
      "lib/cadence/contact_planning/planner.ex" => %{
        "lib/cadence/contacts/contact_store/scheduled_contact_row.ex" => "export",
        "lib/cadence/contacts/link_assignment_store/link_assignment_row.ex" => "export",
        "lib/cadence/contacts/path_template_store/path_template_row.ex" => "export",
        "lib/cadence/contacts/profile_store/provider_profile_row.ex" => "export"
      },
      "lib/cadence/contacts/profile_store.ex" => %{
        "lib/cadence/contacts/profile_store/provider_profile_row.ex" => "export",
        "lib/cadence/contacts/profile_store/transport_profile_row.ex" => "export"
      }
    }

    assert [
             %{
               kind: :context_schema,
               source: "lib/cadence/contact_planning/planner.ex",
               sink: "lib/cadence/contacts/contact_store/scheduled_contact_row.ex"
             },
             %{
               kind: :context_schema,
               source: "lib/cadence/contact_planning/planner.ex",
               sink: "lib/cadence/contacts/link_assignment_store/link_assignment_row.ex"
             },
             %{
               kind: :context_schema,
               source: "lib/cadence/contact_planning/planner.ex",
               sink: "lib/cadence/contacts/path_template_store/path_template_row.ex"
             },
             %{
               kind: :context_schema,
               source: "lib/cadence/contact_planning/planner.ex",
               sink: "lib/cadence/contacts/profile_store/provider_profile_row.ex"
             }
           ] = DependencyBoundary.findings(graph)
  end

  test "protects derived telemetry rows through their owning context" do
    graph = %{
      "lib/cadence/dashboards/data_link_resolver.ex" => %{
        "lib/cadence/derived_telemetry/evaluation_run_row.ex" => "export"
      },
      "lib/cadence/derived_telemetry.ex" => %{
        "lib/cadence/derived_telemetry/evaluation_run_row.ex" => "export"
      }
    }

    assert [
             %{
               kind: :context_schema,
               source: "lib/cadence/dashboards/data_link_resolver.ex",
               sink: "lib/cadence/derived_telemetry/evaluation_run_row.ex"
             }
           ] = DependencyBoundary.findings(graph)
  end

  test "protects telemetry storage rows through their owning context" do
    graph = %{
      "lib/cadence/dashboards/data_link_resolver.ex" => %{
        "lib/cadence/telemetry/storage/backfill_lifecycle_events/event_row.ex" => "export"
      },
      "lib/cadence/telemetry/storage/backfill_lifecycle_events.ex" => %{
        "lib/cadence/telemetry/storage/backfill_lifecycle_events/event_row.ex" => "export"
      }
    }

    assert [
             %{
               kind: :context_schema,
               source: "lib/cadence/dashboards/data_link_resolver.ex",
               sink: "lib/cadence/telemetry/storage/backfill_lifecycle_events/event_row.ex"
             }
           ] = DependencyBoundary.findings(graph)
  end

  test "protects archive manifest rows through their owning contexts" do
    graph = %{
      "lib/cadence/dashboards/data_link_resolver.ex" => %{
        "lib/cadence/ingress_archive/file_system/evidence_entry_row.ex" => "export",
        "lib/cadence/protocol/record_archive/file_system/record_entry_row.ex" => "export"
      },
      "lib/cadence/ingress_archive/filesystem.ex" => %{
        "lib/cadence/ingress_archive/file_system/evidence_entry_row.ex" => "export"
      },
      "lib/cadence/protocol/record_archive/filesystem.ex" => %{
        "lib/cadence/protocol/record_archive/file_system/record_entry_row.ex" => "export"
      }
    }

    assert [
             %{
               kind: :context_schema,
               source: "lib/cadence/dashboards/data_link_resolver.ex",
               sink: "lib/cadence/ingress_archive/file_system/evidence_entry_row.ex"
             },
             %{
               kind: :context_schema,
               source: "lib/cadence/dashboards/data_link_resolver.ex",
               sink: "lib/cadence/protocol/record_archive/file_system/record_entry_row.ex"
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
