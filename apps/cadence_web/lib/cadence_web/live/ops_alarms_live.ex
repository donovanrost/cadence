defmodule CadenceWeb.OpsAlarmsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Reads.Alarms

  @filter_keys ~w(severity state spacecraft_id query)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Alarms")
     |> assign(:ops_nav_item, :alarms)
     |> assign(:alarm_summary, empty_summary())
     |> assign(:alarm_spacecraft_ids, [])
     |> assign(:alarms_empty?, true)
     |> assign(:filter_form, to_form(%{}, as: :filters))
     |> stream(:alarms, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = params |> Map.take(@filter_keys) |> Map.put_new("state", "active")
    %{current_scope: scope, current_mission: mission} = socket.assigns

    snapshot =
      Alarms.snapshot(scope.organization_id, mission.mission_id, filters: filters)

    {:noreply,
     socket
     |> assign(:alarm_summary, snapshot.summary)
     |> assign(:alarm_spacecraft_ids, snapshot.spacecraft_ids)
     |> assign(:alarms_empty?, snapshot.rows == [])
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> stream(:alarms, snapshot.rows, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: alarms_path(socket, filters))}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    {:noreply, push_patch(socket, to: alarms_path(socket, %{}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-alarms-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto flex max-w-[100rem] flex-col gap-5 xl:flex-row xl:items-end xl:justify-between">
            <div>
              <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
                Mission operations / live conditions
              </p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight">Alarms</h1>
              <p class="mt-2 max-w-3xl text-sm text-base-content/60">
                The latest evaluated limit state for every mission point. This surface is read-only;
                definitions and lifecycle changes remain in the Limits application.
              </p>
            </div>
            <div id="alarm-summary" class="flex flex-wrap gap-2" data-alarm-active-count={@alarm_summary.active_count}>
              <.severity_badge severity={:critical} count={@alarm_summary.critical_count} label="Critical" />
              <.severity_badge severity={:warning} count={@alarm_summary.warning_count} label="Warning" />
              <.severity_badge severity={:info} count={@alarm_summary.info_count} label="Info" />
            </div>
          </div>
        </header>

        <div class="mx-auto max-w-[100rem] space-y-4 p-5 lg:p-7">
          <.form
            for={@filter_form}
            id="alarm-filter-form"
            phx-change="filter"
            class="grid gap-3 border border-base-300 bg-base-200/25 p-3 md:grid-cols-4"
          >
            <.input
              field={@filter_form[:severity]}
              type="select"
              label="Severity"
              options={[{"All", "all"}, {"Critical", "critical"}, {"Warning", "warning"}, {"Info", "info"}, {"Nominal", "nominal"}]}
            />
            <.input
              field={@filter_form[:state]}
              type="select"
              label="State"
              options={[{"Active conditions", "active"}, {"All states", "all"}, {"Nominal only", "nominal"}]}
            />
            <.input
              field={@filter_form[:spacecraft_id]}
              type="select"
              label="Spacecraft"
              options={[{"All spacecraft", "all"} | Enum.map(@alarm_spacecraft_ids, &{&1, &1})]}
            />
            <.input
              field={@filter_form[:query]}
              type="search"
              label="Subsystem or point"
              placeholder="EPS, voltage, HK.temp"
              phx-debounce="250"
            />
          </.form>

          <div class="flex items-center justify-between gap-3">
            <p class="font-mono text-[0.65rem] uppercase tracking-wider text-base-content/45">
              Projection observed {timestamp(@alarm_summary.observed_at)}
            </p>
            <button id="alarm-filter-reset" type="button" phx-click="reset_filters" class="btn btn-ghost btn-xs">
              Reset filters
            </button>
          </div>

          <section class="overflow-hidden border border-base-300 bg-base-100">
            <div id="alarm-conditions" phx-update="stream">
              <div id="alarm-conditions-empty" class="hidden only:flex min-h-48 flex-col items-center justify-center px-6 text-center">
                <.icon name="hero-check-circle" class="h-8 w-8 text-success/70" />
                <p class="mt-3 font-semibold">No matching conditions</p>
                <p class="mt-1 text-sm text-base-content/55">
                  The current projection is available; no rows match this filter.
                </p>
              </div>
              <article
                :for={{id, alarm} <- @streams.alarms}
                id={id}
                data-alarm-condition={alarm.limit_event_id}
                data-alarm-severity={alarm.severity}
                data-alarm-state={alarm.limit_state}
                class="grid gap-3 border-b border-base-300/60 px-4 py-3 last:border-b-0 lg:grid-cols-[10rem_minmax(0,1fr)_12rem_12rem_auto] lg:items-center"
              >
                <.severity_badge severity={alarm.severity} label={state_label(alarm.limit_state)} />
                <div class="min-w-0">
                  <p class="truncate font-semibold">{alarm.point_name}</p>
                  <p class="truncate font-mono text-[0.68rem] text-base-content/50">
                    {alarm.spacecraft_id || "Mission"} · {alarm.subsystem} · {alarm.point_id}
                  </p>
                </div>
                <div>
                  <p class="hud-label">Value</p>
                  <p class="mt-1 font-mono text-sm">{format_value(alarm.evaluated_value)}</p>
                </div>
                <div>
                  <p class="hud-label">Observed</p>
                  <p class="mt-1 font-mono text-[0.68rem]">{timestamp(alarm.receipt_time)}</p>
                </div>
                <div class="flex justify-end gap-1">
                  <.link
                    id={"alarm-open-sample-#{alarm.limit_event_id}"}
                    navigate={explore_path(@current_mission.mission_id, alarm)}
                    class="btn btn-ghost btn-xs"
                    title="Open exact sample and evidence"
                  >
                    <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" /> Evidence
                  </.link>
                  <.link
                    id={"alarm-open-definition-#{alarm.limit_event_id}"}
                    navigate={definition_path(@current_mission.mission_id, alarm)}
                    class="btn btn-ghost btn-xs"
                    title="Open limit definition and activation history"
                  >
                    <.icon name="hero-document-magnifying-glass" class="h-3.5 w-3.5" /> Definition
                  </.link>
                </div>
              </article>
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp alarms_path(socket, filters) do
    query = filters |> Enum.reject(fn {_key, value} -> value in [nil, "", "all"] end) |> Map.new()
    ~p"/missions/#{socket.assigns.current_mission.mission_id}/ops/alarms?#{query}"
  end

  defp explore_path(mission_id, alarm) do
    query = %{
      point_id: alarm.point_id,
      spacecraft_id: alarm.spacecraft_id,
      sample_id: alarm.sample_id,
      selected_time: DateTime.to_iso8601(alarm.receipt_time)
    }

    ~p"/missions/#{mission_id}/ops/explore?#{query}"
  end

  defp definition_path(mission_id, alarm) do
    query = %{
      limit_definition_id: alarm.limit_definition_id,
      limit_definition_version: alarm.limit_definition_version,
      point_id: alarm.point_id
    }

    ~p"/missions/#{mission_id}/applications/limits/activity?#{query}"
  end

  defp state_label(state), do: state |> to_string() |> String.replace("_", " ")
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)
  defp timestamp(nil), do: "not observed"
  defp timestamp(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")

  defp empty_summary do
    %{
      observed_at: nil,
      active_count: 0,
      critical_count: 0,
      warning_count: 0,
      info_count: 0
    }
  end
end
