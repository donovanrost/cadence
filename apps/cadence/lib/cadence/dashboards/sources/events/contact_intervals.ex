defmodule Cadence.Dashboards.Sources.Events.ContactIntervals do
  @moduledoc false

  import Cadence.Dashboards.Sources.Events.Presentation
  import Cadence.Dashboards.Sources.Events.Reads
  import Cadence.Dashboards.Sources.Events.RequestPlanning

  alias Cadence.Dashboards.{
    DataLinks,
    Field,
    Frame,
    PlannedSourceRequest,
    ScopeContext
  }

  alias Cadence.Reads.{ContactStations, OperationalState}

  def contact_interval_frame(
        %PlannedSourceRequest{} = request,
        source_binding,
        organization_id,
        mission_id,
        opts,
        limit
      ) do
    contact_opts = contact_opts(request, source_binding, limit)
    scope = interval_scope(request, organization_id, mission_id, opts)

    contacts =
      contact_intervals(request, organization_id, mission_id, contact_opts, opts)
      |> Enum.filter(fn interval ->
        interval_overlaps_request?(interval, request) and
          interval_matches_scope?(interval, scope)
      end)
      |> Enum.sort_by(&interval_sort_key/1)
      |> Enum.take(limit)

    stations = ContactStations.column(organization_id, mission_id, contacts)

    %Frame{
      frame_id: "#{request.request_id}:contact_intervals",
      source: :events,
      shape: :intervals,
      time_axis: :occurred_at,
      scope: request.scope_context,
      fields: [
        %Field{name: "starts_at", kind: :time, values: Enum.map(contacts, & &1.starts_at)},
        %Field{name: "ends_at", kind: :time, values: Enum.map(contacts, & &1.ends_at)},
        %Field{name: "kind", kind: :enum, values: Enum.map(contacts, & &1.kind)},
        %Field{name: "status", kind: :enum, values: Enum.map(contacts, & &1.status)},
        %Field{name: "label", kind: :string, values: Enum.map(contacts, & &1.label)},
        %Field{name: "contact_id", kind: :string, values: Enum.map(contacts, & &1.contact_id)},
        %Field{name: "station", kind: :string, values: stations},
        %Field{
          name: "source_event_id",
          kind: :string,
          values: Enum.map(contacts, &source_event_id/1)
        },
        # A realized contact that closed without starting (dashboards, ux 11-14): drawn at its
        # scheduled window, dashed, 'didn't start'. nil for scheduled rows and open contacts.
        %Field{
          name: "started",
          kind: :boolean,
          values: Enum.map(contacts, &Map.get(&1, :started))
        },
        %Field{
          name: "close_reason",
          kind: :string,
          values: Enum.map(contacts, &Map.get(&1, :close_reason))
        },
        %Field{
          name: "scheduled_starts_at",
          kind: :time,
          values: Enum.map(contacts, &Map.get(&1, :scheduled_starts_at))
        },
        %Field{
          name: "scheduled_ends_at",
          kind: :time,
          values: Enum.map(contacts, &Map.get(&1, :scheduled_ends_at))
        }
      ],
      meta:
        common_meta(request, source_binding)
        |> Map.merge(%{
          family: :contacts,
          product: :contact_intervals,
          projection: contact_interval_projection(request),
          returned_intervals: length(contacts),
          truncated?: length(contacts) == limit,
          evidence: contact_interval_evidence_refs(contacts),
          links:
            DataLinks.contact_links(request, Enum.map(contacts, & &1.source), source: :frame) ++
              DataLinks.operational_event_links(request, Enum.map(contacts, & &1.source),
                source: :frame
              ),
          warning_codes: []
        })
    }
  end

  defp source_event_id(interval), do: interval |> get_attr(:source) |> get_attr(:source_event_id)

  defp contact_intervals(
         %PlannedSourceRequest{} = request,
         organization_id,
         mission_id,
         opts,
         funs
       ) do
    if replay_run_id(request) do
      contact_events_fun =
        Keyword.get(funs, :contact_operational_events_fun, &default_contact_operational_events/3)

      contact_events_fun.(organization_id, mission_id, opts)
      |> Enum.map(&operational_contact_interval/1)
      |> Enum.reject(&is_nil/1)
    else
      scheduled_fun = Keyword.get(funs, :scheduled_contacts_fun, &default_scheduled_contacts/3)
      realized_fun = Keyword.get(funs, :realized_contacts_fun, &default_realized_contacts/3)

      fetch_scheduled =
        Keyword.get(funs, :scheduled_contact_fun, &default_fetch_scheduled_contact/3)

      scheduled_fun.(organization_id, mission_id, opts)
      |> Enum.map(&scheduled_contact_interval/1)
      |> Kernel.++(
        realized_fun.(organization_id, mission_id, opts)
        |> Enum.map(&realized_contact_interval(&1, organization_id, fetch_scheduled))
      )
    end
  end

  defp scheduled_contact_interval(contact) do
    %{
      kind: :scheduled_contact,
      contact_id: contact.scheduled_contact_id,
      starts_at: contact.starts_at,
      ends_at: contact.ends_at,
      status: contact.lifecycle_state,
      label: contact_label(:scheduled_contact, contact.scheduled_contact_id, contact),
      source_endpoint_refs: contact.source_endpoint_refs,
      source: contact
    }
  end

  defp operational_contact_interval(event) do
    contact_kind = operational_contact_kind(event)
    contact_id = operational_contact_id(event, contact_kind)
    starts_at = operational_contact_starts_at(event)

    if contact_id && contact_kind && starts_at do
      source =
        event
        |> operational_contact_source(contact_kind, contact_id, starts_at)
        |> compact_map()

      %{
        kind: contact_kind,
        contact_id: contact_id,
        starts_at: starts_at,
        ends_at: operational_contact_ends_at(event),
        status: operational_contact_status(event),
        label: operational_contact_label(event, contact_kind, contact_id),
        source_endpoint_refs: operational_contact_source_endpoint_refs(event),
        source: source
      }
    end
  end

  defp operational_contact_kind(event) do
    raw_kind =
      operational_contact_value(event, :contact_kind) ||
        operational_contact_value(event, :contact_type) ||
        get_attr(event, :kind)

    cond do
      scheduled_contact_kind?(raw_kind) -> :scheduled_contact
      realized_contact_kind?(raw_kind) -> :realized_contact
      true -> operational_contact_kind_from_ids(event)
    end
  end

  defp scheduled_contact_kind?(kind)
       when kind in [
              :scheduled_contact,
              "scheduled_contact",
              :scheduled_contact_interval,
              "scheduled_contact_interval",
              :contact_scheduled,
              "contact_scheduled"
            ],
       do: true

  defp scheduled_contact_kind?(_kind), do: false

  defp realized_contact_kind?(kind)
       when kind in [
              :realized_contact,
              "realized_contact",
              :realized_contact_interval,
              "realized_contact_interval",
              :contact_realized,
              "contact_realized",
              :contact_started,
              "contact_started"
            ],
       do: true

  defp realized_contact_kind?(_kind), do: false

  defp operational_contact_kind_from_ids(event) do
    cond do
      operational_contact_value(event, :realized_contact_id) -> :realized_contact
      operational_contact_value(event, :scheduled_contact_id) -> :scheduled_contact
      true -> nil
    end
  end

  defp operational_contact_id(event, :scheduled_contact) do
    operational_contact_value(event, :scheduled_contact_id) ||
      operational_contact_value(event, :contact_id) ||
      operational_contact_subject_id(event) ||
      operational_contact_source_record_id(event)
  end

  defp operational_contact_id(event, :realized_contact) do
    operational_contact_value(event, :realized_contact_id) ||
      operational_contact_value(event, :contact_id) ||
      operational_contact_subject_id(event) ||
      operational_contact_source_record_id(event)
  end

  defp operational_contact_id(_event, _kind), do: nil

  defp operational_contact_subject_id(event) do
    event
    |> get_attr(:subject)
    |> get_attr(:id)
  end

  defp operational_contact_source_record_id(event) do
    event
    |> get_attr(:causality)
    |> get_attr(:source_record_id)
  end

  defp operational_contact_starts_at(event) do
    event
    |> operational_contact_value(:starts_at)
    |> fallback(operational_contact_value(event, :start_at))
    |> fallback(operational_contact_value(event, :realized_at))
    |> fallback(get_attr(event, :effective_at))
    |> fallback(get_attr(event, :occurred_at))
    |> normalize_datetime()
  end

  defp operational_contact_ends_at(event) do
    event
    |> operational_contact_value(:ends_at)
    |> fallback(operational_contact_value(event, :end_at))
    |> fallback(operational_contact_value(event, :completed_at))
    |> fallback(operational_contact_value(event, :stopped_at))
    |> normalize_datetime()
  end

  defp operational_contact_status(event) do
    operational_contact_value(event, :status) ||
      operational_contact_value(event, :lifecycle_state) ||
      operational_contact_value(event, :state)
  end

  defp operational_contact_label(event, contact_kind, contact_id) do
    operational_contact_value(event, :label) ||
      operational_contact_value(event, :provider_contact_ref) ||
      contact_label(contact_kind, contact_id, %{provider_contact_ref: nil})
  end

  defp operational_contact_source_endpoint_refs(event) do
    event
    |> operational_contact_value(:source_endpoint_refs)
    |> fallback(operational_contact_value(event, :source_endpoint_ref))
    |> normalize_string_list()
  end

  defp operational_contact_source(event, :scheduled_contact, contact_id, starts_at) do
    %{
      kind: :scheduled_contact,
      interval_id: operational_contact_interval_id(event, contact_id),
      source_event_id: get_attr(event, :event_id),
      scheduled_contact_id: contact_id,
      starts_at: starts_at,
      ends_at: operational_contact_ends_at(event),
      lifecycle_state: operational_contact_status(event),
      provider_contact_ref: operational_contact_value(event, :provider_contact_ref),
      source_endpoint_refs: operational_contact_source_endpoint_refs(event)
    }
  end

  defp operational_contact_source(event, :realized_contact, contact_id, starts_at) do
    %{
      kind: :realized_contact,
      interval_id: operational_contact_interval_id(event, contact_id),
      source_event_id: get_attr(event, :event_id),
      realized_contact_id: contact_id,
      realized_at: starts_at,
      starts_at: starts_at,
      ends_at: operational_contact_ends_at(event),
      lifecycle_state: operational_contact_status(event),
      provider_contact_ref: operational_contact_value(event, :provider_contact_ref),
      source_endpoint_refs: operational_contact_source_endpoint_refs(event)
    }
  end

  defp operational_contact_interval_id(event, contact_id) do
    with event_id when is_binary(event_id) and event_id != "" <- get_attr(event, :event_id),
         contact_id when is_binary(contact_id) and contact_id != "" <- contact_id do
      "effective_interval:contact:#{event_id}:#{contact_id}"
    else
      _other -> nil
    end
  end

  defp operational_contact_value(event, key) do
    get_attr(get_attr(event, :current), key) ||
      get_attr(get_attr(event, :payload), key) ||
      get_attr(get_attr(event, :scope), key)
  end

  defp realized_contact_interval(contact, organization_id, fetch_scheduled) do
    %{
      kind: :realized_contact,
      contact_id: contact.realized_contact_id,
      starts_at: contact.realized_at || contact.initial_time,
      ends_at: contact_end_time(contact.metadata),
      status: contact.lifecycle_state,
      label: contact_label(:realized_contact, contact.realized_contact_id, contact),
      source_endpoint_refs: contact.source_endpoint_refs,
      source: contact,
      started: started(contact),
      close_reason: nil,
      scheduled_starts_at: nil,
      scheduled_ends_at: nil
    }
    |> never_started(contact, organization_id, fetch_scheduled)
  end

  # True once it went active (metadata.started_at is set then and only then); false only for a
  # contact closed without starting (the orphan sweep's not_started, or any closed state with no
  # started_at); nil while it's open and hasn't reached AOS (armed, pre-AOS).
  defp started(contact) do
    cond do
      get_attr(contact.metadata, :started_at) != nil -> true
      contact.lifecycle_state in [:stopped, :completed] -> false
      true -> nil
    end
  end

  # A never-started contact is drawn at the pass it belonged to: its scheduled contact's window.
  # A hand start has none, so it keeps its realized span, to the close.
  defp never_started(%{started: false} = interval, contact, organization_id, fetch_scheduled) do
    not_started = get_attr(contact.metadata, :not_started)

    interval = %{
      interval
      | close_reason: get_attr(not_started, :reason),
        ends_at: interval.ends_at || normalize_datetime(get_attr(not_started, :at))
    }

    case scheduled_window(contact, organization_id, fetch_scheduled) do
      {:ok, %{starts_at: starts_at, ends_at: ends_at}} ->
        %{
          interval
          | starts_at: starts_at,
            ends_at: ends_at,
            scheduled_starts_at: starts_at,
            scheduled_ends_at: ends_at
        }

      _no_schedule ->
        interval
    end
  end

  defp never_started(interval, _contact, _organization_id, _fetch_scheduled), do: interval

  defp scheduled_window(%{scheduled_contact_id: id} = contact, organization_id, fetch_scheduled)
       when is_binary(id),
       do: fetch_scheduled.(organization_id, contact.mission_id, id)

  defp scheduled_window(_contact, _organization_id, _fetch_scheduled), do: :none

  defp contact_label(kind, contact_id, contact) do
    case get_attr(contact, :provider_contact_ref) do
      ref when is_binary(ref) and ref != "" -> ref
      _other -> "#{kind |> Atom.to_string() |> String.replace("_", " ")} #{contact_id}"
    end
  end

  defp contact_interval_evidence_refs(contacts) do
    sources = Enum.map(contacts, & &1.source)

    sources
    |> DataLinks.contact_evidence_refs()
    |> Kernel.++(DataLinks.operational_interval_evidence_refs(sources, source: :events))
    |> Enum.uniq_by(&{&1.kind, &1.id})
  end

  defp contact_end_time(metadata) when is_map(metadata) do
    metadata
    |> get_attr(:completed_at)
    |> fallback(get_attr(metadata, :stopped_at))
    |> fallback(get_attr(metadata, :ended_at))
    |> normalize_datetime()
  end

  defp contact_end_time(_metadata), do: nil

  # The widget's scope, in the precedence mission events use (maybe_put_scope_filters/2): a
  # spacecraft keeps the contacts of its source endpoints (contacts carry endpoint refs, not a
  # spacecraft); a contact keeps that contact, a realized one also by the scheduled contact it
  # realizes; a source endpoint keeps its contacts; a mission keeps all. Until 11-14 only a
  # source-endpoint scope filtered, so a widget fixed to one spacecraft drew every spacecraft's
  # contact bands (dashboards, qa's overlay check).
  defp interval_scope(%PlannedSourceRequest{scope_context: context}, org, mission, funs) do
    spacecraft_ids = ScopeContext.scope_ids(context, :spacecraft)
    contact_ids = ScopeContext.scope_ids(context, :contact)

    cond do
      spacecraft_ids != [] ->
        {:source_endpoints, spacecraft_endpoints(org, mission, spacecraft_ids, funs)}

      contact_ids != [] ->
        {:contacts, MapSet.new(contact_ids)}

      ScopeContext.primary_kind(context) in [:source_endpoint, "source_endpoint"] and
          ScopeContext.primary_ids(context) != [] ->
        {:source_endpoints, MapSet.new(ScopeContext.primary_ids(context))}

      true ->
        :all
    end
  end

  defp spacecraft_endpoints(org, mission, spacecraft_ids, funs) do
    endpoints_fun = Keyword.get(funs, :source_endpoints_fun, &default_source_endpoints/2)
    wanted = MapSet.new(spacecraft_ids)

    for endpoint <- endpoints_fun.(org, mission),
        MapSet.member?(wanted, get_attr(endpoint, :spacecraft_id)),
        into: MapSet.new(),
        do: get_attr(endpoint, :source_endpoint_id)
  end

  defp default_source_endpoints(org, mission),
    do: OperationalState.list_source_endpoints(org, mission)

  defp interval_matches_scope?(_interval, :all), do: true

  defp interval_matches_scope?(interval, {:source_endpoints, ids}),
    do: not MapSet.disjoint?(MapSet.new(interval.source_endpoint_refs || []), ids)

  defp interval_matches_scope?(interval, {:contacts, ids}) do
    MapSet.member?(ids, interval.contact_id) or
      MapSet.member?(ids, get_attr(interval.source, :scheduled_contact_id))
  end

  defp interval_overlaps_request?(%{starts_at: nil}, %PlannedSourceRequest{}), do: false

  defp interval_overlaps_request?(interval, %PlannedSourceRequest{} = request) do
    case time_window(request) do
      {%DateTime{} = from, %DateTime{} = to} ->
        DateTime.compare(interval.starts_at, to) == :lt and
          interval_ends_after?(interval.ends_at, from)

      _window ->
        true
    end
  end

  defp interval_ends_after?(nil, %DateTime{}), do: true

  defp interval_ends_after?(%DateTime{} = ends_at, %DateTime{} = from) do
    DateTime.compare(ends_at, from) == :gt
  end

  def event_in_request_range?(event, %PlannedSourceRequest{} = request) do
    case time_window(request) do
      {%DateTime{} = from, %DateTime{} = to} ->
        DateTime.compare(event.occurred_at, from) != :lt and
          DateTime.compare(event.occurred_at, to) == :lt

      _window ->
        true
    end
  end

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
