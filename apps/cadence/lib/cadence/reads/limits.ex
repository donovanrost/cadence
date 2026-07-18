defmodule Cadence.Reads.Limits do
  @moduledoc """
  Read-side queries for canonical limit events and latest limit-state
  projection.
  """

  import Ecto.Query

  alias Cadence.Limits
  alias Cadence.Limits.{DefinitionInterval, DefinitionLifecycleEvent, Event}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Telemetry.SourceFilters

  alias Cadence.Persistence.Schemas.{
    TelemetryLatestLimitStateRow,
    TelemetryLimitEventRow
  }

  alias Cadence.Repo

  @mission_scope_key "__mission__"

  @spec latest_state(binary(), binary(), keyword()) :: Event.t() | nil
  def latest_state(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    latest_state_for_scope(nil, mission_id, point_id, opts)
  end

  @spec latest_state(binary(), binary(), binary(), keyword()) :: Event.t() | nil
  def latest_state(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    latest_state_for_scope(organization_id, mission_id, point_id, opts)
  end

  defp latest_state_for_scope(organization_id, mission_id, point_id, opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    cond do
      replay_run_id?(opts) ->
        latest_event_as_of(
          organization_id,
          mission_id,
          point_id,
          spacecraft_id,
          Keyword.get(opts, :to_receipt_time),
          opts
        )

      match?(%DateTime{}, Keyword.get(opts, :to_receipt_time)) ->
        latest_event_as_of(
          organization_id,
          mission_id,
          point_id,
          spacecraft_id,
          Keyword.get(opts, :to_receipt_time),
          opts
        )

      true ->
        latest_projected_state(organization_id, mission_id, point_id, spacecraft_id, opts)
    end
  end

  defp latest_event_as_of(
         organization_id,
         mission_id,
         point_id,
         spacecraft_id,
         to_receipt_time,
         opts
       ) do
    TelemetryLimitEventRow
    |> scoped_event_query(organization_id, mission_id, point_id)
    |> maybe_filter_event_spacecraft(spacecraft_id)
    |> maybe_filter_to_receipt_time(to_receipt_time)
    |> order_history(:desc)
    |> Repo.all()
    |> rows_to_events()
    |> filter_source_events(opts)
    |> List.first()
  end

  defp latest_projected_state(organization_id, mission_id, point_id, spacecraft_id, opts) do
    TelemetryLatestLimitStateRow
    |> scoped_latest_query(organization_id, mission_id, point_id)
    |> maybe_filter_latest_spacecraft(spacecraft_id, opts)
    |> order_by([state_row], desc: state_row.receipt_time, desc: state_row.limit_event_id)
    |> Repo.all()
    |> rows_to_events()
    |> filter_source_events(opts)
    |> List.first()
  end

  defp scoped_event_query(query, nil, mission_id, point_id) do
    where(
      query,
      [event_row],
      event_row.mission_id == ^mission_id and event_row.point_id == ^point_id
    )
  end

  defp scoped_event_query(query, organization_id, mission_id, point_id) do
    where(
      query,
      [event_row],
      event_row.organization_id == ^organization_id and event_row.mission_id == ^mission_id and
        event_row.point_id == ^point_id
    )
  end

  defp scoped_latest_query(query, nil, mission_id, point_id) do
    where(
      query,
      [state_row],
      state_row.mission_id == ^mission_id and state_row.point_id == ^point_id
    )
  end

  defp scoped_latest_query(query, organization_id, mission_id, point_id) do
    where(
      query,
      [state_row],
      state_row.organization_id == ^organization_id and state_row.mission_id == ^mission_id and
        state_row.point_id == ^point_id
    )
  end

  @spec latest_states_for_mission(binary(), keyword()) :: [Event.t()]
  def latest_states_for_mission(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    TelemetryLatestLimitStateRow
    |> where([state_row], state_row.mission_id == ^mission_id)
    |> maybe_filter_latest_spacecraft(spacecraft_id, opts)
    |> order_by([state_row], asc: state_row.point_name)
    |> Repo.all()
    |> rows_to_events()
    |> filter_source_events(opts)
  end

  @spec latest_states_for_mission(binary(), binary(), keyword()) :: [Event.t()]
  def latest_states_for_mission(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    TelemetryLatestLimitStateRow
    |> where(
      [state_row],
      state_row.organization_id == ^organization_id and state_row.mission_id == ^mission_id
    )
    |> maybe_filter_latest_spacecraft(spacecraft_id, opts)
    |> order_by([state_row], asc: state_row.point_name)
    |> Repo.all()
    |> rows_to_events()
    |> filter_source_events(opts)
  end

  @spec latest_states_for_points(binary(), [binary()], [binary() | nil]) :: [Event.t()]
  def latest_states_for_points(mission_id, point_ids, spacecraft_ids)
      when is_binary(mission_id) and is_list(point_ids) and is_list(spacecraft_ids) do
    scope_ids = spacecraft_ids |> Enum.map(&spacecraft_scope_id/1) |> Enum.uniq()

    TelemetryLatestLimitStateRow
    |> where(
      [state_row],
      state_row.mission_id == ^mission_id and state_row.point_id in ^point_ids and
        state_row.spacecraft_scope_id in ^scope_ids
    )
    |> Repo.all()
    |> Enum.map(&TelemetryLatestLimitStateRow.to_domain/1)
  end

  @spec event_history(binary(), binary(), keyword()) :: [Event.t()]
  def event_history(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    order = Keyword.get(opts, :order, :desc)
    from_receipt_time = Keyword.get(opts, :from_receipt_time)
    to_receipt_time = Keyword.get(opts, :to_receipt_time)

    TelemetryLimitEventRow
    |> where([event_row], event_row.mission_id == ^mission_id and event_row.point_id == ^point_id)
    |> maybe_filter_event_spacecraft(spacecraft_id)
    |> maybe_filter_from_receipt_time(from_receipt_time)
    |> maybe_filter_to_receipt_time(to_receipt_time)
    |> order_history(order)
    |> Repo.all()
    |> rows_to_events()
    |> filter_source_events(opts)
    |> Enum.take(limit)
  end

  @spec event_history(binary(), binary(), binary(), keyword()) :: [Event.t()]
  def event_history(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    order = Keyword.get(opts, :order, :desc)
    from_receipt_time = Keyword.get(opts, :from_receipt_time)
    to_receipt_time = Keyword.get(opts, :to_receipt_time)

    TelemetryLimitEventRow
    |> where(
      [event_row],
      event_row.organization_id == ^organization_id and event_row.mission_id == ^mission_id and
        event_row.point_id == ^point_id
    )
    |> maybe_filter_event_spacecraft(spacecraft_id)
    |> maybe_filter_from_receipt_time(from_receipt_time)
    |> maybe_filter_to_receipt_time(to_receipt_time)
    |> order_history(order)
    |> Repo.all()
    |> rows_to_events()
    |> filter_source_events(opts)
    |> Enum.take(limit)
  end

  @spec definition_intervals(binary(), binary(), keyword()) :: [DefinitionInterval.t()]
  def definition_intervals(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    definition_intervals_for_scope(nil, mission_id, point_id, opts)
  end

  @spec definition_intervals(binary(), binary(), binary(), keyword()) :: [
          DefinitionInterval.t()
        ]
  def definition_intervals(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    definition_intervals_for_scope(organization_id, mission_id, point_id, opts)
  end

  @spec watermark_result(binary(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def watermark_result(mission_id, point_id, opts \\ [])
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    latest_projection =
      TelemetryLatestLimitStateRow
      |> where(
        [state_row],
        state_row.mission_id == ^mission_id and state_row.point_id == ^point_id
      )
      |> maybe_filter_latest_spacecraft(spacecraft_id, opts)
      |> projection_watermark(:id)
      |> Repo.one()

    event_projection =
      TelemetryLimitEventRow
      |> where(
        [event_row],
        event_row.mission_id == ^mission_id and event_row.point_id == ^point_id
      )
      |> maybe_filter_event_spacecraft(spacecraft_id)
      |> projection_watermark(:limit_event_id)
      |> Repo.one()

    {:ok, merge_projection_watermarks(latest_projection, event_projection)}
  end

  @spec watermark_result(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def watermark_result(organization_id, mission_id, point_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(point_id) and
             is_list(opts) do
    spacecraft_id = Keyword.get(opts, :spacecraft_id)

    latest_projection =
      TelemetryLatestLimitStateRow
      |> where(
        [state_row],
        state_row.organization_id == ^organization_id and state_row.mission_id == ^mission_id and
          state_row.point_id == ^point_id
      )
      |> maybe_filter_latest_spacecraft(spacecraft_id, opts)
      |> projection_watermark(:id)
      |> Repo.one()

    event_projection =
      TelemetryLimitEventRow
      |> where(
        [event_row],
        event_row.organization_id == ^organization_id and event_row.mission_id == ^mission_id and
          event_row.point_id == ^point_id
      )
      |> maybe_filter_event_spacecraft(spacecraft_id)
      |> projection_watermark(:limit_event_id)
      |> Repo.one()

    {:ok, merge_projection_watermarks(latest_projection, event_projection)}
  end

  defp maybe_filter_latest_spacecraft(query, spacecraft_id, opts) do
    if Keyword.has_key?(opts, :spacecraft_id) do
      where(
        query,
        [state_row],
        state_row.spacecraft_scope_id == ^spacecraft_scope_id(spacecraft_id)
      )
    else
      query
    end
  end

  defp maybe_filter_event_spacecraft(query, nil), do: query

  defp maybe_filter_event_spacecraft(query, spacecraft_id),
    do: where(query, [event_row], event_row.spacecraft_id == ^spacecraft_id)

  defp maybe_filter_from_receipt_time(query, nil), do: query

  defp maybe_filter_from_receipt_time(query, %DateTime{} = from_receipt_time) do
    where(query, [event_row], event_row.receipt_time >= ^from_receipt_time)
  end

  defp maybe_filter_to_receipt_time(query, nil), do: query

  defp maybe_filter_to_receipt_time(query, %DateTime{} = to_receipt_time) do
    where(query, [event_row], event_row.receipt_time <= ^to_receipt_time)
  end

  defp definition_intervals_for_scope(organization_id, mission_id, point_id, opts) do
    from_time = Keyword.get(opts, :from_receipt_time) || Keyword.get(opts, :from_time)
    to_time = Keyword.get(opts, :to_receipt_time) || Keyword.get(opts, :to_time)
    interval_limit = Keyword.get(opts, :limit, 1_000)

    events =
      organization_id
      |> list_limit_lifecycle_operational_events(mission_id, opts)
      |> Enum.map(&limit_lifecycle_event_from_operational_event/1)
      |> Enum.filter(&limit_lifecycle_event_matches?(&1, point_id, opts, to_time))
      |> Enum.sort_by(&lifecycle_sort_key/1)
      |> Enum.take(interval_limit)

    definitions = definitions_by_identity(organization_id, mission_id, events)

    events
    |> build_definition_intervals(definitions)
    |> Enum.filter(&interval_overlaps?(&1, from_time, to_time))
  end

  defp list_limit_lifecycle_operational_events(nil, mission_id, opts) do
    OperationalEvents.list_events(
      mission_id,
      limit_lifecycle_operational_event_opts(opts)
    )
  end

  defp list_limit_lifecycle_operational_events(organization_id, mission_id, opts) do
    OperationalEvents.list_events(
      organization_id,
      mission_id,
      limit_lifecycle_operational_event_opts(opts)
    )
  end

  defp limit_lifecycle_operational_event_opts(opts) do
    [
      category: :limits,
      source_record_kind: :limit_definition_lifecycle_event,
      order: :asc,
      limit: Keyword.get(opts, :event_limit, operational_event_limit(opts))
    ]
  end

  defp operational_event_limit(opts) do
    max(Keyword.get(opts, :limit, 1_000) * 4, 1_000)
  end

  defp limit_lifecycle_event_from_operational_event(%OperationalEvent{} = event) do
    struct!(
      DefinitionLifecycleEvent,
      event
      |> limit_lifecycle_identity_attrs()
      |> Map.merge(limit_lifecycle_definition_attrs(event))
      |> Map.merge(limit_lifecycle_timing_attrs(event))
    )
  end

  defp limit_lifecycle_identity_attrs(%OperationalEvent{} = event) do
    %{
      limit_definition_lifecycle_event_id: causality_value(event, :source_record_id),
      definition_activation_key:
        payload_value(event, :definition_activation_key) ||
          causality_value(event, :correlation_id),
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      point_id: payload_value(event, :point_id) || scope_value(event, :point_id),
      limit_set_name:
        payload_value(event, :limit_set_name) || scope_value(event, :limit_set_name),
      scope_type: payload_value(event, :scope_type) || scope_value(event, :scope_type),
      scope_ref: payload_value(event, :scope_ref) || scope_value(event, :scope_ref),
      realm: payload_value(event, :data_realm) || scope_value(event, :data_realm)
    }
  end

  defp limit_lifecycle_definition_attrs(%OperationalEvent{} = event) do
    %{
      event_type: limit_lifecycle_event_type(event.kind),
      limit_definition_id: payload_value(event, :limit_definition_id) || subject_id(event),
      limit_definition_version:
        payload_value(event, :limit_definition_version) ||
          current_value(event, :limit_definition_version),
      previous_limit_definition_id:
        payload_value(event, :previous_limit_definition_id) ||
          previous_value(event, :limit_definition_id),
      previous_limit_definition_version:
        payload_value(event, :previous_limit_definition_version) ||
          previous_value(event, :limit_definition_version)
    }
  end

  defp limit_lifecycle_timing_attrs(%OperationalEvent{} = event) do
    %{
      active_from:
        datetime_value(payload_value(event, :active_from)) || event.effective_at ||
          event.occurred_at,
      active_to:
        datetime_value(payload_value(event, :active_to) || current_value(event, :active_to)),
      reason: payload_value(event, :reason) || current_value(event, :reason),
      observed_at: event.occurred_at,
      payload: payload_value(event, :lifecycle_payload) || event.metadata || %{}
    }
  end

  defp limit_lifecycle_event_type(:limit_definition_registered), do: :registered
  defp limit_lifecycle_event_type(:limit_definition_activated), do: :activated
  defp limit_lifecycle_event_type(:limit_definition_superseded), do: :superseded
  defp limit_lifecycle_event_type(:limit_definition_disabled), do: :disabled
  defp limit_lifecycle_event_type(:limit_definition_retired), do: :retired
  defp limit_lifecycle_event_type(:limit_definition_lifecycle_unknown), do: :unknown
  defp limit_lifecycle_event_type(_kind), do: :unknown

  defp limit_lifecycle_event_matches?(
         %DefinitionLifecycleEvent{} = event,
         point_id,
         opts,
         to_time
       ) do
    event.point_id == point_id and
      optional_match?(event.limit_set_name, Keyword.get(opts, :limit_set_name)) and
      nullable_optional_match?(event.realm, Keyword.get(opts, :realm)) and
      nullable_optional_match?(event.scope_type, Keyword.get(opts, :scope_type)) and
      nullable_optional_match?(event.scope_ref, Keyword.get(opts, :scope_ref)) and
      active_from_before_to?(event, to_time)
  end

  defp optional_match?(_actual, nil), do: true
  defp optional_match?(_actual, ""), do: true
  defp optional_match?(actual, expected), do: enum_string(actual) == enum_string(expected)

  defp nullable_optional_match?(_actual, nil), do: true
  defp nullable_optional_match?(_actual, ""), do: true
  defp nullable_optional_match?(nil, _expected), do: true

  defp nullable_optional_match?(actual, expected),
    do: enum_string(actual) == enum_string(expected)

  defp active_from_before_to?(_event, nil), do: true

  defp active_from_before_to?(%DefinitionLifecycleEvent{} = event, %DateTime{} = to_time) do
    DateTime.compare(event.active_from, to_time) != :gt
  end

  defp payload_value(%OperationalEvent{payload: payload}, key), do: map_value(payload, key)
  defp scope_value(%OperationalEvent{scope: scope}, key), do: map_value(scope, key)
  defp current_value(%OperationalEvent{current: current}, key), do: map_value(current, key)
  defp previous_value(%OperationalEvent{previous: previous}, key), do: map_value(previous, key)

  defp causality_value(%OperationalEvent{causality: causality}, key),
    do: map_value(causality, key)

  defp subject_id(%OperationalEvent{subject: %{id: id}}), do: id
  defp subject_id(%OperationalEvent{subject: %{"id" => id}}), do: id
  defp subject_id(%OperationalEvent{}), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp map_value(_map, _key), do: nil

  defp datetime_value(%DateTime{} = datetime), do: datetime

  defp datetime_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp datetime_value(_value), do: nil

  defp definitions_by_identity(_organization_id, _mission_id, []), do: %{}

  defp definitions_by_identity(organization_id, mission_id, events) do
    identities =
      events
      |> Enum.map(&definition_identity/1)
      |> Enum.uniq()

    organization_id
    |> Limits.list_limit_definition_versions(mission_id, identities)
    |> Map.new(fn definition ->
      {{definition.limit_definition_id, definition.version}, definition}
    end)
  end

  defp build_definition_intervals(events, definitions) do
    events
    |> Enum.group_by(& &1.definition_activation_key)
    |> Enum.flat_map(fn {_activation_key, activation_events} ->
      sorted_events = Enum.sort_by(activation_events, &lifecycle_sort_key/1)

      sorted_events
      |> Enum.with_index()
      |> Enum.map(fn {event, index} ->
        next_event = Enum.at(sorted_events, index + 1)
        active_to = event.active_to || (next_event && next_event.active_from)

        DefinitionInterval.from_event(
          event,
          active_to,
          Map.get(definitions, definition_identity(event))
        )
      end)
    end)
    |> Enum.sort_by(&interval_sort_key/1)
  end

  defp lifecycle_sort_key(%DefinitionLifecycleEvent{} = event) do
    {sortable_datetime(event.active_from), sortable_datetime(event.observed_at)}
  end

  defp interval_sort_key(%DefinitionInterval{} = interval) do
    {sortable_datetime(interval.active_from), interval.limit_set_name,
     interval.limit_definition_id}
  end

  defp definition_identity(%DefinitionLifecycleEvent{} = event) do
    {event.limit_definition_id, event.limit_definition_version}
  end

  defp interval_overlaps?(%DefinitionInterval{} = interval, nil, nil),
    do: not is_nil(interval.active_from)

  defp interval_overlaps?(%DefinitionInterval{} = interval, from_time, to_time) do
    starts_before_to? = is_nil(to_time) or DateTime.compare(interval.active_from, to_time) != :gt

    ends_after_from? =
      is_nil(from_time) or is_nil(interval.active_to) or
        DateTime.compare(interval.active_to, from_time) != :lt

    starts_before_to? and ends_after_from?
  end

  defp order_history(query, :asc),
    do: order_by(query, [event_row], asc: event_row.receipt_time, asc: event_row.limit_event_id)

  defp order_history(query, _order),
    do: order_by(query, [event_row], desc: event_row.receipt_time, desc: event_row.limit_event_id)

  defp rows_to_events(rows) when is_list(rows), do: Enum.map(rows, &row_to_event/1)

  defp row_to_event(%TelemetryLatestLimitStateRow{} = state_row),
    do: TelemetryLatestLimitStateRow.to_domain(state_row)

  defp row_to_event(%TelemetryLimitEventRow{} = event_row),
    do: TelemetryLimitEventRow.to_domain(event_row)

  defp filter_source_events(events, opts) do
    filters = SourceFilters.normalize(opts)

    if limit_event_source_filters?(filters) do
      Enum.filter(events, &source_event_matches?(&1, filters))
    else
      events
    end
  end

  defp source_event_matches?(%Event{} = event, filters) when is_map(filters) do
    storage = storage_provenance(event)

    source_realm_matches?(storage, Map.get(filters, :realm)) and
      source_value_matches?(storage, :replay_run_id, Map.get(filters, :replay_run_id)) and
      source_endpoint_matches?(storage, Map.get(filters, :source_endpoint_ids))
  end

  defp limit_event_source_filters?(filters) when is_map(filters) do
    present?(Map.get(filters, :replay_run_id)) or Map.get(filters, :realm) == "replay" or
      Map.has_key?(filters, :source_endpoint_ids)
  end

  defp storage_provenance(%Event{provenance: provenance}) when is_map(provenance) do
    provenance_value(provenance, :storage) || %{}
  end

  defp storage_provenance(%Event{}), do: %{}

  defp source_value_matches?(_storage, _key, nil), do: true

  defp source_value_matches?(storage, key, expected) do
    storage
    |> provenance_value(key)
    |> compare_source_value(expected)
  end

  defp source_realm_matches?(_storage, nil), do: true
  defp source_realm_matches?(_storage, "flight"), do: true

  defp source_realm_matches?(storage, expected),
    do: source_value_matches?(storage, :realm, expected)

  defp replay_run_id?(opts) do
    case Keyword.get(opts, :replay_run_id) do
      value when is_binary(value) -> String.trim(value) != ""
      _value -> false
    end
  end

  defp source_endpoint_matches?(_storage, nil), do: true
  defp source_endpoint_matches?(_storage, []), do: true

  defp source_endpoint_matches?(storage, expected_ids) when is_list(expected_ids) do
    case provenance_value(storage, :source_endpoint_id) do
      nil -> false
      actual -> to_string(actual) in expected_ids
    end
  end

  defp compare_source_value(nil, _expected), do: false
  defp compare_source_value(actual, expected), do: to_string(actual) == expected

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp provenance_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp provenance_value(map, key) when is_map(map), do: Map.get(map, key)
  defp provenance_value(_value, _key), do: nil

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id

  defp projection_watermark(query, count_field) do
    select(query, [row], %{
      latest_receipt_time: max(row.receipt_time),
      retention_starts_at: min(row.receipt_time),
      sample_count: count(field(row, ^count_field))
    })
  end

  defp merge_projection_watermarks(left, right) do
    latest_receipt_time = latest_datetime([left, right], :latest_receipt_time)
    sample_count = sample_count(left) + sample_count(right)

    %{
      complete_through: latest_receipt_time,
      latest_receipt_time: latest_receipt_time,
      retention_starts_at: earliest_datetime([left, right], :retention_starts_at),
      sample_count: sample_count,
      confidence: watermark_confidence(latest_receipt_time, sample_count),
      projection_sources: %{
        latest_state_count: sample_count(left),
        event_count: sample_count(right)
      }
    }
  end

  defp sample_count(nil), do: 0
  defp sample_count(%{sample_count: count}) when is_integer(count), do: count
  defp sample_count(_projection), do: 0

  defp latest_datetime(projections, key) do
    projections
    |> datetimes(key)
    |> Enum.reduce(nil, &later_datetime/2)
  end

  defp earliest_datetime(projections, key) do
    projections
    |> datetimes(key)
    |> Enum.reduce(nil, &earlier_datetime/2)
  end

  defp datetimes(projections, key) do
    projections
    |> Enum.map(fn projection -> projection && Map.get(projection, key) end)
    |> Enum.reject(&is_nil/1)
  end

  defp earlier_datetime(datetime, nil), do: datetime
  defp earlier_datetime(datetime, minimum), do: compare_datetime(datetime, minimum, :lt)

  defp later_datetime(datetime, nil), do: datetime
  defp later_datetime(datetime, maximum), do: compare_datetime(datetime, maximum, :gt)

  defp compare_datetime(datetime, other, comparison) do
    if DateTime.compare(datetime, other) == comparison, do: datetime, else: other
  end

  defp watermark_confidence(%DateTime{}, sample_count) when sample_count > 0, do: :best_effort
  defp watermark_confidence(_latest_receipt_time, _sample_count), do: :unknown

  defp sortable_datetime(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp sortable_datetime(nil), do: 0

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value
end
