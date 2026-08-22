defmodule Cadence.Reads.OperationalEvidence do
  @moduledoc """
  Cross-context read boundary for operator-facing operational evidence.

  Consumers provide normalized filters and receive domain records. Dashboard
  request planning and frame presentation remain outside this module.
  """

  alias Cadence.Contacts
  alias Cadence.OperationalEvents
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection
  alias Cadence.Reads.DataSources
  alias Cadence.Reads.MissionEvents, as: MissionEventReads
  alias Cadence.Telemetry.Storage, as: TelemetryStorage

  @canonical_mission_timeline_kinds [
    :binding_set_activated,
    :managed_capability_initialized,
    :managed_capability_record_handled,
    :managed_capability_timer_handled,
    :managed_action_requested,
    :managed_timer_scheduled,
    :managed_timer_fired,
    :managed_timer_canceled
  ]
  @default_limit 500

  def list_scheduled_contacts(organization_id, mission_id, opts) do
    organization_id
    |> Contacts.list_scheduled_contacts(mission_id)
    |> Enum.filter(&interval_overlaps_opts?(&1.starts_at, &1.ends_at, opts))
  end

  def list_realized_contacts(organization_id, mission_id, opts) do
    organization_id
    |> Contacts.list_realized_contacts(mission_id)
    |> Enum.filter(fn contact ->
      interval_overlaps_opts?(
        contact.realized_at || contact.initial_time,
        contact_end_time(contact.metadata),
        opts
      )
    end)
  end

  def list_contact_events(organization_id, mission_id, opts) do
    OperationalEvents.list_events(organization_id, mission_id, canonical_contact_event_opts(opts))
  end

  def fetch_operational_event(organization_id, mission_id, event_id) do
    OperationalEvents.fetch_event(organization_id, mission_id, event_id)
  end

  def list_operational_events(organization_id, mission_id, opts) do
    OperationalEvents.list_events(organization_id, mission_id, opts)
  end

  def list_effective_intervals(kind, organization_id, mission_id, opts)

  def list_effective_intervals(:binding_set, organization_id, mission_id, opts),
    do:
      effective_intervals(
        &OperationalEvents.binding_set_intervals/2,
        &OperationalEvents.binding_set_intervals/3,
        organization_id,
        mission_id,
        opts
      )

  def list_effective_intervals(:application_binding, organization_id, mission_id, opts),
    do:
      effective_intervals(
        &OperationalEvents.application_binding_intervals/2,
        &OperationalEvents.application_binding_intervals/3,
        organization_id,
        mission_id,
        opts
      )

  def list_effective_intervals(:catalog_revision, organization_id, mission_id, opts),
    do:
      effective_intervals(
        &OperationalEvents.catalog_revision_intervals/2,
        &OperationalEvents.catalog_revision_intervals/3,
        organization_id,
        mission_id,
        opts
      )

  def list_effective_intervals(:source_binding, organization_id, mission_id, opts),
    do:
      effective_intervals(
        &OperationalEvents.source_binding_intervals/2,
        &OperationalEvents.source_binding_intervals/3,
        organization_id,
        mission_id,
        opts
      )

  def list_effective_intervals(:source_health, organization_id, mission_id, opts),
    do:
      effective_intervals(
        &OperationalEvents.source_health_intervals/2,
        &OperationalEvents.source_health_intervals/3,
        organization_id,
        mission_id,
        opts
      )

  def list_effective_intervals(:transport_execution, organization_id, mission_id, opts),
    do:
      effective_intervals(
        &OperationalEvents.transport_execution_intervals/2,
        &OperationalEvents.transport_execution_intervals/3,
        organization_id,
        mission_id,
        opts
      )

  def list_effective_intervals(:connection_state, organization_id, mission_id, opts),
    do:
      effective_intervals(
        &OperationalEvents.connection_state_intervals/2,
        &OperationalEvents.connection_state_intervals/3,
        organization_id,
        mission_id,
        opts
      )

  def list_effective_intervals(:operational_observable_state, organization_id, mission_id, opts),
    do:
      effective_intervals(
        &OperationalEvents.operational_observable_state_intervals/2,
        &OperationalEvents.operational_observable_state_intervals/3,
        organization_id,
        mission_id,
        opts
      )

  def list_effective_intervals(:link_rf_state, organization_id, mission_id, opts),
    do:
      effective_intervals(
        &OperationalEvents.link_rf_state_intervals/2,
        &OperationalEvents.link_rf_state_intervals/3,
        organization_id,
        mission_id,
        opts
      )

  defp effective_intervals(mission_reader, scoped_reader, organization_id, mission_id, opts) do
    if is_binary(organization_id) do
      scoped_reader.(organization_id, mission_id, opts)
    else
      mission_reader.(mission_id, opts)
    end
  end

  def list_mission_events(organization_id, mission_id, opts) do
    if Keyword.get(opts, :replay_run_id) do
      organization_id
      |> OperationalEvents.list_events(mission_id, canonical_event_opts(opts))
      |> MissionEventProjection.project_many()
      |> filter_mission_events_by_opts(opts)
    else
      MissionEventReads.list_for_mission(organization_id, mission_id, opts)
    end
  end

  def list_source_health_events(organization_id, mission_id, opts) do
    DataSources.list_source_health_events(organization_id, mission_id, opts)
  end

  def list_source_watermark_events(organization_id, mission_id, opts) do
    DataSources.list_source_watermark_events(organization_id, mission_id, opts)
  end

  def list_source_capability_posture_events(organization_id, mission_id, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)

    query_opts =
      opts
      |> Keyword.take([:replay_run_id, :from_occurred_at, :to_occurred_at, :order])
      |> Keyword.put(:category, :data_source)
      |> Keyword.put(:source_record_kind, :source_capability_posture)
      |> Keyword.put(:limit, limit * 4)
      |> Keyword.put_new(:order, :asc)

    OperationalEvents.list_events(organization_id, mission_id, query_opts)
    |> Enum.filter(&source_capability_posture_event_matches_opts?(&1, opts))
    |> Enum.take(limit)
  end

  def list_telemetry_backfill_lifecycle_events(organization_id, mission_id, opts) do
    opts =
      opts
      |> Keyword.put(:organization_id, organization_id)
      |> Keyword.delete(:dataset)
      |> Keyword.delete(:order)

    TelemetryStorage.list_backfill_lifecycle_events(mission_id, opts)
  end

  def list_telemetry_revision_decision_events(organization_id, mission_id, opts) do
    opts =
      opts
      |> Keyword.put(:organization_id, organization_id)
      |> Keyword.delete(:dataset)
      |> Keyword.delete(:order)

    TelemetryStorage.list_observation_identity_decision_events_for_mission(mission_id, opts)
  end

  defp canonical_contact_event_opts(opts) do
    query_limit = Keyword.get(opts, :limit, @default_limit) * 4

    opts
    |> Keyword.take([:severity, :source_record_kind, :source_record_id, :replay_run_id, :order])
    |> Keyword.put(:category, :contact)
    |> Keyword.put(:kind, [:scheduled_contact_interval, :realized_contact_interval])
    |> Keyword.put(:limit, max(query_limit, @default_limit))
    |> Keyword.put_new(:order, :asc)
  end

  defp canonical_event_opts(opts) do
    opts
    |> Keyword.take([
      :category,
      :kind,
      :severity,
      :source_record_kind,
      :source_record_id,
      :replay_run_id,
      :from_occurred_at,
      :to_occurred_at,
      :limit,
      :order
    ])
    |> Keyword.put_new(:order, :asc)
    |> Keyword.put_new(:kind, @canonical_mission_timeline_kinds)
  end

  defp filter_mission_events_by_opts(events, opts) do
    events
    |> Enum.filter(&mission_event_matches_opts?(&1, opts))
    |> Enum.take(Keyword.get(opts, :limit, @default_limit))
  end

  defp mission_event_matches_opts?(event, opts) do
    [:spacecraft_id, :source_endpoint_ref, :scheduled_contact_id, :realized_contact_id, :path_id]
    |> Enum.all?(fn key -> mission_event_filter_match?(event, key, Keyword.get(opts, key)) end)
  end

  defp mission_event_filter_match?(_event, _key, nil), do: true
  defp mission_event_filter_match?(event, key, value), do: get_attr(event, key) == value

  defp source_capability_posture_event_matches_opts?(event, opts) do
    [
      :logical_source,
      :data_source_id,
      :source_binding_id,
      :realm,
      :replay_run_id,
      :dataset,
      :dashboard_id,
      :source_request_id,
      :resolve_id,
      :status
    ]
    |> Enum.all?(fn key ->
      stringify(source_capability_posture_value(event, key)) ==
        stringify(Keyword.get(opts, key)) or is_nil(Keyword.get(opts, key))
    end)
  end

  defp source_capability_posture_value(event, :status) do
    event
    |> get_attr(:current)
    |> get_attr(:capability_status)
    |> fallback(event |> get_attr(:payload) |> get_attr(:status))
  end

  defp source_capability_posture_value(event, :realm) do
    event
    |> get_attr(:payload)
    |> get_attr(:realm)
    |> fallback(event |> get_attr(:scope) |> get_attr(:data_realm))
    |> fallback(event |> get_attr(:scope) |> get_attr(:realm))
  end

  defp source_capability_posture_value(event, key) do
    event
    |> get_attr(:payload)
    |> get_attr(key)
    |> fallback(event |> get_attr(:scope) |> get_attr(key))
    |> fallback(event |> get_attr(:current) |> get_attr(key))
  end

  defp interval_overlaps_opts?(nil, _ends_at, _opts), do: false

  defp interval_overlaps_opts?(%DateTime{} = starts_at, ends_at, opts) do
    from = Keyword.get(opts, :from_occurred_at)
    to = Keyword.get(opts, :to_occurred_at)

    cond do
      match?(%DateTime{}, to) and DateTime.compare(starts_at, to) != :lt -> false
      match?(%DateTime{}, from) and not interval_ends_after?(ends_at, from) -> false
      true -> true
    end
  end

  defp contact_end_time(metadata) when is_map(metadata) do
    metadata |> get_attr(:ended_at) |> normalize_datetime()
  end

  defp contact_end_time(_metadata), do: nil
  defp interval_ends_after?(nil, %DateTime{}), do: true

  defp interval_ends_after?(%DateTime{} = ends_at, %DateTime{} = from),
    do: DateTime.compare(ends_at, from) == :gt

  defp normalize_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil
  defp fallback(nil, value), do: value
  defp fallback(value, _fallback), do: value
  defp get_attr(nil, _key), do: nil
  defp get_attr(%_{} = value, key), do: value |> Map.from_struct() |> get_attr(key)

  defp get_attr(value, key) when is_map(value),
    do: Map.get(value, key, Map.get(value, to_string(key)))

  defp get_attr(_value, _key), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: inspect(value)
end
