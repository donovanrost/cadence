defmodule CadenceWeb.MissionLive.Automations do
  @moduledoc """
  LiveView for managing automations within a mission.
  """
  use CadenceWeb, :live_view

  alias Cadence.{Automations, Procedures}
  alias Cadence.Automations.Automation

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
    automations = Automations.list_automations(mission.organization_id, mission_id: mission.id)
    procedures = Procedures.list_procedures(mission.organization_id, mission_id: mission.id)

    socket
    |> assign(:page_title, "Automations")
    |> assign(:automations, automations)
    |> assign(:procedures, procedures)
    |> assign(:automation, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    automations = Automations.list_automations(mission.organization_id, mission_id: mission.id)
    procedures = Procedures.list_procedures(mission.organization_id, mission_id: mission.id)

    socket
    |> assign(:page_title, "New Automation")
    |> assign(:automations, automations)
    |> assign(:procedures, procedures)
    |> assign(:automation, %Automation{
      enabled: true,
      trigger_type: "alarm_fired",
      action_type: "execute_procedure"
    })
  end

  defp apply_action(socket, :edit, %{"automation_id" => automation_id}) do
    mission = socket.assigns.mission
    automation = Automations.get_automation!(automation_id)
    automations = Automations.list_automations(mission.organization_id, mission_id: mission.id)
    procedures = Procedures.list_procedures(mission.organization_id, mission_id: mission.id)

    if automation.mission_id == mission.id do
      socket
      |> assign(:page_title, "Edit Automation")
      |> assign(:automations, automations)
      |> assign(:procedures, procedures)
      |> assign(:automation, automation)
    else
      socket
      |> put_flash(:error, "Automation not found in this mission")
      |> push_patch(to: ~p"/missions/#{mission}/automations")
    end
  end

  @impl true
  def handle_info({CadenceWeb.AutomationLive.FormComponent, {:saved, _automation}}, socket) do
    automations =
      Automations.list_automations(socket.assigns.mission.organization_id,
        mission_id: socket.assigns.mission.id
      )

    {:noreply, assign(socket, :automations, automations)}
  end

  @impl true
  def handle_event("toggle", %{"id" => automation_id}, socket) do
    automation = Automations.get_automation!(automation_id)
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    if automation.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          result =
            if automation.enabled do
              Automations.disable_automation(automation)
            else
              Automations.enable_automation(automation)
            end

          case result do
            {:ok, _} ->
              automations =
                Automations.list_automations(mission.organization_id, mission_id: mission.id)

              action = if automation.enabled, do: "disabled", else: "enabled"

              {:noreply,
               socket
               |> put_flash(:info, "Automation #{action}")
               |> assign(:automations, automations)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to update automation")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to manage automations")}
      end
    else
      {:noreply, put_flash(socket, :error, "Automation not found in this mission")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => automation_id}, socket) do
    automation = Automations.get_automation!(automation_id)
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    if automation.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          case Automations.delete_automation(automation) do
            {:ok, _} ->
              automations =
                Automations.list_automations(mission.organization_id, mission_id: mission.id)

              {:noreply,
               socket
               |> put_flash(:info, "Automation deleted")
               |> assign(:automations, automations)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to delete automation")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to delete automations")}
      end
    else
      {:noreply, put_flash(socket, :error, "Automation not found in this mission")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Automations
      <:subtitle>
        Event-triggered actions that respond to alarms, telemetry, or procedure events
      </:subtitle>
      <:actions>
        <.link patch={~p"/missions/#{@mission}/automations/new"}>
          <.button>New Automation</.button>
        </.link>
      </:actions>
    </.header>

    <.table id="automations" rows={@automations}>
      <:col :let={automation} label="Name">{automation.name}</:col>
      <:col :let={automation} label="Trigger">
        <span class={trigger_badge_class(automation.trigger_type)}>
          {format_trigger_type(automation.trigger_type)}
        </span>
      </:col>
      <:col :let={automation} label="Action">
        <span class="inline-flex items-center rounded-md bg-purple-50 px-2 py-1 text-xs font-medium text-purple-700 ring-1 ring-inset ring-purple-700/10">
          {format_action_type(automation.action_type)}
        </span>
      </:col>
      <:col :let={automation} label="Runs">
        <span class="text-gray-500">{automation.trigger_count}</span>
      </:col>
      <:col :let={automation} label="Status">
        <.status_badge status={automation.enabled} true_label="Enabled" false_label="Disabled" />
      </:col>
      <:action :let={automation}>
        <.link phx-click={JS.push("toggle", value: %{id: automation.id})}>
          {if automation.enabled, do: "Disable", else: "Enable"}
        </.link>
        <.link patch={~p"/missions/#{@mission}/automations/#{automation}/edit"}>Edit</.link>
        <.link
          phx-click={JS.push("delete", value: %{id: automation.id})}
          data-confirm="Are you sure you want to delete this automation?"
        >
          Delete
        </.link>
      </:action>
    </.table>

    <%= if Enum.empty?(@automations) do %>
      <div class="text-center py-12 border border-dashed border-gray-300 rounded-lg mt-4">
        <.icon name="hero-bolt" class="mx-auto h-12 w-12 text-gray-400" />
        <h3 class="mt-2 text-sm font-semibold text-gray-900">No automations</h3>
        <p class="mt-1 text-sm text-gray-500">
          Create automations to trigger procedures when events occur.
        </p>
        <div class="mt-6">
          <.link patch={~p"/missions/#{@mission}/automations/new"}>
            <.button>
              <.icon name="hero-plus" class="-ml-0.5 mr-1.5 h-5 w-5" /> New Automation
            </.button>
          </.link>
        </div>
      </div>
    <% end %>

    <!-- Automation Modal -->
    <.modal
      :if={@live_action in [:new, :edit]}
      id="automation-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/automations")}
    >
      <.live_component
        module={CadenceWeb.AutomationLive.FormComponent}
        id={@automation.id || :new}
        title={@page_title}
        action={if @live_action == :new, do: :new, else: :edit}
        automation={@automation}
        mission={@mission}
        procedures={@procedures}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/automations"}
      />
    </.modal>
    """
  end

  defp format_trigger_type("alarm_fired"), do: "Alarm Fired"
  defp format_trigger_type("alarm_cleared"), do: "Alarm Cleared"
  defp format_trigger_type("alarm_acknowledged"), do: "Alarm Acknowledged"
  defp format_trigger_type("telemetry_limit"), do: "Telemetry Limit"
  defp format_trigger_type("procedure_completed"), do: "Procedure Completed"
  defp format_trigger_type("procedure_failed"), do: "Procedure Failed"
  defp format_trigger_type(other), do: other

  defp format_action_type("execute_procedure"), do: "Execute Procedure"
  defp format_action_type("acknowledge_alarm"), do: "Acknowledge Alarm"
  defp format_action_type("shelve_alarm"), do: "Shelve Alarm"
  defp format_action_type("send_notification"), do: "Send Notification"
  defp format_action_type(other), do: other

  defp trigger_badge_class("alarm_fired"),
    do:
      "inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/20"

  defp trigger_badge_class("alarm_cleared"),
    do:
      "inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20"

  defp trigger_badge_class("alarm_acknowledged"),
    do:
      "inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20"

  defp trigger_badge_class("telemetry_limit"),
    do:
      "inline-flex items-center rounded-md bg-yellow-50 px-2 py-1 text-xs font-medium text-yellow-700 ring-1 ring-inset ring-yellow-600/20"

  defp trigger_badge_class("procedure_completed"),
    do:
      "inline-flex items-center rounded-md bg-emerald-50 px-2 py-1 text-xs font-medium text-emerald-700 ring-1 ring-inset ring-emerald-600/20"

  defp trigger_badge_class("procedure_failed"),
    do:
      "inline-flex items-center rounded-md bg-orange-50 px-2 py-1 text-xs font-medium text-orange-700 ring-1 ring-inset ring-orange-600/20"

  defp trigger_badge_class(_),
    do:
      "inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-700 ring-1 ring-inset ring-gray-600/20"
end
