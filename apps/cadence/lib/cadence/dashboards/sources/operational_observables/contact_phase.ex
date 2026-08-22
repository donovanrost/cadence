defmodule Cadence.Dashboards.Sources.OperationalObservables.ContactPhase do
  @moduledoc """
  Materializes contact-phase rows, frames, scope filtering, and revisions.

  The source adapter supplies scheduled contacts, realized contacts, and the
  source endpoints needed for spacecraft or ground-station scope resolution.
  This module owns the contact-phase product contract.
  """

  alias Cadence.Dashboards.{
    DataLinks,
    Field,
    Frame,
    PlannedSourceRequest,
    RuntimeCacheKey,
    ScopeContext
  }

  alias Cadence.Dashboards.Sources.OperationalObservables.LatestFreshness
  alias Cadence.Reads.OperationalState

  @observable_id "contacts.phase"

  @spec resolve_latest(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_latest(
        %PlannedSourceRequest{} = request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    {scheduled_contacts, realized_contacts} =
      contacts(organization_id, mission_id, adapter_opts, opts)

    rows =
      scheduled_contacts
      |> latest_rows(
        realized_contacts,
        resolve_scope(request, organization_id, mission_id, adapter_opts, opts)
      )
      |> LatestFreshness.annotate(request, opts)

    latest_frame(request, rows, source_context)
  end

  @spec resolve_history(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve_history(
        %PlannedSourceRequest{} = request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    {scheduled_contacts, realized_contacts} =
      contacts(organization_id, mission_id, adapter_opts, opts)

    rows =
      history_rows(
        scheduled_contacts,
        realized_contacts,
        resolve_scope(request, organization_id, mission_id, adapter_opts, opts),
        request
      )

    history_frame(request, rows, source_context)
  end

  @spec scope(PlannedSourceRequest.t(), [term()]) :: map()
  def scope(%PlannedSourceRequest{} = request, source_endpoints \\ []) do
    %{
      contact_ids: scope_ids(request, :contact),
      source_endpoint_ids: scope_ids(request, :source_endpoint),
      spacecraft_ids: scope_ids(request, :spacecraft),
      ground_station_ids: scope_ids(request, :ground_station),
      source_endpoints_by_id: Map.new(source_endpoints, &{attr(&1, :source_endpoint_id), &1})
    }
  end

  @spec source_endpoint_scope_required?(PlannedSourceRequest.t() | map()) :: boolean()
  def source_endpoint_scope_required?(%PlannedSourceRequest{} = request) do
    request
    |> scope()
    |> source_endpoint_scope_required?()
  end

  def source_endpoint_scope_required?(scope) when is_map(scope) do
    Map.get(scope, :source_endpoint_ids, []) != [] or
      Map.get(scope, :spacecraft_ids, []) != [] or
      Map.get(scope, :ground_station_ids, []) != []
  end

  @spec latest_rows([term()], [term()], map()) :: [map()]
  def latest_rows(scheduled_contacts, realized_contacts, scope) do
    contact_rows(scheduled_contacts, realized_contacts, scope)
  end

  @spec history_rows([term()], [term()], map(), PlannedSourceRequest.t()) :: [map()]
  def history_rows(
        scheduled_contacts,
        realized_contacts,
        scope,
        %PlannedSourceRequest{} = request
      ) do
    scheduled_contacts
    |> contact_rows(realized_contacts, scope)
    |> Enum.filter(&time_in_request_window?(Map.get(&1, :time), request))
    |> Enum.sort_by(&datetime_sort_key(Map.get(&1, :time)))
    |> apply_request_limit(request)
  end

  @spec latest_frame(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def latest_frame(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:contacts_phase",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: [
        field("observable_id", :string, rows, :observable_id),
        field("contact_id", :string, rows, :contact_id),
        field("contact_kind", :enum, rows, :contact_kind),
        field("phase", :enum, rows, :phase),
        field("observed_at", :time, rows, :observed_at),
        field("freshness_state", :enum, rows, :freshness_state),
        field("age_ms", :number, rows, :age_ms)
      ],
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :latest,
          supported_capability: :contacts_phase,
          observable_id: @observable_id,
          returned_points: length(rows),
          freshness_policy: latest_freshness_policy(rows),
          freshness_checked_at: latest_freshness_checked_at(rows),
          warning_codes: latest_freshness_warning_codes(rows),
          links: DataLinks.contact_links(request, Enum.map(rows, & &1.source), source: :frame)
        })
    }
  end

  @spec history_frame(PlannedSourceRequest.t(), [map()], map()) :: Frame.t()
  def history_frame(%PlannedSourceRequest{} = request, rows, source_context) do
    %Frame{
      frame_id: "#{request.request_id}:contacts_phase_history",
      source: :operational_observables,
      shape: :events,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: values(rows, :time),
          metadata: %{axis: :occurred_at}
        },
        field("observable_id", :string, rows, :observable_id),
        field("resource_id", :string, rows, :contact_id),
        %Field{name: "lane_id", kind: :string, values: Enum.map(rows, &lane_id/1)},
        %Field{name: "label", kind: :string, values: Enum.map(rows, &label/1)},
        %Field{name: "scope_kind", kind: :enum, values: Enum.map(rows, fn _row -> :contact end)},
        field("contact_id", :string, rows, :contact_id),
        field("contact_kind", :enum, rows, :contact_kind),
        field("phase", :enum, rows, :phase),
        field("normalized_state", :enum, rows, :phase)
      ],
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :event_history,
          supported_capability: :contacts_phase_history,
          observable_id: @observable_id,
          returned_points: length(rows),
          warning_codes: [],
          links: DataLinks.contact_links(request, Enum.map(rows, & &1.source), source: :frame)
        })
    }
  end

  @spec revision([term()], [term()]) :: binary()
  def revision(scheduled_contacts, realized_contacts) do
    "contacts_phase:" <>
      RuntimeCacheKey.fingerprint(%{
        scheduled_contacts:
          scheduled_contacts
          |> Enum.map(&scheduled_revision_entry/1)
          |> Enum.sort_by(&(&1.scheduled_contact_id || "")),
        realized_contacts:
          realized_contacts
          |> Enum.map(&realized_revision_entry/1)
          |> Enum.sort_by(&(&1.realized_contact_id || ""))
      })
  end

  @spec default_revision(binary(), binary(), keyword()) :: binary()
  def default_revision(organization_id, mission_id, opts) do
    revision(
      default_scheduled_contacts(organization_id, mission_id, opts),
      default_realized_contacts(organization_id, mission_id, opts)
    )
  end

  defp contacts(organization_id, mission_id, adapter_opts, opts) do
    scheduled_contacts_fun =
      Keyword.get(opts, :scheduled_contacts_fun, &default_scheduled_contacts/3)

    realized_contacts_fun =
      Keyword.get(opts, :realized_contacts_fun, &default_realized_contacts/3)

    {
      scheduled_contacts_fun.(organization_id, mission_id, adapter_opts),
      realized_contacts_fun.(organization_id, mission_id, adapter_opts)
    }
  end

  defp resolve_scope(request, organization_id, mission_id, adapter_opts, opts) do
    source_endpoints =
      if source_endpoint_scope_required?(request) do
        source_endpoints_fun =
          Keyword.get(opts, :source_endpoints_fun, &default_source_endpoints/3)

        source_endpoints_fun.(organization_id, mission_id, adapter_opts)
      else
        []
      end

    scope(request, source_endpoints)
  end

  defp default_scheduled_contacts(organization_id, mission_id, _opts) do
    OperationalState.list_scheduled_contacts(organization_id, mission_id)
  end

  defp default_realized_contacts(organization_id, mission_id, _opts) do
    OperationalState.list_realized_contacts(organization_id, mission_id)
  end

  defp default_source_endpoints(organization_id, mission_id, _opts) do
    OperationalState.list_source_endpoints(organization_id, mission_id)
  end

  defp contact_rows(scheduled_contacts, realized_contacts, scope) do
    (Enum.map(scheduled_contacts, &scheduled_row/1) ++
       Enum.map(realized_contacts, &realized_row/1))
    |> Enum.filter(&matches_scope?(&1, scope))
  end

  defp scheduled_row(contact) do
    %{
      observable_id: @observable_id,
      contact_id: attr(contact, :scheduled_contact_id),
      related_contact_id: attr(contact, :realized_contact_id),
      contact_kind: :scheduled,
      phase: attr(contact, :lifecycle_state),
      time: attr(contact, :starts_at),
      source: contact
    }
  end

  defp realized_row(contact) do
    %{
      observable_id: @observable_id,
      contact_id: attr(contact, :realized_contact_id),
      related_contact_id: attr(contact, :scheduled_contact_id),
      contact_kind: :realized,
      phase: attr(contact, :lifecycle_state),
      time: attr(contact, :realized_at) || attr(contact, :initial_time),
      source: contact
    }
  end

  defp label(row) do
    [Map.get(row, :contact_kind), Map.get(row, :contact_id)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" / ", &to_string/1)
  end

  defp lane_id(%{contact_kind: :realized, related_contact_id: related_contact_id})
       when is_binary(related_contact_id),
       do: related_contact_id

  defp lane_id(row), do: Map.get(row, :contact_id)

  defp matches_scope?(row, scope) do
    matches_contact_scope?(row, Map.get(scope, :contact_ids, [])) and
      matches_source_endpoint_scope?(row, Map.get(scope, :source_endpoint_ids, [])) and
      matches_spacecraft_scope?(
        row,
        Map.get(scope, :spacecraft_ids, []),
        Map.get(scope, :source_endpoints_by_id, %{})
      ) and
      matches_ground_station_scope?(
        row,
        Map.get(scope, :ground_station_ids, []),
        Map.get(scope, :source_endpoints_by_id, %{})
      )
  end

  defp matches_contact_scope?(_row, []), do: true

  defp matches_contact_scope?(row, contact_ids) do
    row.contact_id in contact_ids or row.related_contact_id in contact_ids
  end

  defp matches_source_endpoint_scope?(_row, []), do: true

  defp matches_source_endpoint_scope?(row, source_endpoint_ids) do
    row
    |> source_endpoint_refs()
    |> Enum.any?(&(&1 in source_endpoint_ids))
  end

  defp matches_spacecraft_scope?(_row, [], _source_endpoints_by_id), do: true

  defp matches_spacecraft_scope?(row, spacecraft_ids, source_endpoints_by_id) do
    row
    |> source_endpoints(source_endpoints_by_id)
    |> Enum.any?(&(attr(&1, :spacecraft_id) in spacecraft_ids))
  end

  defp matches_ground_station_scope?(_row, [], _source_endpoints_by_id), do: true

  defp matches_ground_station_scope?(row, ground_station_ids, source_endpoints_by_id) do
    row
    |> source_endpoints(source_endpoints_by_id)
    |> Enum.any?(&(source_endpoint_ground_station_id(&1) in ground_station_ids))
  end

  defp source_endpoints(row, source_endpoints_by_id) do
    row
    |> source_endpoint_refs()
    |> Enum.map(&Map.get(source_endpoints_by_id, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp source_endpoint_refs(row) do
    contact = Map.get(row, :source)

    [
      attr(contact, :source_endpoint_ref),
      attr(contact, :source_endpoint_refs),
      path_source_endpoint_refs(attr(contact, :paths))
    ]
    |> List.flatten()
    |> Enum.filter(&present_text?/1)
    |> Enum.uniq()
  end

  defp path_source_endpoint_refs(paths) when is_list(paths) do
    paths
    |> Enum.map(&attr(&1, :source_endpoint_ref))
    |> Enum.filter(&present_text?/1)
  end

  defp path_source_endpoint_refs(_paths), do: []

  defp source_endpoint_ground_station_id(source_endpoint) do
    metadata_attr(source_endpoint, :ground_station_id) ||
      metadata_attr(source_endpoint, :antenna_id)
  end

  defp scheduled_revision_entry(contact) do
    %{
      scheduled_contact_id: attr(contact, :scheduled_contact_id),
      realized_contact_id: attr(contact, :realized_contact_id),
      ground_station_id: attr(contact, :ground_station_id),
      source_endpoint_id: attr(contact, :source_endpoint_id),
      spacecraft_id: attr(contact, :spacecraft_id),
      lifecycle_state: attr(contact, :lifecycle_state),
      starts_at: attr(contact, :starts_at),
      ends_at: attr(contact, :ends_at),
      metadata: attr(contact, :metadata)
    }
  end

  defp realized_revision_entry(contact) do
    %{
      realized_contact_id: attr(contact, :realized_contact_id),
      scheduled_contact_id: attr(contact, :scheduled_contact_id),
      ground_station_id: attr(contact, :ground_station_id),
      source_endpoint_id: attr(contact, :source_endpoint_id),
      spacecraft_id: attr(contact, :spacecraft_id),
      lifecycle_state: attr(contact, :lifecycle_state),
      realized_at: attr(contact, :realized_at),
      initial_time: attr(contact, :initial_time),
      stopped_at: attr(contact, :stopped_at),
      metadata: attr(contact, :metadata)
    }
  end

  defp field(name, kind, rows, key) do
    %Field{name: name, kind: kind, values: values(rows, key)}
  end

  defp values(rows, key), do: Enum.map(rows, &Map.get(&1, key))

  defp latest_freshness_warning_codes(rows) do
    rows
    |> Enum.map(& &1.freshness_state)
    |> Enum.uniq()
    |> Enum.flat_map(fn
      :stale -> [:stale_data]
      :missing -> [:missing_snapshot]
      :unknown -> [:watermark_unknown]
      _state -> []
    end)
    |> Enum.uniq()
  end

  defp latest_freshness_policy([%{freshness_policy: policy} | _rows]), do: policy
  defp latest_freshness_policy(_rows), do: %{}

  defp latest_freshness_checked_at([%{freshness_checked_at: %DateTime{} = checked_at} | _rows]),
    do: checked_at

  defp latest_freshness_checked_at(_rows), do: nil

  defp scope_ids(%PlannedSourceRequest{} = request, kind) do
    primary_ids =
      if ScopeContext.primary_kind(request.scope_context) in [kind, Atom.to_string(kind)] do
        ScopeContext.primary_ids(request.scope_context)
      else
        []
      end

    typed_id = ScopeContext.scope_id(request.scope_context, kind)

    [typed_id | primary_ids]
    |> Enum.filter(&present_text?/1)
    |> Enum.uniq()
  end

  defp time_in_request_window?(%DateTime{} = time, %PlannedSourceRequest{} = request) do
    from_time = request_time_bound(request, [:from, :start, :start_time])
    to_time = request_time_bound(request, [:to, :end, :end_time])

    after_from? = is_nil(from_time) or DateTime.compare(time, from_time) != :lt
    before_to? = is_nil(to_time) or DateTime.compare(time, to_time) != :gt

    after_from? and before_to?
  end

  defp time_in_request_window?(_time, _request), do: false

  defp request_time_bound(%PlannedSourceRequest{} = request, keys) do
    request.time_context
    |> first_context_value(keys)
    |> normalize_time_bound()
  end

  defp first_context_value(context, keys) do
    Enum.find_value(keys, &attr(context, &1))
  end

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
    case attr(request.sampling, :limit) do
      limit when is_integer(limit) and limit > 0 -> Enum.take(rows, limit)
      _other -> rows
    end
  end

  defp datetime_sort_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp datetime_sort_key(_datetime), do: 0

  defp metadata_attr(value, key) when is_atom(key) do
    value
    |> attr(:metadata)
    |> attr(key)
  end

  defp attr(value, key) when is_map(value) and is_atom(key) do
    Map.get(value, key, Map.get(value, Atom.to_string(key)))
  end

  defp attr(_value, _key), do: nil

  defp present_text?(value), do: is_binary(value) and value != ""
end
