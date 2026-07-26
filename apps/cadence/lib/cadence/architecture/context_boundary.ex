defmodule Cadence.Architecture.ContextBoundary do
  @moduledoc """
  Enforces the bounded-context dependency matrix documented in
  `docs/architecture/context-dependency-policy.md`.

  Contexts describe business ownership, independently from the authority plane
  classification in `Cadence.Architecture.PlaneBoundary`. Every core source is
  assigned to a context; web adapters and the compatibility facade are outside
  the matrix.
  """

  alias Cadence.Architecture.PlaneBoundary

  @contexts [
    :identity,
    :catalog,
    :comms,
    :ground_networks,
    :contact_planning,
    :contacts,
    :commanding,
    :runtime,
    :telemetry,
    :dashboards,
    :read_models,
    :platform
  ]

  @file_context_overrides %{
    "lib/cadence/application.ex" => :composition,
    "lib/cadence/extension_catalog.ex" => :composition,
    "lib/cadence/jobs.ex" => :platform,
    "lib/cadence/jobs/runner.ex" => :composition,
    "lib/cadence/jobs/worker.ex" => :composition,
    "lib/cadence/jobs/dispatcher.ex" => :composition,
    "lib/cadence/jobs/supervisor.ex" => :composition,
    "lib/cadence/observability.ex" => :adapter,
    "lib/cadence/persistence.ex" => :platform,
    "lib/cadence/management/supervisor.ex" => :composition,
    "lib/cadence/control/supervisor.ex" => :composition,
    "lib/cadence/platform/supervisor.ex" => :composition,
    "lib/cadence/projections/supervisor.ex" => :composition,
    "lib/cadence/persistence/organization_scope.ex" => :adapter,
    "lib/cadence/application_dispatch/binding_rule.ex" => :catalog,
    "lib/cadence/application_dispatch/binding_set.ex" => :catalog,
    "lib/cadence/application_dispatch/capability_config.ex" => :catalog,
    "lib/cadence/application_dispatch/capability_instance.ex" => :catalog,
    "lib/cadence/application_dispatch/selector.ex" => :catalog,
    "lib/cadence/application_dispatch/selector_match.ex" => :catalog,
    "lib/cadence/application_dispatch/selector_scope.ex" => :catalog,
    "lib/cadence/capabilities/definition_registry.ex" => :catalog,
    "lib/cadence/capabilities/descriptor.ex" => :catalog,
    "lib/cadence/capabilities/family.ex" => :catalog,
    "lib/cadence/capabilities/transport_extensions/uplink_gateway/configuration.ex" => :catalog,
    "lib/cadence/capabilities/validation_context.ex" => :catalog,
    "lib/cadence/commanding/encoder.ex" => :runtime,
    "lib/cadence/contacts/combined_downlink_record.ex" => :runtime,
    "lib/cadence/contacts/downlink_diagnostic.ex" => :runtime,
    "lib/cadence/contacts/downlink_observation.ex" => :runtime,
    "lib/cadence/contacts/link_assignment.ex" => :comms,
    "lib/cadence/contacts/path.ex" => :comms,
    "lib/cadence/contacts/path_template.ex" => :comms,
    "lib/cadence/contacts/provider_binding.ex" => :comms,
    "lib/cadence/contacts/provider_profile.ex" => :comms,
    "lib/cadence/contacts/transport_binding.ex" => :comms,
    "lib/cadence/contacts/transport_profile.ex" => :comms,
    "lib/cadence/contacts/provider_clients/registry.ex" => :ground_networks,
    "lib/cadence/contacts/provider_clients/simulator_http.ex" => :ground_networks,
    "lib/cadence/contacts/provider_client.ex" => :ground_networks,
    "lib/cadence/contacts/provider_scheduling.ex" => :ground_networks,
    "lib/cadence/contacts/known_atom.ex" => :adapter,
    "lib/cadence/contact_planning/contact_plan_executions.ex" => :contacts,
    "lib/cadence/contact_planning/fleet_automation.ex" => :contacts,
    "lib/cadence/contact_planning/fleet_automation_actions.ex" => :contacts,
    "lib/cadence/contact_planning/fleet_repairs.ex" => :contacts,
    "lib/cadence/control/contact_fact_consumer.ex" => :commanding,
    "lib/cadence/control/derived_telemetry.ex" => :telemetry,
    "lib/cadence/control/ingress.ex" => :telemetry,
    "lib/cadence/control/runtime_fact_consumer.ex" => :commanding,
    "lib/cadence/control/mission_runtime.ex" => :runtime,
    "lib/cadence/management/data_sources.ex" => :dashboards,
    "lib/cadence/management/data_sources/execution_policy.ex" => :dashboards,
    "lib/cadence/management/data_sources/lifecycle.ex" => :dashboards,
    "lib/cadence/management/transports.ex" => :composition,
    "lib/cadence/projections/data_source_bindings.ex" => :dashboards,
    "lib/cadence/projections/data_source_health.ex" => :dashboards,
    "lib/cadence/derived_telemetry/definition.ex" => :catalog,
    "lib/cadence/derived_telemetry/expression_evaluator.ex" => :catalog,
    "lib/cadence/derived_telemetry/expression_parser.ex" => :catalog,
    "lib/cadence/cfdp/transaction_event.ex" => :telemetry,
    "lib/cadence/dashboards/secret_metadata.ex" => :platform,
    "lib/cadence/dashboards/runtime_cache.ex" => :adapter,
    "lib/cadence/dashboards/runtime_invalidation.ex" => :adapter,
    "lib/cadence/dashboards/runtime_invalidation/event.ex" => :adapter,
    "lib/cadence/dashboards/source_watermarks.ex" => :adapter,
    "lib/cadence/dashboards/telemetry_revision_summary.ex" => :adapter,
    "lib/cadence/ingress/raw_evidence.ex" => :comms,
    "lib/cadence/telemetry/field_definition.ex" => :catalog,
    "lib/cadence/telemetry/packet_definition.ex" => :catalog,
    "lib/cadence/telemetry/handlers/definition_bound_telemetry_handler.ex" => :runtime,
    "lib/cadence/telemetry/profiler.ex" => :adapter,
    "lib/cadence/provider_adapters.ex" => :runtime
  }

  @prefix_context_overrides [
    adapter: [
      "lib/cadence/operational_events.ex",
      "lib/cadence/operational_events/"
    ],
    composition: [
      "lib/cadence/observability/metrics/"
    ],
    runtime: [
      "lib/cadence/action_requests/",
      "lib/cadence/provider_adapters/"
    ],
    platform: [
      "lib/cadence/extensions/presentation/"
    ],
    catalog: [
      "lib/cadence/capabilities/definitions/",
      "lib/cadence/extensions/"
    ],
    ground_networks: [
      "lib/cadence/contacts/provider_clients/"
    ],
    comms: [
      "lib/cadence/contacts/link_assignment_store",
      "lib/cadence/contacts/path_template_store",
      "lib/cadence/contacts/profile_store"
    ],
    read_models: [
      "lib/cadence/mission_events/",
      "lib/cadence/operational_events.ex",
      "lib/cadence/operational_events/",
      "lib/cadence/ops/",
      "lib/cadence/projections/",
      "lib/cadence/reads/"
    ]
  ]

  @context_paths [
    identity: [
      "lib/cadence/accounts.ex",
      "lib/cadence/accounts/",
      "lib/cadence/auth.ex",
      "lib/cadence/auth/",
      "lib/cadence/missions.ex",
      "lib/cadence/missions/",
      "lib/cadence/organizations.ex",
      "lib/cadence/organizations/",
      "lib/cadence/spacecraft.ex",
      "lib/cadence/spacecraft_store.ex",
      "lib/cadence/spacecraft_store/",
      "lib/cadence/spacecraft_type.ex",
      "lib/cadence/spacecraft_type_store.ex",
      "lib/cadence/spacecraft_type_store/"
    ],
    catalog: [
      "lib/cadence/activations.ex",
      "lib/cadence/activations/",
      "lib/cadence/catalog.ex",
      "lib/cadence/catalog/",
      "lib/cadence/governance.ex",
      "lib/cadence/governance/"
    ],
    comms: [
      "lib/cadence/comms/",
      "lib/cadence/source_endpoints.ex",
      "lib/cadence/source_endpoints/"
    ],
    ground_networks: [
      "lib/cadence/ground_networks.ex",
      "lib/cadence/ground_networks/",
      "lib/cadence/provider_adapters.ex",
      "lib/cadence/provider_adapters/"
    ],
    contact_planning: ["lib/cadence/contact_planning/"],
    contacts: ["lib/cadence/contacts.ex", "lib/cadence/contacts/"],
    commanding: [
      "lib/cadence/action_requests/",
      "lib/cadence/commanding.ex",
      "lib/cadence/commanding/"
    ],
    runtime: [
      "lib/cadence/application_dispatch/",
      "lib/cadence/applications/",
      "lib/cadence/capabilities/",
      "lib/cadence/runtime.ex",
      "lib/cadence/runtime/"
    ],
    telemetry: [
      "lib/cadence/ccsds/",
      "lib/cadence/derived_telemetry.ex",
      "lib/cadence/derived_telemetry/",
      "lib/cadence/ingress/",
      "lib/cadence/ingress_archive.ex",
      "lib/cadence/ingress_archive/",
      "lib/cadence/limits.ex",
      "lib/cadence/limits/",
      "lib/cadence/protocol/",
      "lib/cadence/replay.ex",
      "lib/cadence/replay/",
      "lib/cadence/telemetry/"
    ],
    dashboards: ["lib/cadence/dashboards.ex", "lib/cadence/dashboards/"],
    platform: [
      "lib/cadence/application.ex",
      "lib/cadence/architecture/",
      "lib/cadence/dev_profile.ex",
      "lib/cadence/ids.ex",
      "lib/cadence/jobs.ex",
      "lib/cadence/jobs/",
      "lib/cadence/listing.ex",
      "lib/cadence/notifications.ex",
      "lib/cadence/notifications/",
      "lib/cadence/observability.ex",
      "lib/cadence/observability/",
      "lib/cadence/persistence/",
      "lib/cadence/platform.ex",
      "lib/cadence/platform/",
      "lib/cadence/repo.ex",
      "lib/cadence/secrets/"
    ]
  ]

  @plane_context_paths [
    identity: [
      "lib/cadence/management/identity",
      "lib/cadence/management/missions"
    ],
    catalog: [
      "lib/cadence/management/activations",
      "lib/cadence/control/activations"
    ],
    comms: ["lib/cadence/management/comms"],
    ground_networks: [
      "lib/cadence/management/providers",
      "lib/cadence/control/providers"
    ],
    contact_planning: ["lib/cadence/management/contacts"],
    contacts: ["lib/cadence/control/contacts"],
    commanding: [
      "lib/cadence/management/commanding",
      "lib/cadence/control/commanding"
    ],
    runtime: [
      "lib/cadence/control/mission",
      "lib/cadence/control/runtime",
      "lib/cadence/control/missions"
    ],
    telemetry: ["lib/cadence/control/replay"],
    dashboards: [
      "lib/cadence/management/managed_resources",
      "lib/cadence/control/managed_resources"
    ],
    platform: [
      "lib/cadence/management/supervisor.ex",
      "lib/cadence/control/supervisor.ex"
    ]
  ]

  @allowed %{
    identity: [:platform],
    catalog: [:identity, :platform],
    comms: [:identity, :catalog, :platform],
    ground_networks: [:identity, :comms, :platform],
    contact_planning: [:identity, :catalog, :comms, :ground_networks, :platform],
    contacts: [
      :identity,
      :comms,
      :ground_networks,
      :contact_planning,
      :runtime,
      :platform
    ],
    commanding: [:identity, :catalog, :comms, :contacts, :runtime, :telemetry, :platform],
    runtime: [:identity, :catalog, :comms, :telemetry, :platform],
    telemetry: [:identity, :catalog, :comms, :platform],
    dashboards: @contexts,
    read_models: @contexts,
    platform: [:platform],
    composition: @contexts ++ [:composition, :adapter],
    adapter: @contexts ++ [:composition, :adapter]
  }

  # Cross-context orchestration remains explicit even when the general matrix
  # points the other way. These are named vertical handoffs through a public
  # service, not permission for arbitrary reverse dependencies.
  @public_orchestration_edges MapSet.new([
                                {"lib/cadence/control/activations.ex",
                                 "lib/cadence/control/mission_runtime_reconciler.ex"},
                                {"lib/cadence/control/activations.ex",
                                 "lib/cadence/control/missions.ex"},
                                {"lib/cadence/control/mission_runtime.ex",
                                 "lib/cadence/contacts/scheduler.ex"},
                                {"lib/cadence/ground_networks/provider_event_processor.ex",
                                 "lib/cadence/control/contacts/provider_events.ex"},
                                {"lib/cadence/control/providers.ex",
                                 "lib/cadence/control/contacts/provider_grants.ex"},
                                {"lib/cadence/governance.ex",
                                 "lib/cadence/management/comms/source_endpoint_references.ex"}
                              ])

  @type context ::
          :identity
          | :catalog
          | :comms
          | :ground_networks
          | :contact_planning
          | :contacts
          | :commanding
          | :runtime
          | :telemetry
          | :dashboards
          | :read_models
          | :platform
          | :composition
          | :adapter

  @type finding :: %{
          required(:kind) => :context_direction,
          required(:source) => String.t(),
          required(:sink) => String.t(),
          required(:label) => String.t(),
          required(:fingerprint) => String.t()
        }

  @spec findings_for_edge(String.t(), String.t(), term()) :: [finding()]
  def findings_for_edge(source, sink, label) do
    with source_context when not is_nil(source_context) <- classify(source),
         sink_context when not is_nil(sink_context) <- classify(sink),
         false <- source_context == sink_context,
         false <- source_context == :adapter or sink_context == :adapter,
         false <- MapSet.member?(@public_orchestration_edges, {source, sink}),
         false <- adjacent_plane_handoff?(source, sink),
         false <- sink_context in Map.fetch!(@allowed, source_context) do
      [finding(source, source_context, sink, sink_context, label)]
    else
      _allowed_or_external -> []
    end
  end

  @spec classify(String.t()) :: context() | nil
  def classify(path) when is_binary(path) do
    cond do
      path == "lib/cadence.ex" or String.starts_with?(path, "lib/cadence_web/") ->
        nil

      context = Map.get(@file_context_overrides, path) ->
        context

      context = classify_from_paths(path, @prefix_context_overrides) ->
        context

      context = classify_from_paths(path, @plane_context_paths) ->
        context

      context = classify_from_paths(path, @context_paths) ->
        context

      true ->
        nil
    end
  end

  defp finding(source, source_context, sink, sink_context, label) do
    %{
      kind: :context_direction,
      source: source,
      sink: sink,
      label: "#{label}; #{source_context} -> #{sink_context}",
      fingerprint: Enum.join([:context_direction, source, sink], "|")
    }
  end

  defp adjacent_plane_handoff?(source, sink) do
    source_plane = PlaneBoundary.classify(source)
    sink_plane = PlaneBoundary.classify(sink)

    source_plane in [:management, :control, :data, :projections] and
      sink_plane in [:management, :control, :data, :projections] and
      source_plane != sink_plane
  end

  defp classify_from_paths(path, paths) do
    Enum.find_value(paths, fn {context, prefixes} ->
      if Enum.any?(prefixes, &path_matches?(path, &1)), do: context
    end)
  end

  defp path_matches?(path, prefix), do: path == prefix or String.starts_with?(path, prefix)
end
