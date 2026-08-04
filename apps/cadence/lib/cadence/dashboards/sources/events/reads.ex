defmodule Cadence.Dashboards.Sources.Events.Reads do
  @moduledoc false

  import Cadence.Dashboards.Sources.Events.RequestPlanning

  alias Cadence.Dashboards.{PlannedSourceRequest, ScopeContext}
  alias Cadence.Reads.OperationalEvidence

  @type scheduled_contacts_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type realized_contacts_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type contact_operational_events_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type mission_events_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type source_health_events_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type source_watermark_events_fun :: (binary() | nil, binary(), keyword() -> [struct()])
  @type source_capability_posture_events_fun :: (binary() | nil, binary(), keyword() ->
                                                   [struct()])
  @type telemetry_backfill_lifecycle_events_fun :: (binary() | nil, binary(), keyword() ->
                                                      [struct()])
  @type telemetry_revision_decision_events_fun :: (binary() | nil, binary(), keyword() ->
                                                     [struct()])

  def contact_opts(%PlannedSourceRequest{} = request, source_binding, limit) do
    base_opts(request, source_binding, limit)
  end

  def mission_event_opts(%PlannedSourceRequest{} = request, source_binding, limit) do
    request
    |> base_opts(source_binding, limit)
    |> maybe_put_scope_filters(request)
  end

  def source_health_opts(%PlannedSourceRequest{} = request, limit) do
    opts = [
      realm: get_attr(request.data_context, :realm),
      limit: limit,
      order: :asc
    ]

    case time_window(request) do
      {%DateTime{} = from, %DateTime{} = to} ->
        [{:from_observed_at, from}, {:to_observed_at, to} | opts]

      _window ->
        opts
    end
    |> maybe_put_source_health_filters(request)
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  def source_watermark_opts(%PlannedSourceRequest{} = request, limit) do
    opts = [
      realm: get_attr(request.data_context, :realm),
      limit: limit,
      order: :asc
    ]

    case time_window(request) do
      {%DateTime{} = from, %DateTime{} = to} ->
        [{:from_observed_at, from}, {:to_observed_at, to} | opts]

      _window ->
        opts
    end
    |> maybe_put_source_watermark_filters(request)
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  def source_capability_posture_opts(%PlannedSourceRequest{} = request, limit) do
    opts = [
      realm: get_attr(request.data_context, :realm),
      limit: limit,
      order: :asc
    ]

    opts =
      case time_window(request) do
        {%DateTime{} = from, %DateTime{} = to} ->
          [{:from_occurred_at, from}, {:to_occurred_at, to} | opts]

        _window ->
          opts
      end

    opts
    |> maybe_put_source_capability_posture_filters(request)
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  def telemetry_revision_decision_opts(
        %PlannedSourceRequest{} = request,
        _source_binding,
        limit
      ) do
    opts = [
      realm: get_attr(request.data_context, :realm),
      limit: limit,
      order: :asc
    ]

    opts =
      case time_window(request) do
        {%DateTime{} = from, %DateTime{} = to} ->
          [{:from_occurred_at, from}, {:to_occurred_at, to} | opts]

        _window ->
          opts
      end

    opts
    |> maybe_put_scope_filters(request)
    |> maybe_put_telemetry_revision_filters(request)
    |> maybe_rename_source_binding_filter()
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  def telemetry_backfill_lifecycle_opts(
        %PlannedSourceRequest{} = request,
        _source_binding,
        limit
      ) do
    opts =
      [
        realm: get_attr(request.data_context, :realm),
        limit: limit,
        order: :asc
      ]

    opts =
      case time_window(request) do
        {%DateTime{} = from, %DateTime{} = to} ->
          [{:source_from, from}, {:source_to, to} | opts]

        _window ->
          opts
      end

    opts
    |> maybe_put_scope_filters(request)
    |> maybe_put_telemetry_backfill_filters(request)
    |> maybe_rename_source_binding_filter()
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp base_opts(%PlannedSourceRequest{} = request, source_binding, limit) do
    opts = [
      realm: realm(request, source_binding),
      data_source_id: data_source_id(request, source_binding),
      source_binding_id: source_binding_id(source_binding),
      replay_run_id: replay_run_id(request),
      dataset: dataset(source_binding),
      limit: limit,
      order: :asc
    ]

    case time_window(request) do
      {%DateTime{} = from, %DateTime{} = to} ->
        [{:from_occurred_at, from}, {:to_occurred_at, to} | opts]

      _window ->
        opts
    end
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp maybe_put_scope_filters(opts, %PlannedSourceRequest{} = request) do
    cond do
      spacecraft_id = ScopeContext.scope_id(request.scope_context, :spacecraft) ->
        Keyword.put(opts, :spacecraft_id, spacecraft_id)

      contact_id = ScopeContext.scope_id(request.scope_context, :contact) ->
        opts
        |> Keyword.put(:scheduled_contact_id, contact_id)
        |> Keyword.put(:realized_contact_id, contact_id)

      source_endpoint_ref = source_endpoint_scope_id(request) ->
        Keyword.put(opts, :source_endpoint_ref, source_endpoint_ref)

      true ->
        opts
    end
  end

  defp maybe_put_source_health_filters(opts, %PlannedSourceRequest{} = request) do
    source_health_context = get_attr(request.sampling, :source_health) || %{}

    opts
    |> maybe_put_filter(:logical_source, get_attr(source_health_context, :logical_source))
    |> maybe_put_filter(:data_source_id, get_attr(source_health_context, :data_source_id))
    |> maybe_put_filter(:source_binding_id, get_attr(source_health_context, :source_binding_id))
    |> maybe_put_filter(
      :replay_run_id,
      get_attr(source_health_context, :replay_run_id) || replay_run_id(request)
    )
    |> maybe_put_filter(:dataset, get_attr(source_health_context, :dataset))
  end

  defp maybe_put_source_watermark_filters(opts, %PlannedSourceRequest{} = request) do
    source_watermark_context = get_attr(request.sampling, :source_watermark) || %{}

    opts
    |> maybe_put_filter(:logical_source, get_attr(source_watermark_context, :logical_source))
    |> maybe_put_filter(:data_source_id, get_attr(source_watermark_context, :data_source_id))
    |> maybe_put_filter(
      :source_binding_id,
      get_attr(source_watermark_context, :source_binding_id)
    )
    |> maybe_put_filter(
      :replay_run_id,
      get_attr(source_watermark_context, :replay_run_id) || replay_run_id(request)
    )
    |> maybe_put_filter(:dataset, get_attr(source_watermark_context, :dataset))
  end

  defp maybe_put_source_capability_posture_filters(opts, %PlannedSourceRequest{} = request) do
    source_capability_context = get_attr(request.sampling, :source_capability) || %{}

    opts
    |> maybe_put_filter(:logical_source, get_attr(source_capability_context, :logical_source))
    |> maybe_put_filter(:data_source_id, get_attr(source_capability_context, :data_source_id))
    |> maybe_put_filter(
      :source_binding_id,
      get_attr(source_capability_context, :source_binding_id)
    )
    |> maybe_put_filter(:realm, get_attr(source_capability_context, :realm))
    |> maybe_put_filter(
      :replay_run_id,
      get_attr(source_capability_context, :replay_run_id) || replay_run_id(request)
    )
    |> maybe_put_filter(:dataset, get_attr(source_capability_context, :dataset))
    |> maybe_put_filter(:dashboard_id, get_attr(source_capability_context, :dashboard_id))
    |> maybe_put_filter(
      :source_request_id,
      get_attr(source_capability_context, :source_request_id)
    )
    |> maybe_put_filter(:resolve_id, get_attr(source_capability_context, :resolve_id))
    |> maybe_put_filter(:status, get_attr(source_capability_context, :status))
  end

  defp maybe_put_telemetry_revision_filters(opts, %PlannedSourceRequest{} = request) do
    telemetry_revision_context = get_attr(request.sampling, :telemetry_revision) || %{}

    opts
    |> maybe_put_filter(:data_source_id, get_attr(telemetry_revision_context, :data_source_id))
    |> maybe_put_filter(
      :source_binding_id,
      get_attr(telemetry_revision_context, :source_binding_id)
    )
    |> maybe_put_filter(:observable_id, get_attr(telemetry_revision_context, :observable_id))
    |> maybe_put_filter(:point_id, get_attr(telemetry_revision_context, :point_id))
    |> maybe_put_filter(:decision, get_attr(telemetry_revision_context, :decision))
    |> maybe_put_filter(
      :replay_run_id,
      get_attr(telemetry_revision_context, :replay_run_id) || replay_run_id(request)
    )
    |> maybe_put_filter(
      :observation_identity_id,
      get_attr(telemetry_revision_context, :observation_identity_id)
    )
  end

  defp maybe_put_telemetry_backfill_filters(opts, %PlannedSourceRequest{} = request) do
    telemetry_backfill_context = get_attr(request.sampling, :telemetry_backfill) || %{}

    opts
    |> maybe_put_filter(:data_source_id, get_attr(telemetry_backfill_context, :data_source_id))
    |> maybe_put_filter(
      :source_binding_id,
      get_attr(telemetry_backfill_context, :source_binding_id)
    )
    |> maybe_put_filter(:observable_id, get_attr(telemetry_backfill_context, :observable_id))
    |> maybe_put_filter(:point_id, get_attr(telemetry_backfill_context, :point_id))
    |> maybe_put_filter(:event_type, get_attr(telemetry_backfill_context, :event_type))
    |> maybe_put_filter(:authority, get_attr(telemetry_backfill_context, :authority))
    |> maybe_put_filter(:backfill_run_id, get_attr(telemetry_backfill_context, :backfill_run_id))
    |> maybe_put_filter(
      :replay_run_id,
      get_attr(telemetry_backfill_context, :replay_run_id) || replay_run_id(request)
    )
  end

  defp maybe_rename_source_binding_filter(opts) do
    case Keyword.pop(opts, :source_binding_id) do
      {nil, opts} -> opts
      {source_binding_id, opts} -> Keyword.put(opts, :binding_id, source_binding_id)
    end
  end

  defp maybe_put_filter(opts, _key, nil), do: opts
  defp maybe_put_filter(opts, key, value), do: Keyword.put(opts, key, value)

  def mission_event_cursor([]), do: nil

  def mission_event_cursor(events) do
    event = List.last(events)
    %{occurred_at: event.occurred_at, mission_event_id: event.mission_event_id}
  end

  def source_health_event_cursor([]), do: nil

  def source_health_event_cursor(events) do
    event = List.last(events)
    %{observed_at: event.observed_at, source_health_event_id: event.source_health_event_id}
  end

  def source_watermark_event_cursor([]), do: nil

  def source_watermark_event_cursor(events) do
    event = List.last(events)

    %{
      observed_at: event.observed_at,
      source_watermark_event_id: event.source_watermark_event_id,
      complete_through: event.complete_through,
      latest_receipt_time: event.latest_receipt_time
    }
  end

  def source_capability_posture_event_cursor([]), do: nil

  def source_capability_posture_event_cursor(events) do
    event = List.last(events)

    %{
      occurred_at: get_attr(event, :occurred_at),
      source_capability_posture_id: source_capability_posture_record_id(event),
      source_request_id: source_capability_posture_value(event, :source_request_id),
      capability_status: source_capability_posture_value(event, :status)
    }
  end

  def telemetry_backfill_lifecycle_event_cursor([]), do: nil

  def telemetry_backfill_lifecycle_event_cursor(events) do
    event = List.last(events)

    %{
      occurred_at: event.occurred_at,
      backfill_lifecycle_event_id: event.backfill_lifecycle_event_id,
      backfill_run_id: event.backfill_run_id,
      event_type: event.event_type,
      source_from: event.source_from,
      source_to: event.source_to
    }
  end

  def telemetry_revision_decision_event_cursor([]), do: nil

  def telemetry_revision_decision_event_cursor(events) do
    event = List.last(events)

    %{
      occurred_at: event.occurred_at,
      decision_event_id: event.decision_event_id,
      observation_identity_id: event.observation_identity_id,
      decision: event.decision
    }
  end

  defdelegate default_scheduled_contacts(organization_id, mission_id, opts),
    to: OperationalEvidence,
    as: :list_scheduled_contacts

  defdelegate default_realized_contacts(organization_id, mission_id, opts),
    to: OperationalEvidence,
    as: :list_realized_contacts

  defdelegate default_contact_operational_events(organization_id, mission_id, opts),
    to: OperationalEvidence,
    as: :list_contact_events

  defdelegate default_mission_events(organization_id, mission_id, opts),
    to: OperationalEvidence,
    as: :list_mission_events

  defdelegate default_source_health_events(organization_id, mission_id, opts),
    to: OperationalEvidence,
    as: :list_source_health_events

  defdelegate default_source_watermark_events(organization_id, mission_id, opts),
    to: OperationalEvidence,
    as: :list_source_watermark_events

  defdelegate default_source_capability_posture_events(organization_id, mission_id, opts),
    to: OperationalEvidence,
    as: :list_source_capability_posture_events

  defdelegate default_telemetry_backfill_lifecycle_events(organization_id, mission_id, opts),
    to: OperationalEvidence,
    as: :list_telemetry_backfill_lifecycle_events

  defdelegate default_telemetry_revision_decision_events(organization_id, mission_id, opts),
    to: OperationalEvidence,
    as: :list_telemetry_revision_decision_events

  def source_capability_posture_record_id(event) do
    event
    |> get_attr(:causality)
    |> get_attr(:source_record_id)
    |> fallback(source_capability_posture_value(event, :source_capability_posture_id))
  end

  def source_capability_posture_value(event, :status) do
    event
    |> get_attr(:current)
    |> state_value(:capability_status)
    |> fallback(event |> get_attr(:payload) |> get_attr(:status))
  end

  def source_capability_posture_value(event, :realm) do
    event
    |> get_attr(:payload)
    |> get_attr(:realm)
    |> fallback(event |> get_attr(:scope) |> get_attr(:data_realm))
    |> fallback(event |> get_attr(:scope) |> get_attr(:realm))
  end

  def source_capability_posture_value(event, key) when is_atom(key) do
    event
    |> get_attr(:payload)
    |> get_attr(key)
    |> fallback(event |> get_attr(:scope) |> get_attr(key))
    |> fallback(event |> get_attr(:current) |> get_attr(key))
  end

  def interval_sort_key(%{starts_at: starts_at, kind: kind, contact_id: contact_id}) do
    {datetime_sort(starts_at), Atom.to_string(kind), contact_id}
  end

  def event_sort_key(event) do
    {
      datetime_sort(get_attr(event, :occurred_at) || get_attr(event, :observed_at)),
      get_attr(event, :mission_event_id) || get_attr(event, :source_health_event_id) ||
        get_attr(event, :source_watermark_event_id) ||
        get_attr(event, :backfill_lifecycle_event_id) || get_attr(event, :decision_event_id) ||
        get_attr(event, :event_id) || source_capability_posture_record_id(event)
    }
  end

  defp datetime_sort(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp datetime_sort(_datetime), do: 0

  defp state_value(state, key) when is_map(state), do: get_attr(state, key)
  defp state_value(_state, _key), do: nil

  defp fallback(nil, value), do: value
  defp fallback(value, _fallback), do: value

  defp get_attr(nil, _key), do: nil

  defp get_attr(%_struct{} = struct, key) when is_atom(key) do
    struct
    |> Map.from_struct()
    |> get_attr(key)
  end

  defp get_attr(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp get_attr(_value, _key), do: nil
end
