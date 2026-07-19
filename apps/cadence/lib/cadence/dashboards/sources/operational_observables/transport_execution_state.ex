defmodule Cadence.Dashboards.Sources.OperationalObservables.TransportExecutionState do
  @moduledoc """
  Materializes transport execution state history rows, frames, and revisions.

  The source adapter supplies projected execution intervals and source identity.
  This module owns interval normalization, request filtering, event-frame
  presentation, and the revision projection for the transport execution family.
  """

  alias Cadence.Dashboards.{
    DataLinks,
    Field,
    Frame,
    PlannedSourceRequest,
    RuntimeCacheKey,
    ScopeContext
  }

  alias Cadence.OperationalEvents

  @observable_id "comms.transport.execution_state"
  @states [:initialized, :transport_event_handled, :control_input_handled, :timer_handled]

  @spec resolve(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve(
        %PlannedSourceRequest{} = request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    intervals_fun =
      Keyword.get(
        opts,
        :transport_execution_intervals_fun,
        &default_intervals/3
      )

    intervals_fun.(organization_id, mission_id, adapter_opts)
    |> rows(request)
    |> then(&frame(request, &1, source_context))
  end

  @spec rows([term()], PlannedSourceRequest.t()) :: [map()]
  def rows(intervals, %PlannedSourceRequest{} = request) do
    intervals
    |> Enum.map(&row/1)
    |> Enum.filter(&(matches_scope?(&1, request) and overlaps_request?(&1, request)))
    |> Enum.sort_by(&datetime_sort_key(&1.starts_at))
    |> apply_request_limit(request)
  end

  @spec frame(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def frame(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:transport_execution_state_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: values(rows, :starts_at),
          metadata: %{axis: :occurred_at}
        },
        field("ends_at", :time, rows, :ends_at),
        field("observable_id", :string, rows, :observable_id),
        field("resource_id", :string, rows, :resource_id),
        field("lane_id", :string, rows, :lane_id),
        field("label", :string, rows, :label),
        field("scope_kind", :enum, rows, :scope_kind),
        field("transport_id", :string, rows, :transport_id),
        field("source_endpoint_id", :string, rows, :source_endpoint_id),
        field("ground_station_id", :string, rows, :ground_station_id),
        field("link_id", :string, rows, :link_id),
        field("contact_id", :string, rows, :contact_id),
        field("path_id", :string, rows, :path_id),
        field("transport_record_id", :string, rows, :transport_record_id),
        field("interval_id", :string, rows, :interval_id),
        field("source_event_id", :string, rows, :source_event_id),
        field("state", :enum, rows, :state),
        field("normalized_state", :enum, rows, :normalized_state)
      ],
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :event_history,
          supported_capability: :transport_execution_state_history,
          product_family: :comms_transport,
          state_color_policy: :transport_execution_state,
          observable_ids: observable_ids(rows),
          observable_id: @observable_id,
          returned_points: length(rows),
          warning_codes: [],
          links: operational_links(request, rows),
          evidence_refs: DataLinks.operational_interval_evidence_refs(values(rows, :interval))
        })
    }
  end

  @spec revision([term()]) :: binary()
  def revision(intervals) do
    "transport_execution_state:" <>
      RuntimeCacheKey.fingerprint(%{
        intervals:
          intervals
          |> Enum.map(&revision_entry/1)
          |> Enum.sort_by(&{&1.transport_id || "", &1.starts_at || ""})
      })
  end

  @spec default_revision(binary(), binary(), keyword()) :: binary()
  def default_revision(organization_id, mission_id, opts) do
    organization_id
    |> default_intervals(mission_id, opts)
    |> revision()
  end

  defp default_intervals(organization_id, mission_id, opts) do
    OperationalEvents.transport_execution_intervals(
      organization_id,
      mission_id,
      interval_opts(opts)
    )
  end

  defp interval_opts(opts) do
    [
      from_time: Keyword.get(opts, :from),
      to_time: Keyword.get(opts, :to),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      event_limit: Keyword.get(opts, :event_limit, 1_000)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp row(interval) do
    payload = attr(interval, :payload) || %{}
    transport_id = attr(interval, :subject_id) || attr(payload, :capability_instance_id)
    state = state(attr(payload, :event_kind))

    %{
      observable_id: @observable_id,
      resource_id: transport_id,
      lane_id: transport_id,
      label: "Transport execution / #{transport_id}",
      scope_kind: :transport,
      transport_id: transport_id,
      source_endpoint_id:
        attr(payload, :source_endpoint_id) || attr(payload, :source_endpoint_ref),
      ground_station_id: attr(payload, :ground_station_id) || attr(payload, :antenna_id),
      link_id: attr(payload, :link_id) || attr(payload, :link_assignment_id),
      contact_id: attr(payload, :contact_id) || attr(payload, :realized_contact_id),
      path_id: attr(payload, :path_id),
      transport_record_id: attr(payload, :transport_record_id),
      interval_id: attr(interval, :interval_id),
      source_event_id: attr(interval, :source_event_id),
      state: state,
      normalized_state: state,
      starts_at: attr(interval, :starts_at),
      ends_at: attr(interval, :ends_at),
      interval: interval
    }
  end

  defp revision_entry(interval) do
    payload = attr(interval, :payload) || %{}

    %{
      interval_id: attr(interval, :interval_id),
      transport_id: attr(interval, :subject_id) || attr(payload, :capability_instance_id),
      transport_record_id: attr(payload, :transport_record_id),
      contact_id: attr(payload, :contact_id) || attr(payload, :realized_contact_id),
      path_id: attr(payload, :path_id),
      event_kind: attr(payload, :event_kind),
      starts_at: attr(interval, :starts_at),
      ends_at: attr(interval, :ends_at),
      source_event_id: attr(interval, :source_event_id)
    }
  end

  defp state(value) when value in @states, do: value

  defp state(value) when is_binary(value) do
    normalized = value |> String.downcase() |> String.replace("-", "_")
    Enum.find(@states, &(Atom.to_string(&1) == normalized)) || :unknown
  end

  defp state(_value), do: :unknown

  defp matches_scope?(row, request) do
    matches_scope_id?(row.transport_id, scope_ids(request, :transport)) and
      matches_scope_id?(row.source_endpoint_id, scope_ids(request, :source_endpoint)) and
      matches_scope_id?(row.ground_station_id, scope_ids(request, :ground_station)) and
      matches_scope_id?(row.link_id, scope_ids(request, :link)) and
      matches_scope_id?(row.contact_id, scope_ids(request, :contact))
  end

  defp overlaps_request?(row, request) do
    from_time = request_time_bound(request, [:from, :start, :start_time])
    to_time = request_time_bound(request, [:to, :end, :end_time])

    starts_before_to? =
      is_nil(to_time) or
        (match?(%DateTime{}, row.starts_at) and DateTime.compare(row.starts_at, to_time) == :lt)

    ends_after_from? =
      is_nil(from_time) or is_nil(row.ends_at) or
        (match?(%DateTime{}, row.ends_at) and DateTime.compare(row.ends_at, from_time) == :gt)

    starts_before_to? and ends_after_from?
  end

  defp scope_ids(%PlannedSourceRequest{} = request, kind) do
    primary_ids =
      if ScopeContext.primary_kind(request.scope_context) in [kind, Atom.to_string(kind)] do
        ScopeContext.primary_ids(request.scope_context)
      else
        []
      end

    typed_id = ScopeContext.scope_id(request.scope_context, kind)

    [typed_id | primary_ids]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp matches_scope_id?(_value, []), do: true
  defp matches_scope_id?(value, ids), do: value in ids

  defp request_time_bound(%PlannedSourceRequest{} = request, keys) do
    request.time_context
    |> first_context_value(keys)
    |> normalize_time_bound()
  end

  defp first_context_value(context, keys), do: Enum.find_value(keys, &context_value(context, &1))

  defp normalize_time_bound(nil), do: nil
  defp normalize_time_bound(%DateTime{} = value), do: value

  defp normalize_time_bound(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp normalize_time_bound(_value), do: nil

  defp apply_request_limit(rows, %PlannedSourceRequest{} = request) do
    case context_value(request.sampling, :limit) do
      limit when is_integer(limit) and limit > 0 -> Enum.take(rows, limit)
      _other -> rows
    end
  end

  defp operational_links(request, rows) do
    DataLinks.operational_resource_links(request, rows, source: :frame) ++
      DataLinks.operational_event_links(request, rows, source: :frame)
  end

  defp field(name, kind, rows, key) do
    %Field{name: name, kind: kind, values: values(rows, key)}
  end

  defp values(rows, key), do: Enum.map(rows, &attr(&1, key))

  defp observable_ids(rows) do
    rows
    |> values(:observable_id)
    |> Enum.uniq()
  end

  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp datetime_sort_key(_datetime), do: 0

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil
end
