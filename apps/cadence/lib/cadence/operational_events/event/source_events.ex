defmodule Cadence.OperationalEvents.Event.SourceEvents do
  @moduledoc false

  import Cadence.OperationalEvents.Event.Normalization

  alias Cadence.Dashboards.LifecycleEvent

  alias Cadence.DataSources.{SourceHealthEvent, SourceWatermarkEvent}

  alias Cadence.DataSources.DataBindingEvent

  def from_dashboard_lifecycle_event(%LifecycleEvent{} = lifecycle_event, build_event) do
    build_event.(%{
      event_id:
        "operational_event:dashboard_lifecycle_event:#{lifecycle_event.dashboard_lifecycle_event_id}",
      organization_id: lifecycle_event.organization_id,
      mission_id: lifecycle_event.mission_id,
      occurred_at: lifecycle_event.occurred_at,
      recorded_at: lifecycle_event.occurred_at,
      effective_at: lifecycle_event.occurred_at,
      category: :dashboard,
      kind: dashboard_lifecycle_kind(lifecycle_event.event_type),
      severity: :info,
      actor: dashboard_lifecycle_actor(lifecycle_event.actor_id),
      subject: %{kind: :dashboard, id: lifecycle_event.dashboard_id},
      causality: %{
        correlation_id: lifecycle_event.dashboard_id,
        source_record_kind: :dashboard_lifecycle_event,
        source_record_id: lifecycle_event.dashboard_lifecycle_event_id
      },
      payload: %{
        dashboard_lifecycle_event_id: lifecycle_event.dashboard_lifecycle_event_id,
        dashboard_id: lifecycle_event.dashboard_id,
        event_type: lifecycle_event.event_type,
        dashboard_version: lifecycle_event.dashboard_version,
        lifecycle_payload: lifecycle_event.payload
      },
      previous: %{
        lifecycle_state: lifecycle_event.previous_lifecycle_state,
        published_version: lifecycle_event.previous_published_version
      },
      current: %{
        lifecycle_state: lifecycle_event.current_lifecycle_state,
        published_version: lifecycle_event.current_published_version,
        dashboard_version: lifecycle_event.dashboard_version
      },
      metadata: lifecycle_event.payload
    })
  end

  def from_data_binding_event(%DataBindingEvent{} = binding_event, build_event) do
    build_event.(%{
      event_id:
        "operational_event:data_source_binding_event:#{binding_event.data_binding_event_id}",
      organization_id: binding_event.organization_id,
      mission_id: binding_event.mission_id,
      occurred_at: binding_event.occurred_at,
      recorded_at: binding_event.occurred_at,
      effective_at: binding_event.occurred_at,
      category: :data_source,
      kind: data_binding_kind(binding_event.event_type),
      severity: data_binding_severity(binding_event.event_type),
      actor: dashboard_lifecycle_actor(binding_event.actor_id),
      subject: %{kind: :source_binding, id: binding_event.binding_id},
      scope: data_binding_scope(binding_event),
      causality: %{
        correlation_id: binding_event.binding_id,
        source_record_kind: :data_source_binding_event,
        source_record_id: binding_event.data_binding_event_id
      },
      payload: %{
        data_binding_event_id: binding_event.data_binding_event_id,
        binding_id: binding_event.binding_id,
        event_type: binding_event.event_type,
        binding_version: binding_event.current_binding_version,
        logical_source: binding_event.current_logical_source,
        realm: binding_event.current_realm,
        data_source_id: binding_event.current_data_source_id,
        dataset: binding_event.current_dataset,
        priority: binding_event.current_priority,
        active_from: binding_event.current_active_from,
        active_to: binding_event.current_active_to,
        lifecycle_payload: binding_event.payload
      },
      previous: %{
        status: binding_event.previous_status,
        binding_version: binding_event.previous_binding_version,
        logical_source: binding_event.previous_logical_source,
        realm: binding_event.previous_realm,
        data_source_id: binding_event.previous_data_source_id,
        dataset: binding_event.previous_dataset,
        priority: binding_event.previous_priority,
        active_from: binding_event.previous_active_from,
        active_to: binding_event.previous_active_to
      },
      current: %{
        status: binding_event.current_status,
        binding_version: binding_event.current_binding_version,
        logical_source: binding_event.current_logical_source,
        realm: binding_event.current_realm,
        data_source_id: binding_event.current_data_source_id,
        dataset: binding_event.current_dataset,
        priority: binding_event.current_priority,
        active_from: binding_event.current_active_from,
        active_to: binding_event.current_active_to
      },
      metadata: binding_event.payload
    })
  end

  defp data_binding_kind(:registered), do: :source_binding_registered
  defp data_binding_kind(:changed), do: :source_binding_changed
  defp data_binding_kind(:enabled), do: :source_binding_enabled
  defp data_binding_kind(:disabled), do: :source_binding_disabled
  defp data_binding_kind(:superseded), do: :source_binding_superseded

  defp data_binding_severity(event_type) when event_type in [:disabled, :superseded],
    do: :warning

  defp data_binding_severity(_event_type), do: :info

  defp data_binding_scope(%DataBindingEvent{} = binding_event) do
    %{
      logical_source: binding_event.current_logical_source,
      source_binding_id: binding_event.binding_id,
      data_source_id: binding_event.current_data_source_id,
      data_realm: binding_event.current_realm,
      dataset: binding_event.current_dataset
    }
    |> compact()
  end

  defp dashboard_lifecycle_kind(:published), do: :dashboard_published
  defp dashboard_lifecycle_kind(:archived), do: :dashboard_archived
  defp dashboard_lifecycle_kind(:restored), do: :dashboard_restored
  defp dashboard_lifecycle_kind(:reverted), do: :dashboard_reverted

  defp dashboard_lifecycle_kind(:comparison_review_requested),
    do: :dashboard_comparison_review_requested

  defp dashboard_lifecycle_kind(:comparison_review_resolved),
    do: :dashboard_comparison_review_resolved

  defp dashboard_lifecycle_kind(:health_snapshot_captured),
    do: :dashboard_health_snapshot_captured

  defp dashboard_lifecycle_kind(:publish_readiness_checked),
    do: :dashboard_publish_readiness_checked

  defp dashboard_lifecycle_actor(actor_id) when is_binary(actor_id) and actor_id != "",
    do: %{kind: :user, id: actor_id}

  defp dashboard_lifecycle_actor(_actor_id), do: %{kind: :system}

  def from_source_capability_posture(attrs, build_event) when is_map(attrs) do
    occurred_at = source_capability_posture_occurred_at(attrs)
    posture_id = source_capability_posture_id(attrs)
    payload = source_capability_posture_payload(attrs, posture_id, occurred_at)
    scope = source_capability_posture_scope(payload)
    status = Map.fetch!(payload, :status)

    build_event.(%{
      event_id:
        scoped_event_id(
          :source_capability_posture,
          posture_id,
          Map.get(payload, :replay_run_id)
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: fetch_required(attrs, :mission_id),
      occurred_at: occurred_at,
      recorded_at: Map.get(attrs, :recorded_at, Map.get(attrs, "recorded_at", occurred_at)),
      effective_at: occurred_at,
      category: :data_source,
      kind: source_capability_posture_kind(status),
      severity: source_capability_posture_severity(status),
      actor: Map.get(attrs, :actor, Map.get(attrs, "actor", %{kind: :system})),
      subject: source_capability_posture_subject(payload),
      scope: scope,
      causality:
        %{
          correlation_id: source_capability_posture_correlation_id(payload),
          source_record_kind: :source_capability_posture,
          source_record_id: posture_id,
          replay_run_id: Map.get(payload, :replay_run_id)
        }
        |> compact(),
      payload: payload,
      current: source_capability_posture_current(payload),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    })
  end

  def from_source_health_event(%SourceHealthEvent{} = source_event, build_event) do
    build_event.(%{
      event_id:
        scoped_event_id(
          :source_health_event,
          source_event.source_health_event_id,
          source_event.replay_run_id
        ),
      organization_id: source_event.organization_id,
      mission_id: source_event.mission_id,
      occurred_at: source_event.observed_at,
      recorded_at: source_event.observed_at,
      effective_at: source_event.observed_at,
      category: :data_source,
      kind: source_health_kind(source_event.event_type),
      severity: source_health_severity(source_event.source_health),
      actor: %{kind: :system},
      subject: %{kind: :data_source, id: source_event.data_source_id},
      scope: source_event_scope(source_event),
      causality: %{
        correlation_id: source_event.source_health_key,
        source_record_kind: :source_health_event,
        source_record_id: source_event.source_health_event_id,
        replay_run_id: source_event.replay_run_id
      },
      payload:
        Map.merge(source_event_scope(source_event), %{
          source_health_event_id: source_event.source_health_event_id,
          source_health_key: source_event.source_health_key,
          event_type: source_event.event_type,
          source_health: source_event.source_health,
          previous_source_health: source_event.previous_source_health,
          reason: source_event.reason,
          source_payload: source_event.payload
        }),
      previous: %{source_health: source_event.previous_source_health},
      current: %{
        source_health: source_event.source_health,
        reason: source_event.reason
      },
      metadata: source_event.payload
    })
  end

  def from_source_watermark_event(%SourceWatermarkEvent{} = source_event, build_event) do
    build_event.(%{
      event_id:
        scoped_event_id(
          :source_watermark_event,
          source_event.source_watermark_event_id,
          source_event.replay_run_id
        ),
      organization_id: source_event.organization_id,
      mission_id: source_event.mission_id,
      occurred_at: source_event.observed_at,
      recorded_at: source_event.observed_at,
      effective_at: source_event.observed_at,
      category: :data_source,
      kind: source_watermark_kind(source_event.event_type),
      severity: source_watermark_severity(source_event.event_type),
      actor: %{kind: :system},
      subject: %{kind: :data_source, id: source_event.data_source_id},
      scope: source_event_scope(source_event),
      causality: %{
        correlation_id: source_event.source_watermark_key,
        source_record_kind: :source_watermark_event,
        source_record_id: source_event.source_watermark_event_id,
        replay_run_id: source_event.replay_run_id
      },
      payload:
        Map.merge(source_event_scope(source_event), %{
          source_watermark_event_id: source_event.source_watermark_event_id,
          source_watermark_key: source_event.source_watermark_key,
          event_type: source_event.event_type,
          complete_through: source_event.complete_through,
          previous_complete_through: source_event.previous_complete_through,
          latest_receipt_time: source_event.latest_receipt_time,
          previous_latest_receipt_time: source_event.previous_latest_receipt_time,
          retention_starts_at: source_event.retention_starts_at,
          previous_retention_starts_at: source_event.previous_retention_starts_at,
          sample_count: source_event.sample_count,
          confidence: source_event.confidence,
          reason: source_event.reason,
          source_payload: source_event.payload
        }),
      previous: %{
        complete_through: source_event.previous_complete_through,
        latest_receipt_time: source_event.previous_latest_receipt_time,
        retention_starts_at: source_event.previous_retention_starts_at
      },
      current: %{
        complete_through: source_event.complete_through,
        latest_receipt_time: source_event.latest_receipt_time,
        retention_starts_at: source_event.retention_starts_at,
        sample_count: source_event.sample_count,
        confidence: source_event.confidence,
        reason: source_event.reason
      },
      metadata: source_event.payload
    })
  end

  defp source_health_kind(:degraded), do: :source_health_degraded
  defp source_health_kind(:recovered), do: :source_health_recovered
  defp source_health_kind(:unavailable), do: :source_health_unavailable
  defp source_health_kind(:unknown), do: :source_health_unknown

  defp source_health_severity(:healthy), do: :info
  defp source_health_severity(:degraded), do: :warning
  defp source_health_severity(:unavailable), do: :error
  defp source_health_severity(:unknown), do: :warning

  defp source_watermark_kind(:observed), do: :source_watermark_observed
  defp source_watermark_kind(:advanced), do: :source_watermark_advanced
  defp source_watermark_kind(:retreated), do: :source_watermark_retreated
  defp source_watermark_kind(:changed), do: :source_watermark_changed
  defp source_watermark_kind(:unknown), do: :source_watermark_unknown

  defp source_watermark_severity(:retreated), do: :warning
  defp source_watermark_severity(:unknown), do: :warning
  defp source_watermark_severity(_event_type), do: :info

  defp source_capability_posture_id(attrs) do
    Map.get(attrs, :source_capability_posture_id, Map.get(attrs, "source_capability_posture_id")) ||
      Map.get(attrs, :posture_id, Map.get(attrs, "posture_id")) ||
      [
        Map.get(attrs, :dashboard_id, Map.get(attrs, "dashboard_id")),
        Map.get(attrs, :resolve_id, Map.get(attrs, "resolve_id")),
        Map.get(attrs, :source_request_id, Map.get(attrs, "source_request_id"))
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(":")
      |> text_value!()
  end

  defp source_capability_posture_occurred_at(attrs) do
    Map.get(attrs, :observed_at) ||
      Map.get(attrs, "observed_at") ||
      Map.get(attrs, :occurred_at) ||
      Map.get(attrs, "occurred_at") ||
      raise KeyError, key: :occurred_at, term: attrs
  end

  defp source_capability_posture_payload(attrs, posture_id, occurred_at) do
    posture = Map.get(attrs, :capability_posture, Map.get(attrs, "capability_posture", %{}))
    posture_status = source_capability_posture_value(posture, :status)

    %{
      source_capability_posture_id: posture_id,
      dashboard_id: Map.get(attrs, :dashboard_id, Map.get(attrs, "dashboard_id")),
      dashboard_version: Map.get(attrs, :dashboard_version, Map.get(attrs, "dashboard_version")),
      resolve_id: Map.get(attrs, :resolve_id, Map.get(attrs, "resolve_id")),
      source_request_id: Map.get(attrs, :source_request_id, Map.get(attrs, "source_request_id")),
      logical_source: Map.get(attrs, :logical_source, Map.get(attrs, "logical_source")),
      data_source_id: Map.get(attrs, :data_source_id, Map.get(attrs, "data_source_id")),
      source_binding_id: Map.get(attrs, :source_binding_id, Map.get(attrs, "source_binding_id")),
      realm: Map.get(attrs, :realm, Map.get(attrs, "realm")),
      dataset: Map.get(attrs, :dataset, Map.get(attrs, "dataset")),
      replay_run_id: Map.get(attrs, :replay_run_id, Map.get(attrs, "replay_run_id")),
      status: Map.get(attrs, :status, Map.get(attrs, "status", posture_status)),
      requested_sampling:
        Map.get(
          attrs,
          :requested_sampling,
          Map.get(
            attrs,
            "requested_sampling",
            source_capability_posture_value(posture, :requested_sampling)
          )
        ),
      supported_sampling:
        Map.get(
          attrs,
          :supported_sampling,
          Map.get(
            attrs,
            "supported_sampling",
            source_capability_posture_value(posture, :supported_sampling)
          )
        ),
      requested_products:
        Map.get(
          attrs,
          :requested_products,
          Map.get(
            attrs,
            "requested_products",
            source_capability_posture_value(posture, :requested_products)
          )
        ),
      supported_products:
        Map.get(
          attrs,
          :supported_products,
          Map.get(
            attrs,
            "supported_products",
            source_capability_posture_value(posture, :supported_products)
          )
        ),
      requested_time_axis:
        Map.get(
          attrs,
          :requested_time_axis,
          Map.get(
            attrs,
            "requested_time_axis",
            source_capability_posture_value(posture, :requested_time_axis)
          )
        ),
      executed_time_axis:
        Map.get(
          attrs,
          :executed_time_axis,
          Map.get(
            attrs,
            "executed_time_axis",
            source_capability_posture_value(posture, :executed_time_axis)
          )
        ),
      supported_time_axes:
        Map.get(
          attrs,
          :supported_time_axes,
          Map.get(
            attrs,
            "supported_time_axes",
            source_capability_posture_value(posture, :supported_time_axes)
          )
        ),
      fallbacks:
        Map.get(
          attrs,
          :fallbacks,
          Map.get(attrs, "fallbacks", source_capability_posture_value(posture, :fallbacks))
        ),
      unsupported:
        Map.get(
          attrs,
          :unsupported,
          Map.get(attrs, "unsupported", source_capability_posture_value(posture, :unsupported))
        ),
      source_execution_status:
        Map.get(attrs, :source_execution_status, Map.get(attrs, "source_execution_status")),
      source_execution_cache_status:
        Map.get(
          attrs,
          :source_execution_cache_status,
          Map.get(attrs, "source_execution_cache_status")
        ),
      source_execution_operator_action:
        Map.get(
          attrs,
          :source_execution_operator_action,
          Map.get(attrs, "source_execution_operator_action")
        ),
      source_execution_runtime_action:
        Map.get(
          attrs,
          :source_execution_runtime_action,
          Map.get(attrs, "source_execution_runtime_action")
        ),
      source_execution_warning_codes:
        Map.get(
          attrs,
          :source_execution_warning_codes,
          Map.get(attrs, "source_execution_warning_codes")
        ),
      observed_at: occurred_at
    }
    |> compact()
  end

  defp source_capability_posture_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp source_capability_posture_value(_map, _key), do: nil

  defp source_capability_posture_scope(payload) do
    %{
      logical_source: Map.get(payload, :logical_source),
      data_source_id: Map.get(payload, :data_source_id),
      source_binding_id: Map.get(payload, :source_binding_id),
      data_realm: Map.get(payload, :realm),
      replay_run_id: Map.get(payload, :replay_run_id),
      dataset: Map.get(payload, :dataset),
      dashboard_id: Map.get(payload, :dashboard_id),
      source_request_id: Map.get(payload, :source_request_id)
    }
    |> compact()
  end

  defp source_capability_posture_current(payload) do
    %{
      capability_status: Map.get(payload, :status),
      requested_sampling: Map.get(payload, :requested_sampling),
      supported_sampling: Map.get(payload, :supported_sampling),
      requested_products: Map.get(payload, :requested_products),
      supported_products: Map.get(payload, :supported_products),
      requested_time_axis: Map.get(payload, :requested_time_axis),
      executed_time_axis: Map.get(payload, :executed_time_axis),
      supported_time_axes: Map.get(payload, :supported_time_axes),
      fallbacks: Map.get(payload, :fallbacks),
      unsupported: Map.get(payload, :unsupported)
    }
    |> compact()
  end

  defp source_capability_posture_subject(%{data_source_id: data_source_id})
       when data_source_id not in [nil, ""],
       do: %{kind: :data_source, id: data_source_id}

  defp source_capability_posture_subject(%{source_binding_id: source_binding_id})
       when source_binding_id not in [nil, ""],
       do: %{kind: :source_binding, id: source_binding_id}

  defp source_capability_posture_subject(%{dashboard_id: dashboard_id})
       when dashboard_id not in [nil, ""],
       do: %{kind: :dashboard, id: dashboard_id}

  defp source_capability_posture_subject(_payload), do: nil

  defp source_capability_posture_correlation_id(payload) do
    Map.get(payload, :resolve_id) ||
      [
        Map.get(payload, :dashboard_id),
        Map.get(payload, :source_request_id)
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(":")
      |> case do
        "" -> Map.get(payload, :source_capability_posture_id)
        correlation_id -> correlation_id
      end
  end

  defp source_capability_posture_kind(:native), do: :source_capability_native
  defp source_capability_posture_kind("native"), do: :source_capability_native
  defp source_capability_posture_kind(:fallback), do: :source_capability_fallback
  defp source_capability_posture_kind("fallback"), do: :source_capability_fallback
  defp source_capability_posture_kind(:unsupported), do: :source_capability_unsupported
  defp source_capability_posture_kind("unsupported"), do: :source_capability_unsupported
  defp source_capability_posture_kind(_status), do: :source_capability_unknown

  defp source_capability_posture_severity(:native), do: :info
  defp source_capability_posture_severity("native"), do: :info
  defp source_capability_posture_severity(:fallback), do: :warning
  defp source_capability_posture_severity("fallback"), do: :warning
  defp source_capability_posture_severity(:unsupported), do: :error
  defp source_capability_posture_severity("unsupported"), do: :error
  defp source_capability_posture_severity(_status), do: :warning

  defp source_event_scope(source_event) do
    %{
      logical_source: Map.get(source_event, :logical_source),
      data_source_id: Map.get(source_event, :data_source_id),
      source_binding_id: Map.get(source_event, :source_binding_id),
      data_realm: Map.get(source_event, :realm),
      replay_run_id: Map.get(source_event, :replay_run_id),
      dataset: Map.get(source_event, :dataset)
    }
    |> compact()
  end
end
