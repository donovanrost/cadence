defmodule Cadence.OperationalEvents.Event.Kind do
  @moduledoc false

  @kinds [
    :binding_set_activated,
    :catalog_revision_registered,
    :dashboard_archived,
    :dashboard_comparison_review_requested,
    :dashboard_comparison_review_resolved,
    :dashboard_health_snapshot_captured,
    :dashboard_limit_selected_clock,
    :dashboard_publish_readiness_checked,
    :dashboard_published,
    :dashboard_restored,
    :dashboard_reverted,
    :limit_definition_activated,
    :limit_definition_disabled,
    :limit_definition_lifecycle_unknown,
    :limit_definition_registered,
    :limit_definition_retired,
    :limit_definition_superseded,
    :managed_action_requested,
    :managed_capability_initialized,
    :managed_capability_record_handled,
    :managed_capability_timer_handled,
    :managed_timer_canceled,
    :managed_timer_fired,
    :managed_timer_scheduled,
    :operational_observable_metric_sampled,
    :operational_observable_state_changed,
    :provider_audit_recorded,
    :realized_contact_ended_early,
    :realized_contact_interval,
    :scheduled_contact_canceled,
    :scheduled_contact_interval,
    :source_binding_changed,
    :source_binding_disabled,
    :source_binding_enabled,
    :source_binding_registered,
    :source_binding_superseded,
    :source_capability_fallback,
    :source_capability_native,
    :source_capability_unknown,
    :source_capability_unsupported,
    :source_credential_material_resolution_denied,
    :source_credential_material_resolution_failed,
    :source_credential_material_resolved,
    :source_health_degraded,
    :source_health_recovered,
    :source_health_unavailable,
    :source_health_unknown,
    :source_watermark_advanced,
    :source_watermark_changed,
    :source_watermark_observed,
    :source_watermark_retreated,
    :source_watermark_unknown,
    :telemetry_backfill_approved,
    :telemetry_backfill_completed,
    :telemetry_backfill_failed,
    :telemetry_backfill_lifecycle_unknown,
    :telemetry_backfill_missing_replacement_inspected,
    :telemetry_backfill_rejected,
    :telemetry_backfill_requested,
    :telemetry_backfill_retried,
    :telemetry_backfill_stale_replacement_inspected,
    :telemetry_backfill_stale_replacement_requeued,
    :telemetry_backfill_started,
    :telemetry_import_approved,
    :telemetry_import_completed,
    :telemetry_import_failed,
    :telemetry_import_missing_replacement_inspected,
    :telemetry_import_rejected,
    :telemetry_import_requested,
    :telemetry_import_retried,
    :telemetry_import_stale_replacement_inspected,
    :telemetry_import_stale_replacement_requeued,
    :telemetry_import_started,
    :telemetry_late_data_accepted,
    :telemetry_late_data_rejected,
    :telemetry_observation_marked_advisory,
    :telemetry_observation_marked_canonical,
    :telemetry_observation_marked_conflict,
    :telemetry_observation_marked_superseded,
    :transport_action_requested,
    :transport_control_input_handled,
    :transport_event_handled,
    :transport_initialized,
    :transport_timer_canceled,
    :transport_timer_fired,
    :transport_timer_handled,
    :transport_timer_scheduled
  ]

  @kind_by_name Map.new(@kinds, &{Atom.to_string(&1), &1})

  @spec all() :: [atom()]
  def all, do: @kinds

  @spec normalize!(atom() | binary()) :: atom()
  def normalize!(value) when is_atom(value) do
    if value in @kinds do
      value
    else
      raise ArgumentError, "unsupported kind: #{inspect(value)}"
    end
  end

  def normalize!(value) when is_binary(value) do
    case Map.fetch(@kind_by_name, value) do
      {:ok, kind} -> kind
      :error -> raise ArgumentError, "unsupported kind: #{inspect(value)}"
    end
  end

  def normalize!(value), do: raise(ArgumentError, "unsupported kind: #{inspect(value)}")
end
