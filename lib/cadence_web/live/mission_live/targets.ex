defmodule CadenceWeb.MissionLive.Targets do
  @moduledoc """
  LiveView for managing targets within a mission.
  """
  use CadenceWeb, :live_view

  alias Cadence.{Interfaces, Targets}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Mission is already loaded by the on_mount hook
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
    targets = Targets.list_targets(mission)
    interfaces = Interfaces.list_interfaces(mission)

    socket
    |> assign(:page_title, "Targets")
    |> assign(:targets, targets)
    |> assign(:interfaces, interfaces)
    |> assign(:target, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    targets = Targets.list_targets(mission)
    interfaces = Interfaces.list_interfaces(mission)

    socket
    |> assign(:page_title, "New Target")
    |> assign(:targets, targets)
    |> assign(:interfaces, interfaces)
    |> assign(:target, %Targets.Target{})
  end

  defp apply_action(socket, :edit, %{"target_id" => target_id}) do
    mission = socket.assigns.mission
    target = Targets.get_target!(target_id)
    targets = Targets.list_targets(mission)
    interfaces = Interfaces.list_interfaces(mission)

    if target.mission_id == mission.id do
      socket
      |> assign(:page_title, "Edit Target")
      |> assign(:targets, targets)
      |> assign(:interfaces, interfaces)
      |> assign(:target, target)
    else
      socket
      |> put_flash(:error, "Target not found in this mission")
      |> push_patch(to: ~p"/missions/#{mission}/targets")
    end
  end

  @impl true
  def handle_info({CadenceWeb.TargetLive.FormComponent, {:saved, _target}}, socket) do
    targets = Targets.list_targets(socket.assigns.mission)
    {:noreply, assign(socket, :targets, targets)}
  end

  @impl true
  def handle_event("delete", %{"id" => target_id}, socket) do
    target = Targets.get_target!(target_id)
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    if target.mission_id == mission.id do
      case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
        :ok ->
          case Targets.delete_target(target) do
            {:ok, _} ->
              targets = Targets.list_targets(mission)

              {:noreply,
               socket
               |> put_flash(:info, "Target deleted successfully")
               |> assign(:targets, targets)}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Failed to delete target")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "You don't have permission to delete targets")}
      end
    else
      {:noreply, put_flash(socket, :error, "Target not found in this mission")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Targets
      <:subtitle>Manage spacecraft and ground station targets for this mission</:subtitle>
      <:actions>
        <.link patch={~p"/missions/#{@mission}/targets/new"}>
          <.button>New Target</.button>
        </.link>
      </:actions>
    </.header>

    <.table id="targets" rows={@targets}>
      <:col :let={target} label="Name">{target.name}</:col>
      <:col :let={target} label="Identifier">{target.identifier}</:col>
      <:col :let={target} label="Type">{target.type}</:col>
      <:col :let={target} label="Database">
        <%= if target.definition_set do %>
          <span class="text-sm">
            {target.definition_set.database.name}
            <span class="text-zinc-400 text-xs ml-1">v{target.definition_set.version}</span>
          </span>
        <% else %>
          <span class="text-zinc-500 text-sm italic">Not assigned</span>
        <% end %>
      </:col>
      <:col :let={target} label="Status">
        <span class={[
          "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset",
          target.status == "online" && "bg-green-50 text-green-700 ring-green-600/20",
          target.status == "offline" && "bg-gray-50 text-gray-600 ring-gray-500/10",
          target.status == "standby" && "bg-yellow-50 text-yellow-700 ring-yellow-600/20",
          target.status == "fault" && "bg-red-50 text-red-700 ring-red-600/10"
        ]}>
          {target.status}
        </span>
      </:col>
      <:col :let={target} label="Circuit Breaker">
        <span class={[
          "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset",
          target.circuit_breaker_status == "closed" && "bg-green-50 text-green-700 ring-green-600/20",
          target.circuit_breaker_status == "open" && "bg-red-50 text-red-700 ring-red-600/10",
          target.circuit_breaker_status == "half_open" &&
            "bg-yellow-50 text-yellow-700 ring-yellow-600/20"
        ]}>
          {target.circuit_breaker_status}
        </span>
      </:col>
      <:action :let={target}>
        <.link patch={~p"/missions/#{@mission}/targets/#{target}/edit"}>Edit</.link>
        <.link
          phx-click={JS.push("delete", value: %{id: target.id})}
          data-confirm="Are you sure you want to delete this target?"
        >
          Delete
        </.link>
      </:action>
    </.table>

    <%= if Enum.empty?(@targets) do %>
      <div class="text-center py-12">
        <.icon name="hero-cpu-chip" class="mx-auto h-12 w-12 text-gray-400" />
        <h3 class="mt-2 text-sm font-semibold text-gray-900">No targets</h3>
        <p class="mt-1 text-sm text-gray-500">Get started by creating a new target.</p>
        <div class="mt-6">
          <.link patch={~p"/missions/#{@mission}/targets/new"}>
            <.button>
              <.icon name="hero-plus" class="-ml-0.5 mr-1.5 h-5 w-5" /> New Target
            </.button>
          </.link>
        </div>
      </div>
    <% end %>

    <.modal
      :if={@live_action in [:new, :edit]}
      id="target-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/targets")}
    >
      <.live_component
        module={CadenceWeb.TargetLive.FormComponent}
        id={@target.id || :new}
        title={@page_title}
        action={if @live_action == :new, do: :new, else: :edit}
        target={@target}
        mission={@mission}
        interfaces={@interfaces}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/targets"}
      />
    </.modal>
    """
  end
end
