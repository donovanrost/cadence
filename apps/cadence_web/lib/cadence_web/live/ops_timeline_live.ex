defmodule CadenceWeb.OpsTimelineLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.MissionTimeline

  @query_keys ~w(
    event_id category kind severity spacecraft_id scope_kind scope_id from to source_dashboard_id
    return_to time_mode time_axis replay_run_id realm data_view data_source_id source_binding_id
    limit_mode selected_id
  )

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Mission Timeline")
     |> assign(:ops_nav_item, :timeline)
     |> assign(:timeline_context, timeline_context(%{}))
     |> assign(:timeline_filter_form, to_form(%{}, as: :timeline))
     |> assign(:selected_event, nil)
     |> assign(:timeline_events_empty?, true)
     |> stream(:timeline_events, [], dom_id: &timeline_dom_id/1)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    context = timeline_context(params)

    events =
      MissionTimeline.list_for_mission(
        scope.organization_id,
        mission.mission_id,
        event_read_opts(context)
      )

    selected_event = selected_event(scope.organization_id, mission.mission_id, context.event_id)

    {:noreply,
     socket
     |> assign(:timeline_context, context)
     |> assign(:timeline_filter_form, to_form(filter_params(context), as: :timeline))
     |> assign(:selected_event, selected_event)
     |> assign(:timeline_events_empty?, events == [])
     |> stream(:timeline_events, events, reset: true)}
  end

  @impl true
  def handle_event("apply_timeline_filters", %{"timeline" => params}, socket) do
    mission_id = socket.assigns.current_mission.mission_id

    query =
      socket.assigns.timeline_context
      |> context_query()
      |> Map.merge(Map.take(params, ~w(category kind severity spacecraft_id from to)))
      |> Map.delete("event_id")
      |> compact_query()

    {:noreply, push_patch(socket, to: ~p"/missions/#{mission_id}/ops/timeline?#{query}")}
  end

  def handle_event("clear_timeline_selection", _params, socket) do
    mission_id = socket.assigns.current_mission.mission_id
    query = socket.assigns.timeline_context |> context_query() |> Map.delete("event_id")

    {:noreply, push_patch(socket, to: ~p"/missions/#{mission_id}/ops/timeline?#{query}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="ops-timeline-page" class="min-h-0 flex-1 overflow-y-auto">
        <div class="mx-auto max-w-[96rem] space-y-4 px-5 py-6">
          <header class="flex flex-col gap-3 border-b border-primary/20 pb-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p class="hud-label">Observe / Canonical event projection</p>
              <h1 class="mt-1 text-xl font-semibold tracking-tight">Mission Timeline</h1>
              <p class="mt-1 max-w-3xl text-sm text-base-content/60">
                Contacts, alarms, commands, source posture, catalog activation, historical repair, and runtime facts in one read-only sequence.
              </p>
            </div>
            <.link
              :if={return_path(@current_mission.mission_id, @timeline_context)}
              id="timeline-return-to-origin"
              navigate={return_path(@current_mission.mission_id, @timeline_context)}
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-arrow-uturn-left" class="h-4 w-4" /> Return to investigation
            </.link>
          </header>

          <.form
            for={@timeline_filter_form}
            id="timeline-filter-form"
            phx-submit="apply_timeline_filters"
            class="grid gap-3 border border-base-300 bg-base-200/35 p-3 md:grid-cols-3 xl:grid-cols-[10rem_12rem_10rem_minmax(12rem,1fr)_13rem_13rem_auto] xl:items-end"
          >
            <.input field={@timeline_filter_form[:category]} type="select" label="Category" options={category_options()} />
            <.input field={@timeline_filter_form[:kind]} type="text" label="Kind" placeholder="telemetry_backfill_failed" />
            <.input field={@timeline_filter_form[:severity]} type="select" label="Severity" options={severity_options()} />
            <.input field={@timeline_filter_form[:spacecraft_id]} type="text" label="Spacecraft" />
            <.input field={@timeline_filter_form[:from]} type="text" label="From" />
            <.input field={@timeline_filter_form[:to]} type="text" label="To" />
            <button id="timeline-apply-filters" type="submit" class="btn btn-sm btn-primary">
              <.icon name="hero-funnel" class="h-4 w-4" /> Apply
            </button>
          </.form>

          <div class="grid min-h-[40rem] gap-4 xl:grid-cols-[minmax(0,1fr)_28rem]">
            <section class="border border-base-300 bg-base-100">
              <div class="grid grid-cols-[10rem_7rem_minmax(10rem,1fr)_8rem] gap-3 border-b border-base-300 bg-base-200/50 px-3 py-2 text-[0.65rem] font-semibold uppercase tracking-wider text-base-content/45">
                <span>Occurred</span><span>Category</span><span>Event</span><span>Subject</span>
              </div>
              <div id="mission-timeline-events" phx-update="stream" class="divide-y divide-base-300">
                <div id="mission-timeline-events-empty" class="hidden only:block p-8 text-center text-sm text-base-content/50">
                  No canonical mission events match this context.
                </div>
                <.link
                  :for={{dom_id, event} <- @streams.timeline_events}
                  id={dom_id}
                  patch={timeline_event_path(@current_mission.mission_id, @timeline_context, event.mission_event_id)}
                  class={[
                    "grid grid-cols-[10rem_7rem_minmax(10rem,1fr)_8rem] gap-3 px-3 py-3 text-xs hover:bg-primary/5",
                    @timeline_context.event_id == event.mission_event_id && "border-l-2 border-primary bg-primary/10"
                  ]}
                  data-mission-event-kind={event.kind}
                  data-mission-event-category={event.category}
                  data-mission-event-severity={event.severity || "none"}
                >
                  <time class="font-mono text-base-content/55">{format_time(event.occurred_at)}</time>
                  <span class="font-mono">{event.category}</span>
                  <span class="min-w-0">
                    <span class="block truncate font-semibold">{event.title}</span>
                    <span class="mt-0.5 block truncate text-base-content/50">{event.summary || event.kind}</span>
                  </span>
                  <span class="truncate font-mono text-base-content/55">{event.subject_id || event.source_record_id}</span>
                </.link>
              </div>
            </section>

            <aside id="timeline-event-detail" class="border border-base-300 bg-base-200/35 p-4">
              <div :if={is_nil(@selected_event)} class="grid min-h-[20rem] place-items-center text-center">
                <div>
                  <.icon name="hero-clock" class="mx-auto h-8 w-8 text-base-content/25" />
                  <p class="mt-3 text-sm text-base-content/55">Select an event to inspect its canonical identity and evidence.</p>
                </div>
              </div>

              <div :if={@selected_event} class="space-y-4">
                <div class="flex items-start justify-between gap-3">
                  <div class="min-w-0">
                    <p class="hud-label">{@selected_event.kind}</p>
                    <h2 id="timeline-selected-event-title" class="mt-1 text-base font-semibold">{@selected_event.title}</h2>
                  </div>
                  <button id="timeline-clear-selection" type="button" phx-click="clear_timeline_selection" class="btn btn-ghost btn-xs">
                    <.icon name="hero-x-mark" class="h-4 w-4" />
                  </button>
                </div>

                <button
                  id="timeline-copy-event-link"
                  type="button"
                  phx-hook="ClipboardButton"
                  data-clipboard-text={timeline_event_path(@current_mission.mission_id, @timeline_context, @selected_event.mission_event_id)}
                  class="btn btn-xs btn-outline w-full justify-start"
                >
                  <.icon name="hero-link" class="h-3.5 w-3.5" /> Copy canonical event link
                </button>

                <dl class="grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                  <%= for row <- event_rows(@selected_event) do %>
                    <dt class="text-base-content/50">{row.label}</dt>
                    <dd class="break-all font-mono" data-timeline-event-field={row.label}>{row.value}</dd>
                  <% end %>
                </dl>

                <section class="space-y-2 border-t border-base-300 pt-4">
                  <h3 class="hud-label">Continue investigation</h3>
                  <div class="grid gap-2">
                    <.link
                      :if={event_owner_path(@current_mission.mission_id, @selected_event)}
                      id="timeline-open-event-owner"
                      navigate={event_owner_path(@current_mission.mission_id, @selected_event)}
                      class="btn btn-xs btn-outline justify-start"
                    >
                      <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" /> Open owning workflow
                    </.link>
                    <.link
                      :if={event_explore_path(@current_mission.mission_id, @selected_event, @timeline_context)}
                      id="timeline-explore-event"
                      navigate={event_explore_path(@current_mission.mission_id, @selected_event, @timeline_context)}
                      class="btn btn-xs btn-outline justify-start"
                    >
                      <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" /> Explore telemetry context
                    </.link>
                  </div>
                </section>
              </div>
            </aside>
          </div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp timeline_context(params) do
    %{
      event_id: text(params["event_id"]),
      category: text(params["category"]),
      kind: text(params["kind"]),
      severity: text(params["severity"]),
      spacecraft_id: text(params["spacecraft_id"]),
      scope_kind: text(params["scope_kind"]),
      scope_id: text(params["scope_id"]),
      from: text(params["from"]),
      to: text(params["to"]),
      source_dashboard_id: text(params["source_dashboard_id"]),
      return_to: text(params["return_to"]),
      time_mode: text(params["time_mode"]),
      time_axis: text(params["time_axis"]),
      replay_run_id: text(params["replay_run_id"]),
      realm: text(params["realm"]),
      data_view: text(params["data_view"]),
      data_source_id: text(params["data_source_id"]),
      source_binding_id: text(params["source_binding_id"]),
      selected_id: text(params["selected_id"]),
      limit_mode: text(params["limit_mode"])
    }
  end

  defp event_read_opts(context) do
    [limit: 500]
    |> maybe_put(:category, context.category)
    |> maybe_put(:kind, context.kind)
    |> maybe_put(:severity, context.severity)
    |> maybe_put(:spacecraft_id, context.spacecraft_id)
    |> maybe_put(:from_occurred_at, parse_datetime(context.from))
    |> maybe_put(:to_occurred_at, parse_datetime(context.to))
  end

  defp selected_event(_organization_id, _mission_id, nil), do: nil

  defp selected_event(organization_id, mission_id, event_id) do
    case MissionTimeline.fetch_for_mission(organization_id, mission_id, event_id) do
      {:ok, event} -> event
      {:error, :mission_event_not_found} -> nil
    end
  end

  defp timeline_event_path(mission_id, context, event_id) do
    query = context |> context_query() |> Map.put("event_id", event_id)
    ~p"/missions/#{mission_id}/ops/timeline?#{query}"
  end

  defp timeline_dom_id(event) do
    safe_id = String.replace(event.mission_event_id, ~r/[^A-Za-z0-9_-]/, "-")
    "mission-event-#{safe_id}"
  end

  defp context_query(context) do
    context
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.new()
    |> Map.take(@query_keys)
    |> compact_query()
  end

  defp filter_params(context) do
    %{
      "category" => context.category || "",
      "kind" => context.kind || "",
      "severity" => context.severity || "",
      "spacecraft_id" => context.spacecraft_id || "",
      "from" => context.from || "",
      "to" => context.to || ""
    }
  end

  defp return_path(mission_id, %{source_dashboard_id: dashboard_id} = context)
       when is_binary(dashboard_id) and context.return_to != "explore" do
    query =
      %{
        "time_mode" => context.time_mode,
        "time_axis" => context.time_axis,
        "from" => context.from,
        "to" => context.to,
        "replay_run_id" => context.replay_run_id,
        "realm" => context.realm,
        "data_view" => context.data_view,
        "selected_data_view" => context.data_view,
        "data_source_id" => context.data_source_id,
        "source_binding_id" => context.source_binding_id,
        "scope_kind" => context.scope_kind,
        "scope_id" => context.scope_id,
        "limit_mode" => context.limit_mode,
        "selected_target" => if(context.selected_id, do: "mission_event"),
        "selected_id" => context.selected_id
      }
      |> compact_query()

    ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}?#{query}"
  end

  defp return_path(mission_id, %{return_to: "explore"} = context) do
    query =
      %{
        "spacecraft_id" => context.spacecraft_id,
        "scope_kind" => context.scope_kind,
        "scope_id" => context.scope_id,
        "time_mode" => context.time_mode,
        "time_axis" => context.time_axis,
        "from" => context.from,
        "to" => context.to,
        "replay_run_id" => context.replay_run_id,
        "realm" => context.realm,
        "selection_view" => context.data_view,
        "data_source_id" => context.data_source_id,
        "source_binding_id" => context.source_binding_id,
        "source_dashboard_id" => context.source_dashboard_id,
        "limit_mode" => context.limit_mode
      }
      |> compact_query()

    ~p"/missions/#{mission_id}/ops/explore?#{query}"
  end

  defp return_path(_mission_id, _context), do: nil

  defp event_owner_path(mission_id, %Entry{} = event) do
    event_owner_path(mission_id, event, historical_event?(event))
  end

  defp event_owner_path(mission_id, %Entry{} = event, true) do
    case historical_group_id(event) do
      group_id when is_binary(group_id) ->
        ~p"/missions/#{mission_id}/ops/data-operations?#{%{group: group_id}}"

      _missing_group ->
        ~p"/missions/#{mission_id}/ops/data-operations"
    end
  end

  defp event_owner_path(
         mission_id,
         %Entry{subject_kind: :data_source, subject_id: subject_id},
         false
       )
       when is_binary(subject_id),
       do: ~p"/missions/#{mission_id}/ops/data-sources/#{subject_id}"

  defp event_owner_path(
         mission_id,
         %Entry{kind: :limit_violation, subject_id: point_id, source_record_id: event_id},
         false
       ),
       do: ~p"/missions/#{mission_id}/ops/alarms?#{%{point_id: point_id, event_id: event_id}}"

  defp event_owner_path(mission_id, %Entry{subject_kind: :command, subject_id: command_id}, false)
       when is_binary(command_id),
       do: ~p"/missions/#{mission_id}/ops/commands?#{%{command_id: command_id}}"

  defp event_owner_path(mission_id, %Entry{realized_contact_id: contact_id}, false)
       when is_binary(contact_id),
       do: ~p"/missions/#{mission_id}/ops/contacts/records/#{contact_id}"

  defp event_owner_path(mission_id, %Entry{scheduled_contact_id: contact_id}, false)
       when is_binary(contact_id),
       do: ~p"/missions/#{mission_id}/ops/contacts/records/#{contact_id}"

  defp event_owner_path(
         mission_id,
         %Entry{subject_kind: subject_kind, subject_id: contact_id},
         false
       )
       when subject_kind in [:contact, :scheduled_contact, :realized_contact] and
              is_binary(contact_id),
       do: ~p"/missions/#{mission_id}/ops/contacts/records/#{contact_id}"

  defp event_owner_path(_mission_id, %Entry{}, false), do: nil

  defp event_explore_path(mission_id, %Entry{} = event, context) do
    point_id = if event.subject_kind == :telemetry_point, do: event.subject_id

    if is_binary(point_id) do
      query =
        %{
          "point_id" => point_id,
          "spacecraft_id" => event.spacecraft_id,
          "scope_kind" => context.scope_kind,
          "scope_id" => context.scope_id,
          "time_mode" => context.time_mode || "archive",
          "time_axis" => context.time_axis,
          "from" => context.from,
          "to" => context.to,
          "replay_run_id" => context.replay_run_id,
          "realm" => context.realm,
          "selection_view" => context.data_view,
          "data_source_id" => metadata_value(event, "data_source_id"),
          "source_binding_id" => metadata_value(event, "source_binding_id"),
          "limit_mode" => context.limit_mode,
          "selected_time" => DateTime.to_iso8601(event.occurred_at)
        }
        |> compact_query()

      ~p"/missions/#{mission_id}/ops/explore?#{query}"
    end
  end

  defp historical_event?(event) do
    event.kind
    |> Atom.to_string()
    |> String.starts_with?(["telemetry_backfill_", "telemetry_import_"])
  end

  defp historical_group_id(event) do
    metadata_value(event, "request_group_id") ||
      get_in(event.metadata, ["payload", "lifecycle_payload", "request_group_id"]) ||
      get_in(event.metadata, ["payload", "backfill_run_id"]) || event.correlation_key
  end

  defp metadata_value(%Entry{metadata: metadata}, key) when is_map(metadata) do
    Map.get(metadata, key) ||
      get_in(metadata, ["scope", key]) ||
      get_in(metadata, ["payload", key])
  end

  defp event_rows(event) do
    [
      row("Event", event.mission_event_id),
      row("Occurred", format_time(event.occurred_at)),
      row("Category", event.category),
      row("Kind", event.kind),
      row("Severity", event.severity),
      row("Status", event.status),
      row("Source kind", event.source_record_kind),
      row("Source record", event.source_record_id),
      row("Subject kind", event.subject_kind),
      row("Subject", event.subject_id),
      row("Correlation", event.correlation_key),
      row("Spacecraft", event.spacecraft_id),
      row("Source endpoint", event.source_endpoint_ref)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp row(_label, nil), do: nil
  defp row(label, value), do: %{label: label, value: value}

  defp category_options,
    do: [
      {"All", ""},
      {"Operations", "operations"},
      {"Health", "health"},
      {"Runtime", "runtime"},
      {"Transport", "transport"}
    ]

  defp severity_options,
    do: [
      {"All", ""},
      {"Info", "info"},
      {"Warning", "warning"},
      {"Error", "error"},
      {"Critical", "critical"}
    ]

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp compact_query(query) do
    query
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp format_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%SZ")
  defp format_time(_datetime), do: "unknown"

  defp text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text(_value), do: nil
end
