defmodule Cadence.Architecture.PlaneBoundary do
  @moduledoc """
  Classifies plane-owned source paths and enforces ADR-015 dependency direction.

  Domain-first namespaces remain unclassified until their authority is split or
  recorded explicitly. Plane-prefixed namespaces are guarded immediately.
  """

  @plane_paths [
    management: ["lib/cadence/management.ex", "lib/cadence/management/"],
    control: ["lib/cadence/control.ex", "lib/cadence/control/"],
    data: ["lib/cadence/runtime.ex", "lib/cadence/runtime/"],
    projections: ["lib/cadence/projections.ex", "lib/cadence/projections/"],
    platform: ["lib/cadence/platform.ex", "lib/cadence/platform/"]
  ]

  @plane_file_overrides %{
    "lib/cadence/applications/telemetry_decom.ex" => :management,
    "lib/cadence/commanding/command_approval.ex" => :management,
    "lib/cadence/commanding/command_queue_entry.ex" => :control,
    "lib/cadence/commanding/command_release_attempt.ex" => :control,
    "lib/cadence/commanding/command_request.ex" => :management,
    "lib/cadence/commanding/command_stage.ex" => :management,
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
    "lib/cadence/contact_planning/contact_plan.ex" => :management,
    "lib/cadence/contact_planning/contact_plan_approval.ex" => :management,
    "lib/cadence/contact_planning/contact_plan_approvals.ex" => :management,
    "lib/cadence/contact_planning/contact_plan_execution_item.ex" => :control,
    "lib/cadence/contact_planning/contact_plan_executions.ex" => :control,
    "lib/cadence/contact_planning/contact_plan_version.ex" => :management,
    "lib/cadence/contact_planning/contact_plans.ex" => :management,
    "lib/cadence/dashboards/data_source.ex" => :management,
    "lib/cadence/dashboards/managed_questdb_provisioning.ex" => :control,
    "lib/cadence/dashboards/managed_questdb_provisioning_jobs.ex" => :control,
    "lib/cadence/dashboards/managed_questdb_provisioning_runs.ex" => :control,
    "lib/cadence/dashboards/tsdb_backend_lifecycle_jobs.ex" => :control
  }

  @plane_prefix_overrides [
    management: [
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
    ]
  ]

  @allowed_directions MapSet.new([
                        {:management, :platform},
                        {:control, :management},
                        {:control, :data},
                        {:control, :platform},
                        {:data, :platform},
                        {:projections, :management},
                        {:projections, :control},
                        {:projections, :data},
                        {:projections, :platform}
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
                              "lib/cadence/control/contacts.ex",
                              "lib/cadence/management/providers.ex",
                              "lib/cadence/management/providers/provider_configuration.ex",
                              "lib/cadence/control/providers.ex",
                              "lib/cadence/ground_networks/mission_provider.ex",
                              "lib/cadence/ground_networks/mission_providers.ex",
                              "lib/cadence/ground_networks/provider_account_grants.ex",
                              "lib/cadence/ground_networks/provider_account_version.ex",
                              "lib/cadence/ground_networks/provider_accounts.ex",
                              "lib/cadence/management/managed_resources.ex",
                              "lib/cadence/management/managed_resources/managed_resource_request.ex",
                              "lib/cadence/control/managed_resources.ex",
                              "lib/cadence/dashboards/data_source.ex",
                              "lib/cadence/platform/content_hash.ex",
                              "lib/cadence/runtime/generation_applied.ex",
                              "lib/cadence/runtime/contacts.ex",
                              "lib/cadence/projections/contact_status.ex",
                              "lib/cadence/runtime/commanding.ex",
                              "lib/cadence/runtime/mission_runtime_spec.ex",
                              "lib/cadence/runtime/missions.ex",
                              "lib/cadence/runtime/realized_contact_runtime_spec.ex",
                              "lib/cadence/runtime/transmit_command.ex",
                              "lib/cadence/runtime/transport_action_request.ex",
                              "lib/cadence/runtime/transport_capability_record.ex",
                              "lib/cadence/runtime/managed_action_request.ex"
                            ])

  @type plane :: :management | :control | :data | :projections | :platform

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
    Map.get(@plane_file_overrides, path) ||
      Enum.find_value(@plane_prefix_overrides, fn {plane, prefixes} ->
        if path_in_plane?(path, prefixes), do: plane
      end) ||
      Enum.find_value(@plane_paths, fn {plane, prefixes} ->
        if path_in_plane?(path, prefixes), do: plane
      end)
  end

  defp cross_plane_findings(source, source_plane, sink, sink_plane, label) do
    direction = {source_plane, sink_plane}

    cond do
      not MapSet.member?(@allowed_directions, direction) ->
        [finding(:plane_direction, source, source_plane, sink, sink_plane, label)]

      not MapSet.member?(@public_cross_plane_sinks, sink) ->
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
end
