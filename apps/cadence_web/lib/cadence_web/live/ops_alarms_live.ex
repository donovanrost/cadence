defmodule CadenceWeb.OpsAlarmsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Reads.Alarms
  alias Phoenix.LiveView.JS

  @filter_keys ~w(severity state spacecraft_id query)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:alarms, dom_id: &"alarm-condition-#{&1.limit_event_id}")
     |> assign(:page_title, "Alarms")
     |> assign(:ops_nav_item, :alarms)
     |> assign(:alarms_page, page_dto())
     |> assign(:alarm_summary, summary_dto(empty_summary()))
     |> assign(:alarm_filters, filters_dto(%{}, []))
     |> assign(:alarm_reset, reset_dto())
     |> assign(:alarm_empty, empty_dto())
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
     |> assign(:alarm_summary, summary_dto(snapshot.summary))
     |> assign(:alarm_filters, filters_dto(filters, snapshot.spacecraft_ids))
     |> stream(
       :alarms,
       Enum.map(snapshot.rows, &alarm_dto(&1, mission.mission_id)),
       reset: true
     )}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: alarms_path(socket, Map.take(filters, @filter_keys)))}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    {:noreply, push_patch(socket, to: alarms_path(socket, %{}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-alarms-component"
        v-component="OpsAlarms"
        page={@alarms_page}
        summary={@alarm_summary}
        filters={@alarm_filters}
        reset={@alarm_reset}
        empty={@alarm_empty}
        alarms={@streams.alarms}
        v-on:filter={JS.push("filter")}
        v-on:reset_filters={JS.push("reset_filters")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp page_dto do
    %{
      id: "ops-alarms-page",
      header: %{
        eyebrow: "Mission operations / live conditions",
        heading: "Alarms",
        copy:
          "The latest evaluated limit state for every mission point. This surface is read-only; definitions and lifecycle changes remain in the Limits application."
      },
      conditions_id: "alarm-conditions"
    }
  end

  defp summary_dto(summary) do
    %{
      id: "alarm-summary",
      active_count: summary.active_count,
      observed: "Projection observed #{timestamp(summary.observed_at)}",
      badges: [
        %{severity: "critical", count: summary.critical_count, label: "Critical"},
        %{severity: "warning", count: summary.warning_count, label: "Warning"},
        %{severity: "info", count: summary.info_count, label: "Info"}
      ]
    }
  end

  defp filters_dto(filters, spacecraft_ids) do
    %{
      id: "alarm-filter-form",
      values: %{
        severity: Map.get(filters, "severity", "all"),
        state: Map.get(filters, "state", "active"),
        spacecraft_id: Map.get(filters, "spacecraft_id", "all"),
        query: Map.get(filters, "query", "")
      },
      fields: %{
        severity:
          select_field_dto(
            "filters_severity",
            "filters[severity]",
            "Severity",
            [
              {"All", "all"},
              {"Critical", "critical"},
              {"Warning", "warning"},
              {"Info", "info"},
              {"Nominal", "nominal"}
            ]
          ),
        state:
          select_field_dto(
            "filters_state",
            "filters[state]",
            "State",
            [
              {"Active conditions", "active"},
              {"All states", "all"},
              {"Nominal only", "nominal"}
            ]
          ),
        spacecraft_id:
          select_field_dto(
            "filters_spacecraft_id",
            "filters[spacecraft_id]",
            "Spacecraft",
            [{"All spacecraft", "all"} | Enum.map(spacecraft_ids, &{&1, &1})]
          ),
        query: %{
          id: "filters_query",
          name: "filters[query]",
          type: "search",
          label: "Subsystem or point",
          placeholder: "EPS, voltage, HK.temp",
          debounce_ms: 250
        }
      }
    }
  end

  defp select_field_dto(id, name, label, options) do
    %{
      id: id,
      name: name,
      type: "select",
      label: label,
      options:
        Enum.map(options, fn {option_label, value} ->
          %{label: option_label, value: value}
        end)
    }
  end

  defp reset_dto do
    %{id: "alarm-filter-reset", label: "Reset filters"}
  end

  defp empty_dto do
    %{
      id: "alarm-conditions-empty",
      icon: "hero-check-circle",
      heading: "No matching conditions",
      copy: "The current projection is available; no rows match this filter."
    }
  end

  defp alarm_dto(alarm, mission_id) do
    %{
      id: alarm.limit_event_id,
      limit_event_id: alarm.limit_event_id,
      severity: Atom.to_string(alarm.severity),
      limit_state: Atom.to_string(alarm.limit_state),
      state_label: state_label(alarm.limit_state),
      point_name: alarm.point_name,
      context: "#{alarm.spacecraft_id || "Mission"} · #{alarm.subsystem} · #{alarm.point_id}",
      value: %{label: "Value", display: format_value(alarm.evaluated_value)},
      observed: %{label: "Observed", display: timestamp(alarm.receipt_time)},
      evidence: %{
        id: "alarm-open-sample-#{alarm.limit_event_id}",
        href: explore_path(mission_id, alarm),
        title: "Open exact sample and evidence",
        icon: "hero-magnifying-glass",
        label: "Evidence"
      },
      definition: %{
        id: "alarm-open-definition-#{alarm.limit_event_id}",
        href: definition_path(mission_id, alarm),
        title: "Open limit definition and activation history",
        icon: "hero-document-magnifying-glass",
        label: "Definition"
      }
    }
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
