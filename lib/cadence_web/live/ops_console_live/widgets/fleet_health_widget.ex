defmodule CadenceWeb.OpsConsoleLive.Widgets.FleetHealthWidget do
  @moduledoc """
  Phoenix LiveComponent for displaying fleet/constellation health overview.

  Shows:
  - Aggregated health bars by group
  - Expandable groups with target details
  - Target selection for drill-down

  ## Usage

      <.live_component
        module={FleetHealthWidget}
        id="fleet-widget-1"
        widget_id="widget-abc"
        targets={@targets}
        fleet_health={@fleet_health}
        config={%{
          "group_by" => "type",
          "show_details" => true
        }}
        on_configure={JS.push("open_widget_config")}
        on_select_target={JS.push("select_target")}
      />
  """
  use CadenceWeb, :live_component

  import CadenceWeb.WidgetComponents

  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket) do
    {:ok, assign(socket, expanded_groups: MapSet.new(), selected_target: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("toggle_group", %{"group" => group}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded_groups, group) do
        MapSet.delete(socket.assigns.expanded_groups, group)
      else
        MapSet.put(socket.assigns.expanded_groups, group)
      end

    {:noreply, assign(socket, :expanded_groups, expanded)}
  end

  @impl true
  def handle_event("select_target", %{"id" => target_id}, socket) do
    socket = assign(socket, :selected_target, target_id)

    # Notify parent if handler provided
    if socket.assigns[:on_select_target] do
      send(self(), {:target_selected, socket.assigns.widget_id, target_id})
    end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    config = assigns[:config] || %{}
    targets = assigns[:targets] || []
    fleet_health = assigns[:fleet_health] || %{percentage: 100, total: 0, healthy: 0}
    title = config["title"] || "Fleet Health"
    group_by = config["group_by"] || "type"

    # Group targets
    groups = group_targets(targets, group_by)

    assigns =
      assigns
      |> assign(:title, title)
      |> assign(:groups, groups)
      |> assign(:fleet_health, fleet_health)

    ~H"""
    <.widget
      id={@widget_id}
      title={@title}
      on_configure={@on_configure && JS.push("open_widget_config", value: widget_config_value(@widget_id, "fleet_health", @config))}
    >
      <div class="fleet-health-widget">
        <!-- Overall health summary -->
        <div class="health-summary mb-4">
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm font-medium">Fleet Status</span>
            <span class={["text-sm font-bold", health_color_class(@fleet_health.percentage)]}>
              {@fleet_health.percentage}%
            </span>
          </div>
          <div class="w-full bg-base-300 rounded-full h-2">
            <div
              class={["h-2 rounded-full transition-all", health_bar_class(@fleet_health.percentage)]}
              style={"width: #{@fleet_health.percentage}%"}
            >
            </div>
          </div>
          <div class="text-xs text-base-content/50 mt-1">
            {@fleet_health.healthy}/{@fleet_health.total} targets healthy
          </div>
        </div>

        <!-- Groups -->
        <div class="groups-list space-y-2">
          <div
            :for={{group_name, group_targets} <- @groups}
            class={["fleet-group", has_issues?(group_targets) && "has-issues"]}
          >
            <button
              type="button"
              class="group-header w-full flex items-center justify-between p-2 hover:bg-base-200 rounded transition-colors"
              phx-click="toggle_group"
              phx-value-group={group_name}
              phx-target={@myself}
            >
              <div class="flex items-center gap-2">
                <.icon
                  name={if MapSet.member?(@expanded_groups, group_name), do: "hero-chevron-down", else: "hero-chevron-right"}
                  class="w-3 h-3"
                />
                <span class="text-sm font-medium">{group_name}</span>
                <span class="text-xs text-base-content/50">({length(group_targets)})</span>
              </div>
              <div class="flex items-center gap-1">
                <.severity_dot
                  :for={target <- Enum.take(group_targets, 5)}
                  severity={target_status_severity(target.status)}
                  size="sm"
                />
                <span :if={length(group_targets) > 5} class="text-xs text-base-content/40">
                  +{length(group_targets) - 5}
                </span>
              </div>
            </button>

            <div
              :if={MapSet.member?(@expanded_groups, group_name)}
              class="group-targets pl-5 pr-2 pb-2 space-y-1"
            >
              <button
                :for={target <- group_targets}
                type="button"
                class={[
                  "target-item w-full flex items-center gap-2 p-1.5 rounded text-left transition-colors",
                  @selected_target == target.id && "bg-primary/10 border-l-2 border-primary",
                  @selected_target != target.id && "hover:bg-base-200"
                ]}
                phx-click="select_target"
                phx-value-id={target.id}
                phx-target={@myself}
              >
                <.severity_dot severity={target_status_severity(target.status)} size="sm" />
                <span class="text-xs truncate flex-1">{target.name || target.identifier}</span>
                <span class="text-xs text-base-content/40">{target.status}</span>
              </button>
            </div>
          </div>
        </div>

        <.widget_empty
          :if={@groups == []}
          icon="hero-server-stack"
          message="No targets"
        />
      </div>
    </.widget>
    """
  end

  defp group_targets(targets, "type") do
    targets
    |> Enum.group_by(& &1.type)
    |> Enum.sort_by(fn {name, _} -> name end)
  end

  defp group_targets(targets, "status") do
    targets
    |> Enum.group_by(& &1.status)
    |> Enum.sort_by(fn {name, _} -> name end)
  end

  defp group_targets(targets, _) do
    [{"All Targets", targets}]
  end

  defp has_issues?(targets) do
    Enum.any?(targets, fn t ->
      t.status not in [:active, :online, :nominal, :healthy]
    end)
  end

  defp target_status_severity(:active), do: :nominal
  defp target_status_severity(:online), do: :nominal
  defp target_status_severity(:nominal), do: :nominal
  defp target_status_severity(:healthy), do: :nominal
  defp target_status_severity(:standby), do: :warning
  defp target_status_severity(:degraded), do: :warning
  defp target_status_severity(:offline), do: :critical
  defp target_status_severity(:error), do: :critical
  defp target_status_severity(:failed), do: :critical
  defp target_status_severity(_), do: :info

  defp health_color_class(pct) when pct >= 90, do: "text-success"
  defp health_color_class(pct) when pct >= 70, do: "text-warning"
  defp health_color_class(_), do: "text-error"

  defp health_bar_class(pct) when pct >= 90, do: "bg-success"
  defp health_bar_class(pct) when pct >= 70, do: "bg-warning"
  defp health_bar_class(_), do: "bg-error"

  defp widget_config_value(widget_id, widget_type, config) do
    %{widget_id: widget_id, widget_type: widget_type, config: config}
  end
end
