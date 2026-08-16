defmodule Cadence.Architecture.PlaneBoundary do
  @moduledoc """
  Classifies plane-owned source paths and enforces ADR-015 dependency direction.

  Plane-prefixed and authoritative domain namespaces are classified directly.
  Remaining core modules are explicitly `:shared`; shared code may be consumed
  by planes but may not reach back into an authoritative plane. Web and
  observability are adapter boundaries, application startup is the composition
  root, and the historical root facade is an isolated compatibility boundary
  whose production callers are rejected separately.
  """

  @plane_paths [
    management: ["lib/cadence/management.ex", "lib/cadence/management/"],
    control: ["lib/cadence/control.ex", "lib/cadence/control/"],
    data: ["lib/cadence/runtime.ex", "lib/cadence/runtime/"],
    projections: ["lib/cadence/projections.ex", "lib/cadence/projections/"],
    platform: ["lib/cadence/platform.ex", "lib/cadence/platform/"]
  ]

  @domain_plane_paths [
    management: [
      "lib/cadence/accounts.ex",
      "lib/cadence/accounts/",
      "lib/cadence/auth.ex",
      "lib/cadence/auth/",
      "lib/cadence/catalog.ex",
      "lib/cadence/catalog/",
      "lib/cadence/comms/",
      "lib/cadence/contact_planning/",
      "lib/cadence/governance.ex",
      "lib/cadence/governance/",
      "lib/cadence/missions.ex",
      "lib/cadence/missions/",
      "lib/cadence/mission_models.ex",
      "lib/cadence/mission_models/",
      "lib/cadence/organizations.ex",
      "lib/cadence/organizations/",
      "lib/cadence/source_endpoints.ex",
      "lib/cadence/source_endpoints/",
      "lib/cadence/spacecraft.ex",
      "lib/cadence/spacecraft_store.ex",
      "lib/cadence/spacecraft_store/",
      "lib/cadence/spacecraft_type.ex",
      "lib/cadence/spacecraft_type_store.ex",
      "lib/cadence/spacecraft_type_store/"
    ],
    control: [
      "lib/cadence/activations.ex",
      "lib/cadence/activations/",
      "lib/cadence/commanding.ex",
      "lib/cadence/commanding/",
      "lib/cadence/contacts.ex",
      "lib/cadence/contacts/",
      "lib/cadence/ground_networks.ex",
      "lib/cadence/ground_networks/",
      "lib/cadence/replay.ex",
      "lib/cadence/replay/"
    ],
    data: [
      "lib/cadence/action_requests/",
      "lib/cadence/application_dispatch/",
      "lib/cadence/applications/",
      "lib/cadence/capabilities/",
      "lib/cadence/derived_telemetry.ex",
      "lib/cadence/derived_telemetry/",
      "lib/cadence/ingress/",
      "lib/cadence/ingress_archive.ex",
      "lib/cadence/ingress_archive/",
      "lib/cadence/ingress_journal/",
      "lib/cadence/limits.ex",
      "lib/cadence/limits/",
      "lib/cadence/operational_events.ex",
      "lib/cadence/operational_events/",
      "lib/cadence/protocol/",
      "lib/cadence/provider_adapters.ex",
      "lib/cadence/provider_adapters/",
      "lib/cadence/semantic_observations.ex",
      "lib/cadence/semantic_observations/",
      "lib/cadence/semantic_runtime.ex",
      "lib/cadence/semantic_runtime/",
      "lib/cadence/telemetry/"
    ],
    projections: [
      "lib/cadence/dashboards.ex",
      "lib/cadence/dashboards/",
      "lib/cadence/mission_events/",
      "lib/cadence/ops/",
      "lib/cadence/reads/"
    ],
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
      "lib/cadence/repo.ex",
      "lib/cadence/secrets/"
    ]
  ]

  @plane_file_overrides %{
    "lib/cadence/application.ex" => :composition,
    "lib/cadence/extension_catalog.ex" => :composition,
    "lib/cadence/persistence/organization_scope.ex" => :adapter,
    "lib/cadence/jobs.ex" => :platform,
    "lib/cadence/jobs/runner.ex" => :composition,
    "lib/cadence/jobs/dispatcher.ex" => :composition,
    "lib/cadence/jobs/supervisor.ex" => :composition,
    "lib/cadence/data_sources/probe_scheduler.ex" => :composition,
    "lib/cadence/observability.ex" => :adapter,
    "lib/cadence/persistence.ex" => :platform,
    "lib/cadence/applications/action_confirmation.ex" => :shared,
    "lib/cadence/applications/action_definition.ex" => :shared,
    "lib/cadence/applications/action_failure.ex" => :shared,
    "lib/cadence/applications/action_provider.ex" => :shared,
    "lib/cadence/applications/action_request.ex" => :shared,
    "lib/cadence/applications/application_dependency.ex" => :shared,
    "lib/cadence/applications/application_definition.ex" => :shared,
    "lib/cadence/applications/application_installation.ex" => :shared,
    "lib/cadence/applications/application_installation/lifecycle_event.ex" => :management,
    "lib/cadence/applications/application_installations.ex" => :management,
    "lib/cadence/applications/application_installations/installation_row.ex" => :management,
    "lib/cadence/applications/application_installations/lifecycle_event_row.ex" => :management,
    "lib/cadence/applications/application_preflight.ex" => :management,
    "lib/cadence/applications/application_preflights/provider.ex" => :management,
    "lib/cadence/applications/application_preflights/telemetry_decom.ex" => :management,
    "lib/cadence/applications/action_dispatcher.ex" => :management,
    "lib/cadence/applications/configuration_reference.ex" => :shared,
    "lib/cadence/applications/derived_telemetry/action_provider.ex" => :management,
    "lib/cadence/applications/limits/action_provider.ex" => :adapter,
    "lib/cadence/applications/host_context.ex" => :shared,
    "lib/cadence/applications/lifecycle_action_definition.ex" => :shared,
    "lib/cadence/applications/lifecycle_actions.ex" => :shared,
    "lib/cadence/applications/lifecycle_contract.ex" => :shared,
    "lib/cadence/applications/preflight_check.ex" => :shared,
    "lib/cadence/applications/preflight_report.ex" => :shared,
    "lib/cadence/applications/registry.ex" => :shared,
    "lib/cadence/applications/resource_claim_definition.ex" => :shared,
    "lib/cadence/applications/resource_contract.ex" => :shared,
    "lib/cadence/applications/status.ex" => :shared,
    "lib/cadence/applications/status_placement.ex" => :shared,
    "lib/cadence/applications/surface_definition.ex" => :shared,
    "lib/cadence/applications/surface_document.ex" => :shared,
    "lib/cadence/applications/surface_query_request.ex" => :shared,
    "lib/cadence/applications/surface_elements/activity.ex" => :shared,
    "lib/cadence/applications/surface_elements/activity_item.ex" => :shared,
    "lib/cadence/applications/surface_elements/diagnostic.ex" => :shared,
    "lib/cadence/applications/surface_elements/diagnostics.ex" => :shared,
    "lib/cadence/applications/surface_elements/generated_form.ex" => :shared,
    "lib/cadence/applications/surface_elements/stat.ex" => :shared,
    "lib/cadence/applications/surface_elements/table.ex" => :shared,
    "lib/cadence/applications/telemetry_decom.ex" => :management,
    "lib/cadence/applications/telemetry_decom/action_provider.ex" => :management,
    "lib/cadence/applications/telemetry_decom/apid_selection.ex" => :management,
    "lib/cadence/applications/telemetry_decom/config.ex" => :management,
    "lib/cadence/application_dispatch/binding_rule.ex" => :shared,
    "lib/cadence/application_dispatch/binding_set.ex" => :shared,
    "lib/cadence/application_dispatch/capability_config.ex" => :shared,
    "lib/cadence/application_dispatch/capability_instance.ex" => :shared,
    "lib/cadence/application_dispatch/selector.ex" => :shared,
    "lib/cadence/application_dispatch/selector_match.ex" => :shared,
    "lib/cadence/application_dispatch/selector_scope.ex" => :shared,
    "lib/cadence/capabilities/definition_registry.ex" => :shared,
    "lib/cadence/capabilities/descriptor.ex" => :shared,
    "lib/cadence/capabilities/registry.ex" => :data,
    "lib/cadence/capabilities/transport_extensions/uplink_gateway/configuration.ex" => :shared,
    "lib/cadence/capabilities/validation_context.ex" => :shared,
    "lib/cadence/catalog/ids.ex" => :shared,
    "lib/cadence/catalog/command/compiler/argument_spec.ex" => :shared,
    "lib/cadence/catalog/command/compiler/encoding_step.ex" => :shared,
    "lib/cadence/catalog/command/compiler/runtime_definition.ex" => :shared,
    "lib/cadence/catalog/command/type_encoding.ex" => :shared,
    "lib/cadence/catalog/command/normalize.ex" => :shared,
    "lib/cadence/commanding/command_approval.ex" => :management,
    "lib/cadence/commanding/command_approval_row.ex" => :management,
    "lib/cadence/commanding/command_queue_entry.ex" => :control,
    "lib/cadence/commanding/command_release_attempt.ex" => :control,
    "lib/cadence/commanding/command_request.ex" => :management,
    "lib/cadence/commanding/command_stage.ex" => :management,
    "lib/cadence/commanding/command_request_row.ex" => :management,
    "lib/cadence/commanding/command_stage_row.ex" => :management,
    "lib/cadence/commanding/lifecycle_policy.ex" => :management,
    "lib/cadence/commanding/request_store.ex" => :management,
    "lib/cadence/commanding/request_validation.ex" => :management,
    "lib/cadence/commanding/staged_command_item_row.ex" => :management,
    "lib/cadence/commanding/command_verifier_instance.ex" => :control,
    "lib/cadence/commanding/dispatch_supervisor.ex" => :control,
    "lib/cadence/commanding/dispatcher.ex" => :control,
    "lib/cadence/commanding/encoder.ex" => :data,
    "lib/cadence/commanding/lane_dispatcher.ex" => :control,
    "lib/cadence/commanding/release_artifacts.ex" => :control,
    "lib/cadence/commanding/release_store.ex" => :control,
    "lib/cadence/commanding/release_target_selection.ex" => :control,
    "lib/cadence/commanding/stage_store.ex" => :management,
    "lib/cadence/commanding/staged_command_item.ex" => :management,
    "lib/cadence/commanding/verifier_evaluation.ex" => :control,
    "lib/cadence/commanding/verifier_scheduler.ex" => :control,
    "lib/cadence/commanding/verifier_store.ex" => :control,
    "lib/cadence/commanding/verifier_transport_signals.ex" => :control,
    "lib/cadence/commanding/verifier_workflow.ex" => :control,
    "lib/cadence/contact_planning/automation_grants.ex" => :management,
    "lib/cadence/contact_planning/contact_plan.ex" => :management,
    "lib/cadence/contact_planning/contact_plan_approval.ex" => :management,
    "lib/cadence/contact_planning/contact_plan_approvals.ex" => :management,
    "lib/cadence/contact_planning/contact_plan_execution_item.ex" => :control,
    "lib/cadence/contact_planning/contact_plan_executions.ex" => :control,
    "lib/cadence/contact_planning/contact_plan_version.ex" => :management,
    "lib/cadence/contact_planning/contact_plans.ex" => :management,
    "lib/cadence/contact_planning/contact_requirement_templates.ex" => :management,
    "lib/cadence/contact_planning/contact_requirements.ex" => :management,
    "lib/cadence/contact_planning/fleet_automation_actions.ex" => :control,
    "lib/cadence/contact_planning/fleet_planning_policies.ex" => :management,
    "lib/cadence/contact_planning/fleet_planning_runs.ex" => :management,
    "lib/cadence/contact_planning/fleet_automation.ex" => :control,
    "lib/cadence/contact_planning/fleet_planner.ex" => :control,
    "lib/cadence/contact_planning/fleet_repair_inputs.ex" => :control,
    "lib/cadence/contact_planning/fleet_repairs.ex" => :control,
    "lib/cadence/contact_planning/planner.ex" => :control,
    "lib/cadence/contact_planning/policy_narrowing.ex" => :management,
    "lib/cadence/contacts/combined_downlink_record.ex" => :data,
    "lib/cadence/contacts/downlink_diagnostic.ex" => :data,
    "lib/cadence/contacts/downlink_observation.ex" => :data,
    "lib/cadence/contacts/link_assignment.ex" => :management,
    "lib/cadence/contacts/path.ex" => :management,
    "lib/cadence/contacts/path_template.ex" => :management,
    "lib/cadence/contacts/provider_binding.ex" => :management,
    "lib/cadence/contacts/provider_profile.ex" => :management,
    "lib/cadence/contacts/transport_binding.ex" => :management,
    "lib/cadence/contacts/transport_profile.ex" => :management,
    "lib/cadence/contacts/known_atom.ex" => :adapter,
    "lib/cadence/ground_networks/delivery_policy.ex" => :shared,
    "lib/cadence/ground_networks/provider_audit.ex" => :management,
    "lib/cadence/ground_networks/provider_audit_entry.ex" => :management,
    "lib/cadence/ground_networks/provider_audit/entry_row.ex" => :management,
    "lib/cadence/ground_networks/provider_audit_references.ex" => :management,
    "lib/cadence/ground_networks/provider_error.ex" => :shared,
    "lib/cadence/ground_networks/validation.ex" => :shared,
    "lib/cadence/ingress/raw_evidence.ex" => :shared,
    "lib/cadence/cfdp/transaction_event.ex" => :shared,
    "lib/cadence/derived_telemetry/definition.ex" => :shared,
    "lib/cadence/derived_telemetry/expression_evaluator.ex" => :shared,
    "lib/cadence/derived_telemetry/expression_parser.ex" => :shared,
    "lib/cadence/derived_telemetry/store.ex" => :data,
    "lib/cadence/reads/derived_telemetry.ex" => :projections,
    "lib/cadence/limits/store.ex" => :data,
    "lib/cadence/reads/limits.ex" => :projections,
    "lib/cadence/telemetry/current_value_store.ex" => :data,
    "lib/cadence/telemetry/sample_records.ex" => :data,
    "lib/cadence/reads/mission_events.ex" => :projections,
    "lib/cadence/reads/replay.ex" => :projections,
    "lib/cadence/replay/diff.ex" => :projections,
    "lib/cadence/replay/scope.ex" => :shared,
    "lib/cadence/telemetry/field_definition.ex" => :shared,
    "lib/cadence/telemetry/packet_definition.ex" => :shared,
    "lib/cadence/dashboards/source_execution_policy.ex" => :projections,
    "lib/cadence/dashboards/planned_source_request.ex" => :projections,
    "lib/cadence/dashboards/resolved_source_binding.ex" => :projections,
    "lib/cadence/dashboards/runtime_cache_key.ex" => :projections,
    "lib/cadence/dashboards/runtime_cache.ex" => :adapter,
    "lib/cadence/dashboards/runtime_invalidation.ex" => :adapter,
    "lib/cadence/dashboards/runtime_invalidation/event.ex" => :adapter,
    "lib/cadence/dashboards/telemetry_revision_summary.ex" => :adapter,
    "lib/cadence/dashboards/sources/telemetry.ex" => :adapter,
    "lib/cadence/operational_events.ex" => :adapter,
    "lib/cadence/operational_events/event.ex" => :adapter,
    "lib/cadence/jobs/worker.ex" => :composition
  }

  @plane_prefix_overrides [
    shared: [
      "lib/cadence/ccsds/",
      "lib/cadence/capabilities/definitions/",
      "lib/cadence/data_sources/",
      "lib/cadence/extensions/"
    ],
    composition: [
      "lib/cadence/smoke/"
    ],
    adapter: [
      "lib/cadence/operational_events/"
    ],
    management: [
      "lib/cadence/applications/application_binding.ex",
      "lib/cadence/applications/application_binding_store",
      "lib/cadence/contacts/link_assignment_store",
      "lib/cadence/contacts/path_template_store",
      "lib/cadence/contacts/profile_store",
      "lib/cadence/ground_networks/mission_provider.ex",
      "lib/cadence/ground_networks/mission_providers",
      "lib/cadence/ground_networks/provider_account.ex",
      "lib/cadence/ground_networks/provider_account_grant.ex",
      "lib/cadence/ground_networks/provider_account_grants",
      "lib/cadence/ground_networks/provider_account_version.ex",
      "lib/cadence/ground_networks/provider_accounts",
      "lib/cadence/ground_networks/provider_credential.ex",
      "lib/cadence/ground_networks/provider_credentials"
    ],
    control: [
      "lib/cadence/contacts/provider_booking.ex",
      "lib/cadence/contacts/provider_change_approval.ex",
      "lib/cadence/contacts/provider_change_approvals.ex",
      "lib/cadence/contacts/provider_client.ex",
      "lib/cadence/contacts/provider_clients",
      "lib/cadence/contacts/provider_reservation.ex",
      "lib/cadence/contacts/provider_reservation_change.ex",
      "lib/cadence/contacts/provider_reservation_changes.ex",
      "lib/cadence/contacts/provider_reservation_reconciler.ex",
      "lib/cadence/contacts/provider_reservations.ex",
      "lib/cadence/contacts/provider_scheduling.ex",
      "lib/cadence/ground_networks/provider_event",
      "lib/cadence/ground_networks/provider_evidence"
    ],
    data: [
      "lib/cadence/derived_telemetry/store/",
      "lib/cadence/limits/store/",
      "lib/cadence/telemetry/current_value_store/",
      "lib/cadence/telemetry/sample_records/"
    ]
  ]

  @allowed_directions MapSet.new([
                        {:management, :platform},
                        {:management, :shared},
                        {:control, :management},
                        {:control, :data},
                        {:control, :platform},
                        {:control, :shared},
                        {:data, :platform},
                        {:data, :shared},
                        {:projections, :management},
                        {:projections, :control},
                        {:projections, :data},
                        {:projections, :platform},
                        {:projections, :shared},
                        {:platform, :shared},
                        {:shared, :platform},
                        {:web, :management},
                        {:web, :control},
                        {:web, :data},
                        {:web, :projections},
                        {:web, :platform},
                        {:web, :shared}
                      ])

  # Cross-plane public boundaries are deliberately explicit. Add an entry only
  # when the owning plane intends the module to be consumed across the boundary.
  @public_cross_plane_sinks MapSet.new([
                              "lib/cadence/control/activations.ex",
                              "lib/cadence/control/activations/activation_execution.ex",
                              "lib/cadence/applications/telemetry_decom.ex",
                              "lib/cadence/management/activations/approved_activation.ex",
                              "lib/cadence/management/activations/activation_request.ex",
                              "lib/cadence/management/activations.ex",
                              "lib/cadence/management/commanding/approved_command.ex",
                              "lib/cadence/management/commanding.ex",
                              "lib/cadence/commanding/command_request.ex",
                              "lib/cadence/management/contacts.ex",
                              "lib/cadence/management/contacts/approved_contact_plan.ex",
                              "lib/cadence/management/contacts/planning_results.ex",
                              "lib/cadence/control/contacts.ex",
                              "lib/cadence/management/providers.ex",
                              "lib/cadence/management/providers/provider_configuration.ex",
                              "lib/cadence/control/providers.ex",
                              "lib/cadence/control/replay/store.ex",
                              "lib/cadence/ground_networks/mission_provider.ex",
                              "lib/cadence/ground_networks/mission_providers.ex",
                              "lib/cadence/ground_networks/provider_account_grants.ex",
                              "lib/cadence/ground_networks/provider_account_version.ex",
                              "lib/cadence/ground_networks/provider_accounts.ex",
                              "lib/cadence/management/managed_resources.ex",
                              "lib/cadence/management/managed_resources/managed_resource_request.ex",
                              "lib/cadence/management/data_sources.ex",
                              "lib/cadence/control/managed_resources.ex",
                              "lib/cadence/projections/data_sources/health.ex",
                              "lib/cadence/projections/data_source_bindings.ex",
                              "lib/cadence/platform/content_hash.ex",
                              "lib/cadence/runtime/generation_applied.ex",
                              "lib/cadence/runtime/contacts.ex",
                              "lib/cadence/runtime/ingress.ex",
                              "lib/cadence/projections/contact_status.ex",
                              "lib/cadence/runtime/commanding.ex",
                              "lib/cadence/runtime/mission_runtime_spec.ex",
                              "lib/cadence/runtime/missions.ex",
                              "lib/cadence/runtime/replay_session.ex",
                              "lib/cadence/runtime/realized_contact_runtime_spec.ex",
                              "lib/cadence/runtime/transmit_command.ex",
                              "lib/cadence/runtime/transport_action_request.ex",
                              "lib/cadence/runtime/transport_capability_record.ex",
                              "lib/cadence/runtime/transport_records.ex",
                              "lib/cadence/runtime/downlink_records.ex",
                              "lib/cadence/runtime/managed_records.ex",
                              "lib/cadence/runtime/managed_action_request.ex",
                              "lib/cadence/runtime/managed_capability_record.ex",
                              "lib/cadence/runtime/managed_timer_event.ex",
                              "lib/cadence/runtime/facts.ex",
                              "lib/cadence/runtime/processing_results_persisted.ex",
                              "lib/cadence/runtime/transport_records_persisted.ex",
                              "lib/cadence/runtime/downlink_records_persisted.ex",
                              "lib/cadence/runtime/managed_records_persisted.ex",
                              "lib/cadence/derived_telemetry/store.ex",
                              "lib/cadence/limits/store.ex",
                              "lib/cadence/telemetry/current_value_store.ex",
                              "lib/cadence/telemetry/sample_records.ex"
                            ])

  @type plane ::
          :management
          | :control
          | :data
          | :projections
          | :platform
          | :shared
          | :web
          | :adapter
          | :composition
          | :compatibility

  @type finding :: %{
          required(:kind) => :plane_direction | :plane_internal,
          required(:source) => String.t(),
          required(:sink) => String.t(),
          required(:label) => String.t(),
          required(:fingerprint) => String.t()
        }

  @spec findings_for_edge(String.t(), String.t(), term()) :: [finding()]
  def findings_for_edge(source, sink, label) do
    with source_plane when not is_nil(source_plane) <- classify(source),
         sink_plane when not is_nil(sink_plane) <- classify(sink),
         false <- source_plane == sink_plane do
      cross_plane_findings(source, source_plane, sink, sink_plane, label)
    else
      _same_or_unclassified -> []
    end
  end

  @spec classify(String.t()) :: plane() | nil
  def classify(path) when is_binary(path) do
    cond do
      path == "lib/cadence.ex" ->
        :compatibility

      String.starts_with?(path, "lib/cadence_web/") ->
        :adapter

      String.starts_with?(path, "lib/cadence/observability/") ->
        :adapter

      true ->
        Map.get(@plane_file_overrides, path) ||
          classify_from_paths(path, @plane_prefix_overrides) ||
          classify_from_paths(path, @plane_paths) ||
          classify_from_paths(path, @domain_plane_paths)
    end
  end

  defp cross_plane_findings(source, source_plane, sink, sink_plane, label) do
    direction = {source_plane, sink_plane}

    cond do
      source_plane in [:adapter, :composition, :compatibility] or
          sink_plane == :compatibility ->
        []

      sink_plane == :adapter ->
        []

      not MapSet.member?(@allowed_directions, direction) ->
        [finding(:plane_direction, source, source_plane, sink, sink_plane, label)]

      sink_plane in [:platform, :shared] ->
        []

      formal_plane_path?(sink) and not MapSet.member?(@public_cross_plane_sinks, sink) ->
        [finding(:plane_internal, source, source_plane, sink, sink_plane, label)]

      true ->
        []
    end
  end

  defp finding(kind, source, source_plane, sink, sink_plane, label) do
    %{
      kind: kind,
      source: source,
      sink: sink,
      label: "#{label}; #{source_plane} -> #{sink_plane}",
      fingerprint: Enum.join([kind, source, sink], "|")
    }
  end

  defp path_in_plane?(path, prefixes) do
    Enum.any?(prefixes, fn prefix -> path == prefix or String.starts_with?(path, prefix) end)
  end

  defp classify_from_paths(path, paths) do
    Enum.find_value(paths, fn {plane, prefixes} ->
      if path_in_plane?(path, prefixes), do: plane
    end)
  end

  defp formal_plane_path?(path) do
    Enum.any?(
      [
        "lib/cadence/management/",
        "lib/cadence/control/",
        "lib/cadence/runtime/",
        "lib/cadence/projections/"
      ],
      &String.starts_with?(path, &1)
    )
  end
end
