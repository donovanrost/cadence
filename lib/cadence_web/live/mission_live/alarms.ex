defmodule CadenceWeb.MissionLive.Alarms do
  @moduledoc """
  LiveView for managing alarm rules within a mission.
  """
  use CadenceWeb, :live_view

  alias Cadence.{Alarms, MissionDatabase, Targets}
  alias Cadence.Alarms.AlarmRule

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        {:noreply, apply_action(socket, socket.assigns.live_action, params)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp apply_action(socket, :index, _params) do
    mission = socket.assigns.mission
    alarm_rules = Alarms.list_rules(mission.organization_id, mission_id: mission.id)
    targets = Targets.list_targets(mission)
    definition_set_id = get_active_definition_set_id(mission.id)

    socket
    |> assign(:page_title, "Alarms")
    |> assign(:alarm_rules, alarm_rules)
    |> assign(:targets, targets)
    |> assign(:alarm_rule, nil)
    |> assign(:definition_set_id, definition_set_id)
    |> assign_coverage_modal_defaults()
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    alarm_rules = Alarms.list_rules(mission.organization_id, mission_id: mission.id)
    targets = Targets.list_targets(mission)
    definition_set_id = get_active_definition_set_id(mission.id)

    socket
    |> assign(:page_title, "New Alarm Rule")
    |> assign(:alarm_rules, alarm_rules)
    |> assign(:targets, targets)
    |> assign(:alarm_rule, %AlarmRule{
      enabled: true,
      severity: :warning,
      event_type: "telemetry_limit"
    })
    |> assign(:definition_set_id, definition_set_id)
    |> assign_coverage_modal_defaults()
  end

  defp apply_action(socket, :edit, %{"alarm_rule_id" => alarm_rule_id}) do
    mission = socket.assigns.mission
    alarm_rule = Alarms.get_rule!(alarm_rule_id)
    alarm_rules = Alarms.list_rules(mission.organization_id, mission_id: mission.id)
    targets = Targets.list_targets(mission)
    definition_set_id = get_active_definition_set_id(mission.id)

    if alarm_rule.mission_id == mission.id do
      socket
      |> assign(:page_title, "Edit Alarm Rule")
      |> assign(:alarm_rules, alarm_rules)
      |> assign(:targets, targets)
      |> assign(:alarm_rule, alarm_rule)
      |> assign(:definition_set_id, definition_set_id)
      |> assign_coverage_modal_defaults()
    else
      socket
      |> put_flash(:error, "Alarm rule not found in this mission")
      |> push_patch(to: ~p"/missions/#{mission}/alarms")
    end
  end

  # Gets the first available published definition set for the mission
  defp get_active_definition_set_id(mission_id) do
    databases = MissionDatabase.list_databases(mission_id)

    Enum.find_value(databases, fn db ->
      case MissionDatabase.get_latest_definition_set(db.id) do
        nil -> nil
        ds -> ds.id
      end
    end)
  end

  @impl true
  def handle_info({CadenceWeb.AlarmRuleLive.FormComponent, {:saved, _alarm_rule}}, socket) do
    alarm_rules =
      Alarms.list_rules(socket.assigns.mission.organization_id,
        mission_id: socket.assigns.mission.id
      )

    {:noreply, assign(socket, :alarm_rules, alarm_rules)}
  end

  def handle_info({CadenceWeb.AlarmRuleLive.FormComponent, {:deleted, _alarm_rule}}, socket) do
    alarm_rules =
      Alarms.list_rules(socket.assigns.mission.organization_id,
        mission_id: socket.assigns.mission.id
      )

    {:noreply, assign(socket, :alarm_rules, alarm_rules)}
  end

  def handle_info(
        {CadenceWeb.AlarmRuleLive.CoverageReportComponent,
         {:open_bulk_create, definition_set_id, _mission_id, target_id}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:show_coverage_modal, false)
     |> assign(:show_bulk_create_modal, true)
     |> assign(:bulk_create_definition_set_id, definition_set_id)
     |> assign(:bulk_create_target_id, target_id)
     |> assign(:bulk_create_parameters, nil)}
  end

  def handle_info(
        {CadenceWeb.AlarmRuleLive.CoverageReportComponent,
         {:create_single_rule, definition_set_id, _mission_id, qualified_name, target_id}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:show_coverage_modal, false)
     |> assign(:show_bulk_create_modal, true)
     |> assign(:bulk_create_definition_set_id, definition_set_id)
     |> assign(:bulk_create_target_id, target_id)
     |> assign(:bulk_create_parameters, [qualified_name])}
  end

  def handle_info({CadenceWeb.AlarmRuleLive.BulkCreateComponent, :cancelled}, socket) do
    {:noreply,
     socket
     |> assign(:show_bulk_create_modal, false)
     |> assign(:bulk_create_definition_set_id, nil)
     |> assign(:bulk_create_target_id, nil)
     |> assign(:bulk_create_parameters, nil)}
  end

  def handle_info(
        {CadenceWeb.AlarmRuleLive.BulkCreateComponent, {:created, created_rules}},
        socket
      ) do
    alarm_rules =
      Alarms.list_rules(socket.assigns.mission.organization_id,
        mission_id: socket.assigns.mission.id
      )

    count = length(created_rules)

    {:noreply,
     socket
     |> assign(:show_bulk_create_modal, false)
     |> assign(:bulk_create_definition_set_id, nil)
     |> assign(:bulk_create_target_id, nil)
     |> assign(:bulk_create_parameters, nil)
     |> assign(:alarm_rules, alarm_rules)
     |> put_flash(:info, "Created #{count} alarm #{if count == 1, do: "rule", else: "rules"}")}
  end

  @impl true
  def handle_event("toggle", %{"id" => rule_id}, socket) do
    rule = Alarms.get_rule!(rule_id)
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    if rule.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          result =
            if rule.enabled do
              Alarms.disable_rule(rule, scope.user.id, "Disabled via UI")
            else
              Alarms.enable_rule(rule)
            end

          case result do
            {:ok, _} ->
              alarm_rules = Alarms.list_rules(mission.organization_id, mission_id: mission.id)
              action = if rule.enabled, do: "disabled", else: "enabled"

              {:noreply,
               socket
               |> put_flash(:info, "Alarm rule #{action}")
               |> assign(:alarm_rules, alarm_rules)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to update alarm rule")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to manage alarm rules")}
      end
    else
      {:noreply, put_flash(socket, :error, "Alarm rule not found in this mission")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => rule_id}, socket) do
    rule = Alarms.get_rule!(rule_id)
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    if rule.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          case Alarms.delete_rule(rule) do
            {:ok, _} ->
              alarm_rules = Alarms.list_rules(mission.organization_id, mission_id: mission.id)

              {:noreply,
               socket
               |> put_flash(:info, "Alarm rule deleted")
               |> assign(:alarm_rules, alarm_rules)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to delete alarm rule")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to delete alarm rules")}
      end
    else
      {:noreply, put_flash(socket, :error, "Alarm rule not found in this mission")}
    end
  end

  @impl true
  def handle_event("show_coverage_analysis", _params, socket) do
    {:noreply, assign(socket, :show_coverage_modal, true)}
  end

  @impl true
  def handle_event("close_coverage_modal", _params, socket) do
    {:noreply, assign(socket, :show_coverage_modal, false)}
  end

  @impl true
  def handle_event("close_bulk_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_bulk_create_modal, false)
     |> assign(:bulk_create_definition_set_id, nil)
     |> assign(:bulk_create_target_id, nil)
     |> assign(:bulk_create_parameters, nil)}
  end

  defp assign_coverage_modal_defaults(socket) do
    socket
    |> assign(:show_coverage_modal, false)
    |> assign(:show_bulk_create_modal, false)
    |> assign(:bulk_create_definition_set_id, nil)
    |> assign(:bulk_create_target_id, nil)
    |> assign(:bulk_create_parameters, nil)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Alarm Rules
      <:subtitle>Define when alarms are generated from telemetry limit violations</:subtitle>
      <:actions>
        <.button
          phx-click="show_coverage_analysis"
          variant="secondary"
        >
          Coverage Analysis
        </.button>
        <.link patch={~p"/missions/#{@mission}/alarms/new"}>
          <.button>New Rule</.button>
        </.link>
      </:actions>
    </.header>

    <.table id="alarm-rules" rows={@alarm_rules}>
      <:col :let={rule} label="Name">{rule.name}</:col>
      <:col :let={rule} label="Event Type">
        <%= case rule.event_type do %>
          <% "telemetry_limit" -> %>
            <span class="text-info">Telemetry Limit</span>
          <% other -> %>
            {other}
        <% end %>
      </:col>
      <:col :let={rule} label="Conditions">
        <div class="flex flex-wrap gap-1">
          <%= if rule.conditions["limit_state"] do %>
            <%= for state <- rule.conditions["limit_state"] do %>
              <span class={[
                "badge badge-sm",
                state == "red" && "badge-error",
                state == "yellow" && "badge-warning",
                state == "blue" && "badge-info"
              ]}>
                {state}
              </span>
            <% end %>
          <% end %>
          <%= if rule.conditions["item_name_pattern"] do %>
            <span class="badge badge-sm badge-neutral font-mono">
              {rule.conditions["item_name_pattern"]}
            </span>
          <% end %>
          <%= if rule.conditions == %{} do %>
            <span class="text-base-content/40 italic text-xs">All events</span>
          <% end %>
        </div>
      </:col>
      <:col :let={rule} label="Severity">
        <.status_badge status={to_string(rule.severity)} />
      </:col>
      <:col :let={rule} label="Status">
        <.status_badge status={rule.enabled} true_label="Enabled" false_label="Disabled" />
      </:col>
      <:action :let={rule}>
        <.link phx-click={JS.push("toggle", value: %{id: rule.id})}>
          {if rule.enabled, do: "Disable", else: "Enable"}
        </.link>
        <.link patch={~p"/missions/#{@mission}/alarms/#{rule}/edit"}>Edit</.link>
        <.link
          phx-click={JS.push("delete", value: %{id: rule.id})}
          data-confirm="Are you sure you want to delete this alarm rule?"
        >
          Delete
        </.link>
      </:action>
    </.table>

    <%= if Enum.empty?(@alarm_rules) do %>
      <div class="text-center py-12 border border-dashed border-base-300 rounded-sm mt-4 bg-base-200/30">
        <.icon name="hero-bell-alert" class="mx-auto h-12 w-12 text-base-content/30" />
        <h3 class="mt-2 text-sm font-semibold text-base-content">No alarm rules</h3>
        <p class="mt-1 text-sm text-base-content/60">
          Create rules to generate alarms when telemetry exceeds limits.
        </p>
        <div class="mt-6">
          <.link patch={~p"/missions/#{@mission}/alarms/new"}>
            <.button>
              <.icon name="hero-plus" class="-ml-0.5 mr-1.5 h-5 w-5" /> New Rule
            </.button>
          </.link>
        </div>
      </div>
    <% end %>

    <!-- Alarm Rule Modal -->
    <.modal
      :if={@live_action in [:new, :edit]}
      id="alarm-rule-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/alarms")}
    >
      <.live_component
        module={CadenceWeb.AlarmRuleLive.FormComponent}
        id={@alarm_rule.id || :new}
        title={@page_title}
        action={if @live_action == :new, do: :new, else: :edit}
        alarm_rule={@alarm_rule}
        mission={@mission}
        targets={@targets}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/alarms"}
      />
    </.modal>

    <!-- Coverage Analysis Modal -->
    <.modal
      :if={@show_coverage_modal}
      id="coverage-modal"
      show
      on_cancel={JS.push("close_coverage_modal")}
    >
      <.live_component
        module={CadenceWeb.AlarmRuleLive.CoverageReportComponent}
        id="coverage-analysis"
        mission={@mission}
        definition_set_id={@definition_set_id}
      />
    </.modal>

    <!-- Bulk Create Modal -->
    <.modal
      :if={@show_bulk_create_modal}
      id="bulk-create-modal"
      show
      on_cancel={JS.push("close_bulk_create_modal")}
    >
      <.live_component
        module={CadenceWeb.AlarmRuleLive.BulkCreateComponent}
        id="bulk-create"
        mission={@mission}
        definition_set_id={@bulk_create_definition_set_id}
        target_id={@bulk_create_target_id}
        parameters={@bulk_create_parameters}
      />
    </.modal>
    """
  end
end
