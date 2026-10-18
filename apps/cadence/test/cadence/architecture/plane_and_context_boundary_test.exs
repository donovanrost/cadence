defmodule Cadence.Architecture.PlaneAndContextBoundaryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Architecture.{ContextBoundary, DependencyBoundary, PlaneBoundary}

  test "mission startup ingress is exact and observation recording is a forward context dependency" do
    root = "lib/cadence/control/missions.ex"

    for caller <- ["lib/cadence/contacts/scheduler.ex", "lib/cadence/control/mission_recovery.ex"] do
      assert [] == DependencyBoundary.findings(%{caller => %{root => "runtime"}})
    end

    assert [%{kind: :context_direction}] =
             ContextBoundary.findings_for_edge(
               "lib/cadence/control/mission_worker.ex",
               root,
               "runtime"
             )

    assert [%{kind: :plane_direction}] =
             PlaneBoundary.findings_for_edge(
               "lib/cadence/management/commanding.ex",
               root,
               "runtime"
             )

    assert [] ==
             DependencyBoundary.findings(%{
               "lib/cadence/telemetry/storage.ex" => %{
                 "lib/cadence/projections/data_sources/watermarks.ex" => "runtime"
               }
             })

    assert [%{kind: :context_direction}] =
             ContextBoundary.findings_for_edge(
               "lib/cadence/projections/data_sources/watermarks.ex",
               "lib/cadence/telemetry/storage.ex",
               "runtime"
             )

    assert [%{kind: :context_schema}] =
             DependencyBoundary.findings(%{
               "lib/cadence/telemetry/storage.ex" => %{
                 "lib/cadence/projections/data_sources/watermarks/event_row.ex" => "export"
               }
             })
  end

  test "active generation adaptation is explicit and management keeps its authority boundary" do
    adapter = "lib/cadence/reads/mission_models/active_basis.ex"
    caller = "lib/cadence/commanding/request_validation.ex"
    assert PlaneBoundary.classify(adapter) == :adapter
    assert ContextBoundary.classify(adapter) == :adapter
    assert [] == DependencyBoundary.findings(%{caller => %{adapter => "runtime"}})

    assert [%{kind: :plane_direction}] =
             PlaneBoundary.findings_for_edge(
               caller,
               "lib/cadence/control/mission_model_promotion.ex",
               "runtime"
             )

    assert PlaneBoundary.classify("lib/cadence/reads/mission_models/other_query.ex") ==
             :projections

    assert [%{kind: :context_schema}] =
             DependencyBoundary.findings(%{
               adapter => %{"lib/cadence/activations/active_binding_set_row.ex" => "export"}
             })
  end

  test "continuation and repair own operational execution rather than management declarations" do
    for name <- ~w(fleet_run_actions fleet_run_repairs) do
      path = "lib/cadence/contact_planning/#{name}.ex"
      assert PlaneBoundary.classify(path) == :control
      assert ContextBoundary.classify(path) == :contacts

      assert [] ==
               DependencyBoundary.findings(%{
                 path => %{"lib/cadence/contact_planning/contact_plan_executions.ex" => "runtime"}
               })
    end

    assert [%{kind: :plane_direction}] =
             PlaneBoundary.findings_for_edge(
               "lib/cadence/contact_planning/new_declaration.ex",
               "lib/cadence/contact_planning/fleet_run_repairs.ex",
               "runtime"
             )
  end

  test "mission lifecycle assembly reaches the public contact owner without changing its plane" do
    source = "lib/cadence/control/missions.ex"
    assert ContextBoundary.classify(source) == :composition
    assert PlaneBoundary.classify(source) == :control

    assert [] ==
             DependencyBoundary.findings(%{
               source => %{"lib/cadence/control/contacts.ex" => "runtime"}
             })

    assert [%{kind: :plane_direction}] =
             PlaneBoundary.findings_for_edge(
               source,
               "lib/cadence/projections/mission_summary.ex",
               "runtime"
             )

    refute ContextBoundary.classify("lib/cadence/control/mission_runtime.ex") == :composition
  end

  test "pure semantic qualification shares catalog evaluation without exposing durable runtime execution" do
    for path <- [
          "lib/cadence/semantic_runtime.ex",
          "lib/cadence/semantic_runtime/state.ex",
          "lib/cadence/semantic_runtime/plan_decoder.ex",
          "lib/cadence/runtime/mission_model_plan_decoder.ex"
        ] do
      assert PlaneBoundary.classify(path) == :shared
      assert ContextBoundary.classify(path) == :catalog

      assert [] ==
               DependencyBoundary.findings(%{
                 "lib/cadence/mission_models/comparison.ex" => %{path => "runtime"}
               })

      assert [%{kind: :plane_direction}] =
               PlaneBoundary.findings_for_edge(path, "lib/cadence/control/contacts.ex", "runtime")
    end

    store = "lib/cadence/semantic_runtime/store.ex"
    assert PlaneBoundary.classify(store) == :data
    assert ContextBoundary.classify(store) == :runtime

    assert [%{kind: :plane_direction}] =
             PlaneBoundary.findings_for_edge(
               "lib/cadence/mission_models/comparison.ex",
               store,
               "runtime"
             )

    assert PlaneBoundary.classify("lib/cadence/limits/store.ex") == :data
  end

  test "compiled contribution catalogs expose metadata without exposing arbitrary composition" do
    for catalog <- [
          "lib/cadence/extension_catalog.ex",
          "lib/cadence/applications/registry.ex",
          "lib/cadence/applications/comms.ex"
        ] do
      assert PlaneBoundary.classify(catalog) == :composition
      assert ContextBoundary.classify(catalog) == :composition

      assert [] ==
               DependencyBoundary.findings(%{
                 "lib/cadence/reads/application_references.ex" => %{catalog => "runtime"}
               })
    end

    assert PlaneBoundary.classify("lib/cadence/applications/telemetry_decom.ex") == :management
    refute PlaneBoundary.public_composition_value?("lib/cadence/applications/telemetry_decom.ex")
    refute PlaneBoundary.public_composition_value?("lib/cadence/platform/root_composition.ex")
    refute PlaneBoundary.public_composition_value?("lib/cadence/extensions/registry.ex")

    assert ContextBoundary.classify("lib/cadence/projections/data_source_bindings.ex") ==
             :read_models
  end

  test "public process addresses do not grant access to supervision or arbitrary composition" do
    caller = "lib/cadence/control/mission_runtime.ex"

    for owner <- ~w(control runtime) do
      value = "lib/cadence/#{owner}/process_namespace.ex"
      assert PlaneBoundary.classify(value) == :composition
      assert ContextBoundary.classify(value) == :composition
      assert [] == DependencyBoundary.findings(%{caller => %{value => "export"}})

      assert [] ==
               DependencyBoundary.findings(%{
                 value => %{"lib/cadence/#{owner}/supervisor.ex" => "runtime"}
               })
    end

    for sink <- ["lib/cadence/runtime/supervisor.ex", "lib/cadence/platform/root_composition.ex"] do
      assert [%{kind: :plane_direction}] =
               PlaneBoundary.findings_for_edge(caller, sink, "runtime")

      assert [%{kind: :context_direction}] =
               ContextBoundary.findings_for_edge(caller, sink, "runtime")
    end
  end

  test "packet declaration values are shared while configuration and rows retain management authority" do
    for name <-
          ~w(packet_binding packet_binding_configuration packet_binding_resource mission_binding_contribution surface_query_contribution surface_elements/packet_bindings surface_elements/packet_binding_group surface_elements/packet_binding_resource) do
      path = "lib/cadence/applications/#{name}.ex"
      assert PlaneBoundary.classify(path) == :shared

      assert [%{kind: :plane_direction}] =
               PlaneBoundary.findings_for_edge(path, "lib/cadence/control/contacts.ex", "runtime")
    end

    for name <-
          ~w(configuration_lock packet_bindings mission_binding_composer packet_bindings/configuration_row) do
      assert PlaneBoundary.classify("lib/cadence/applications/#{name}.ex") == :management
    end
  end

  test "host providers and notification recipient authorization have their actual owners" do
    for name <-
          ~w(comms/action_provider spacecraft/action_provider mission_catalog/action_provider telemetry_decom/action_provider organization_admin_query organization_admin_providers/provider_account_new) do
      path = "lib/cadence/applications/#{name}.ex"
      assert PlaneBoundary.classify(path) == :adapter
      assert ContextBoundary.classify(path) == :adapter
    end

    for name <- ~w(actions recipient) do
      path = "lib/cadence/notifications/#{name}.ex"
      assert PlaneBoundary.classify(path) == :management
      assert ContextBoundary.classify(path) == :identity

      assert [] ==
               DependencyBoundary.findings(%{path => %{"lib/cadence/accounts.ex" => "runtime"}})
    end

    assert PlaneBoundary.classify("lib/cadence/notifications/store.ex") == :platform

    assert [%{kind: :context_direction}] =
             ContextBoundary.findings_for_edge(
               "lib/cadence/notifications/store.ex",
               "lib/cadence/accounts.ex",
               "runtime"
             )
  end

  test "Data Sources observation stores keep their owner before the generic read-model fallback" do
    for name <- ~w(health watermarks) do
      path = "lib/cadence/projections/data_sources/#{name}.ex"
      assert PlaneBoundary.classify(path) == :data
      assert ContextBoundary.classify(path) == :data_sources

      assert [] ==
               PlaneBoundary.findings_for_edge(
                 "lib/cadence/telemetry/storage.ex",
                 path,
                 "runtime"
               )

      assert [%{kind: :plane_direction}] =
               PlaneBoundary.findings_for_edge(
                 path,
                 "lib/cadence/management/data_sources.ex",
                 "runtime"
               )

      assert [] ==
               DependencyBoundary.findings(%{
                 "lib/cadence/reads/data_sources.ex" => %{path => "runtime"}
               })
    end

    assert ContextBoundary.classify("lib/cadence/projections/unrelated_projection.ex") ==
             :read_models
  end

  test "reviewed UI request adapters can orchestrate public owners but cannot consume their rows" do
    for name <-
          ~w(contact_planning data_sources fleet_policy_workflow historical_workflow_actions) do
      path = "lib/cadence/applications/ops_console/actions/#{name}.ex"
      assert PlaneBoundary.classify(path) == :adapter
      assert ContextBoundary.classify(path) == :adapter

      assert [] ==
               DependencyBoundary.findings(%{
                 path => %{"lib/cadence/control/contacts.ex" => "runtime"}
               })

      assert [%{kind: :context_schema}] =
               DependencyBoundary.findings(%{
                 path => %{
                   "lib/cadence/management/contacts/store/contact_plan_row.ex" => "export"
                 }
               })

      assert [%{kind: :root_facade}] =
               DependencyBoundary.findings(%{path => %{"lib/cadence.ex" => "runtime"}})
    end

    for path <- [
          "lib/cadence/applications/evaluator.ex",
          "lib/cadence/applications/ops_console/actions/unreviewed_worker.ex"
        ] do
      assert PlaneBoundary.classify(path) == :data

      assert [%{kind: :plane_direction}] =
               PlaneBoundary.findings_for_edge(path, "lib/cadence/control/contacts.ex", "runtime")
    end
  end

  test "each concrete subsystem supervisor is composition, without exempting its workers" do
    for owner <- ["platform", "control", "runtime", "projections"] do
      path = "lib/cadence/#{owner}/supervisor.ex"
      assert PlaneBoundary.classify(path) == :composition
      assert ContextBoundary.classify(path) == :composition

      assert [] ==
               DependencyBoundary.findings(%{
                 path => %{"lib/cadence/platform/root_composition.ex" => "export"}
               })
    end

    refute PlaneBoundary.classify("lib/cadence/runtime/worker.ex") == :composition
    refute PlaneBoundary.classify("lib/cadence/control/worker.ex") == :composition
  end

  test "bounded fleet input snapshots belong to the management contact store owner" do
    row = "lib/cadence/management/contacts/store/contact_requirement_version_row.ex"

    assert [] ==
             DependencyBoundary.findings(%{
               "lib/cadence/contact_planning/fleet_start_inputs.ex" => %{row => "export"}
             })

    assert [%{kind: :context_schema}] =
             DependencyBoundary.findings(%{
               "lib/cadence/reads/fleet_inputs.ex" => %{row => "export"}
             })
  end

  test "the exact subsystem root constructor composes policies without exempting other platform code" do
    constructor = "lib/cadence/platform/root_composition.ex"
    assert PlaneBoundary.classify(constructor) == :composition
    assert ContextBoundary.classify(constructor) == :composition

    assert [] ==
             DependencyBoundary.findings(%{
               constructor => %{"lib/cadence/telemetry/storage.ex" => "runtime"}
             })

    assert [%{kind: :plane_direction}] =
             PlaneBoundary.findings_for_edge(
               "lib/cadence/platform/other_policy.ex",
               "lib/cadence/telemetry/storage.ex",
               "runtime"
             )

    assert [%{kind: :context_direction}] =
             ContextBoundary.findings_for_edge(
               "lib/cadence/platform/other_policy.ex",
               "lib/cadence/telemetry/storage.ex",
               "runtime"
             )
  end

  test "pure host validation and packet declarations are shared values without runtime authority" do
    for path <- [
          "lib/cadence/applications/json_boundary.ex",
          "lib/cadence/applications/packet_input_definition.ex"
        ] do
      assert PlaneBoundary.classify(path) == :shared

      assert [] ==
               PlaneBoundary.findings_for_edge(
                 "lib/cadence/management/communications_setup.ex",
                 path,
                 "runtime"
               )

      assert [%{kind: :plane_direction}] =
               PlaneBoundary.findings_for_edge(
                 path,
                 "lib/cadence/control/mission_runtime.ex",
                 "runtime"
               )
    end

    assert ContextBoundary.classify("lib/cadence/applications/json_boundary.ex") == :platform

    assert ContextBoundary.classify("lib/cadence/applications/packet_input_definition.ex") ==
             :catalog

    assert PlaneBoundary.classify("lib/cadence/applications/unreviewed_evaluator.ex") == :data

    assert [%{kind: :plane_direction}] =
             PlaneBoundary.findings_for_edge(
               "lib/cadence/applications/unreviewed_evaluator.ex",
               "lib/cadence/control/mission_runtime.ex",
               "runtime"
             )
  end

  test "every current core module has explicit plane and context ownership" do
    paths = ["lib/cadence.ex" | Path.wildcard("lib/cadence/**/*.ex")]

    assert [] == Enum.reject(paths, &PlaneBoundary.classify/1)

    assert [] ==
             Enum.reject(paths, fn path ->
               path == "lib/cadence.ex" or ContextBoundary.classify(path)
             end)
  end

  test "administration identity effects retain management authority and identity dependency limits" do
    for source <- [
          "lib/cadence/administration/access.ex",
          "lib/cadence/administration/organization_creation.ex"
        ] do
      assert PlaneBoundary.classify(source) == :management
      assert ContextBoundary.classify(source) == :identity
      assert [] == ContextBoundary.findings_for_edge(source, "lib/cadence/accounts.ex", "runtime")

      assert [%{kind: :context_direction}] =
               ContextBoundary.findings_for_edge(source, "lib/cadence/catalog.ex", "runtime")
    end
  end

  test "web production modules are classified as adapters" do
    assert :adapter ==
             PlaneBoundary.classify("lib/cadence_web/controllers/telemetry_controller.ex")

    assert :adapter ==
             PlaneBoundary.classify("lib/cadence_web/live/ops_dashboard_show_live.ex")
  end

  test "ingress journal belongs to the telemetry data plane" do
    path = "lib/cadence/ingress_journal/file_system.ex"

    assert :data == PlaneBoundary.classify(path)
    assert :telemetry == ContextBoundary.classify(path)
  end

  test "unclassified core modules fail closed" do
    findings =
      DependencyBoundary.findings(%{
        "lib/cadence/unowned_feature/worker.ex" => %{}
      })

    assert Enum.map(findings, & &1.kind) == [:unclassified_context, :unclassified_plane]
  end

  test "spacecraft identity changes belong to management authority in the identity context" do
    path = "lib/cadence/spacecraft/identity.ex"

    assert :management == PlaneBoundary.classify(path)
    assert :identity == ContextBoundary.classify(path)
  end

  test "enforces the context matrix while preserving named orchestration" do
    assert [%{kind: :context_direction}] =
             ContextBoundary.findings_for_edge(
               "lib/cadence/accounts.ex",
               "lib/cadence/catalog.ex",
               "runtime"
             )

    assert [] ==
             ContextBoundary.findings_for_edge(
               "lib/cadence/catalog.ex",
               "lib/cadence/accounts.ex",
               "runtime"
             )

    assert [] ==
             ContextBoundary.findings_for_edge(
               "lib/cadence/control/activations.ex",
               "lib/cadence/control/mission_runtime_reconciler.ex",
               "runtime"
             )

    assert [] ==
             ContextBoundary.findings_for_edge(
               "lib/cadence/ground_networks/provider_event_processor.ex",
               "lib/cadence/control/contacts/provider_events.ex",
               "runtime"
             )

    assert [%{kind: :context_direction}] =
             ContextBoundary.findings_for_edge(
               "lib/cadence/ground_networks/provider_event_processor.ex",
               "lib/cadence/contacts/provider_reservations.ex",
               "runtime"
             )

    assert [] ==
             ContextBoundary.findings_for_edge(
               "lib/cadence/control/providers.ex",
               "lib/cadence/control/contacts/provider_grants.ex",
               "runtime"
             )

    assert [%{kind: :context_direction}] =
             ContextBoundary.findings_for_edge(
               "lib/cadence/control/providers.ex",
               "lib/cadence/contacts/provider_reservations.ex",
               "runtime"
             )

    assert [] ==
             ContextBoundary.findings_for_edge(
               "lib/cadence/governance.ex",
               "lib/cadence/management/comms/source_endpoint_references.ex",
               "runtime"
             )

    assert [%{kind: :context_direction}] =
             ContextBoundary.findings_for_edge(
               "lib/cadence/governance.ex",
               "lib/cadence/source_endpoints.ex",
               "runtime"
             )

    assert :telemetry == ContextBoundary.classify("lib/cadence/control/derived_telemetry.ex")
    assert :telemetry == ContextBoundary.classify("lib/cadence/control/ingress.ex")

    assert :comms ==
             ContextBoundary.classify(
               "lib/cadence/management/comms/source_endpoint_references.ex"
             )

    assert :catalog ==
             ContextBoundary.classify("lib/cadence/capabilities/definition_registry.ex")

    assert :platform ==
             ContextBoundary.classify(
               "lib/cadence/extensions/presentation/configuration_definition.ex"
             )

    assert :ground_networks ==
             ContextBoundary.classify("lib/cadence/contacts/provider_clients/definition.ex")

    assert [] ==
             ContextBoundary.findings_for_edge(
               "lib/cadence/contact_planning/fleet_planner.ex",
               "lib/cadence/contact_planning/fleet_repair_inputs.ex",
               "runtime"
             )

    assert [%{kind: :context_direction}] =
             ContextBoundary.findings_for_edge(
               "lib/cadence/contact_planning/fleet_planner.ex",
               "lib/cadence/contact_planning/fleet_repairs.ex",
               "runtime"
             )

    assert :contact_planning ==
             ContextBoundary.classify("lib/cadence/contact_planning/fleet_repair_inputs.ex")

    assert :contacts ==
             ContextBoundary.classify("lib/cadence/contact_planning/fleet_repairs.ex")
  end

  test "cross-plane callers use public resource boundaries, not owner internals" do
    assert [] ==
             PlaneBoundary.findings_for_edge(
               "lib/cadence/contact_planning/planner.ex",
               "lib/cadence/management/contacts/planning_results.ex",
               "runtime"
             )

    assert [%{kind: :plane_internal}] =
             PlaneBoundary.findings_for_edge(
               "lib/cadence/contact_planning/planner.ex",
               "lib/cadence/management/contacts/store/contact_planning_run_row.ex",
               "runtime"
             )

    assert [] ==
             PlaneBoundary.findings_for_edge(
               "lib/cadence/replay.ex",
               "lib/cadence/runtime/replay_session.ex",
               "runtime"
             )

    assert [] ==
             PlaneBoundary.findings_for_edge(
               "lib/cadence/control/ingress.ex",
               "lib/cadence/runtime/ingress.ex",
               "runtime"
             )

    assert [%{kind: :plane_internal}] =
             PlaneBoundary.findings_for_edge(
               "lib/cadence/replay.ex",
               "lib/cadence/runtime/partition_owner.ex",
               "runtime"
             )

    assert [] ==
             PlaneBoundary.findings_for_edge(
               "lib/cadence/governance.ex",
               "lib/cadence/capabilities/definition_registry.ex",
               "runtime"
             )

    assert [%{kind: :plane_direction}] =
             PlaneBoundary.findings_for_edge(
               "lib/cadence/governance.ex",
               "lib/cadence/capabilities/registry.ex",
               "runtime"
             )

    assert :shared == PlaneBoundary.classify("lib/cadence/capabilities/definition_registry.ex")
    assert :shared == PlaneBoundary.classify("lib/cadence/capabilities/descriptor.ex")

    assert :shared ==
             PlaneBoundary.classify("lib/cadence/applications/resource_claim_definition.ex")

    assert :shared ==
             PlaneBoundary.classify("lib/cadence/applications/preflight_report.ex")

    assert :shared ==
             PlaneBoundary.classify("lib/cadence/applications/status_placement.ex")

    assert :management ==
             PlaneBoundary.classify("lib/cadence/applications/application_preflight.ex")

    assert :management ==
             PlaneBoundary.classify(
               "lib/cadence/applications/application_preflights/telemetry_decom.ex"
             )

    assert :shared ==
             PlaneBoundary.classify("lib/cadence/capabilities/definitions/uplink_gateway.ex")

    assert [] ==
             PlaneBoundary.findings_for_edge(
               "lib/cadence/management/providers.ex",
               "lib/cadence/ground_networks/mission_providers.ex",
               "runtime"
             )

    assert [%{kind: :plane_direction}] =
             PlaneBoundary.findings_for_edge(
               "lib/cadence/management/providers.ex",
               "lib/cadence/ground_networks.ex",
               "runtime"
             )

    assert :management ==
             PlaneBoundary.classify("lib/cadence/ground_networks/mission_providers.ex")

    assert [] ==
             PlaneBoundary.findings_for_edge(
               "lib/cadence/management/commanding.ex",
               "lib/cadence/commanding/stage_store.ex",
               "runtime"
             )

    assert [] ==
             PlaneBoundary.findings_for_edge(
               "lib/cadence/management/commanding.ex",
               "lib/cadence/commanding/request_store.ex",
               "runtime"
             )

    assert [%{kind: :plane_direction}] =
             PlaneBoundary.findings_for_edge(
               "lib/cadence/management/commanding.ex",
               "lib/cadence/commanding.ex",
               "runtime"
             )

    assert :management == PlaneBoundary.classify("lib/cadence/commanding/request_store.ex")
    assert :management == PlaneBoundary.classify("lib/cadence/commanding/command_approval_row.ex")
  end

  test "web catch-all and resource-adapter migration debt are distinguished" do
    findings =
      DependencyBoundary.findings(%{
        "lib/cadence_web/controllers/command_request_controller.ex" => %{
          "lib/cadence_web/control_plane_params.ex" => "runtime"
        },
        "lib/cadence_web/api/catalog_params.ex" => %{
          "lib/cadence_web/control_plane_params/catalog.ex" => "runtime"
        }
      })

    assert [
             %{
               kind: :web_catch_all,
               source: "lib/cadence_web/controllers/command_request_controller.ex",
               sink: "lib/cadence_web/control_plane_params.ex"
             },
             %{
               kind: :web_legacy_adapter,
               source: "lib/cadence_web/api/catalog_params.ex",
               sink: "lib/cadence_web/control_plane_params/catalog.ex"
             }
           ] = findings
  end
end
