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
    targets = Targets.list_targets_with_preloads(mission)
    interfaces = Interfaces.list_interfaces(mission)

    socket
    |> assign(:page_title, "Targets")
    |> assign(:targets, targets)
    |> assign(:interfaces, interfaces)
    |> assign(:target, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    targets = Targets.list_targets_with_preloads(mission)
    interfaces = Interfaces.list_interfaces(mission)

    socket
    |> assign(:page_title, "New Target")
    |> assign(:targets, targets)
    |> assign(:interfaces, interfaces)
    |> assign(:target, %Targets.Target{})
  end

  defp apply_action(socket, :edit, %{"target_id" => target_id}) do
    mission = socket.assigns.mission

    # Use schema version for form compatibility
    case Targets.get_target_schema_unscoped(target_id) do
      nil ->
        socket
        |> put_flash(:error, "Target not found in this mission")
        |> push_patch(to: ~p"/missions/#{mission}/targets")

      target ->
        targets = Targets.list_targets_with_preloads(mission)
        interfaces = Interfaces.list_interfaces(mission)

        socket
        |> assign(:page_title, "Edit Target")
        |> assign(:targets, targets)
        |> assign(:interfaces, interfaces)
        |> assign(:target, target)
    end
  end

  @impl true
  def handle_info({CadenceWeb.TargetLive.FormComponent, {:saved, _target}}, socket) do
    targets = Targets.list_targets_with_preloads(socket.assigns.mission)
    {:noreply, assign(socket, :targets, targets)}
  end

  @impl true
  def handle_event("delete", %{"id" => target_id}, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Targets.get_target(target_id, mission.id) do
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Target not found in this mission")}

      {:ok, target} ->
        case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
          :ok ->
            case Targets.delete_target(target) do
              {:ok, _} ->
                targets = Targets.list_targets_with_preloads(mission)

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
            <span class="text-base-content/40 text-xs ml-1">v{target.definition_set.version}</span>
          </span>
        <% else %>
          <span class="text-base-content/50 text-sm italic">Not assigned</span>
        <% end %>
      </:col>
      <:col :let={target} label="Status">
        <.status_badge status={target.status} />
      </:col>
      <:col :let={target} label="Circuit Breaker">
        <.status_badge status={target.circuit_breaker_status} />
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
      <div class="text-center py-12 border border-dashed border-base-300 rounded-sm mt-4 bg-base-200/30">
        <.icon name="hero-cpu-chip" class="mx-auto h-12 w-12 text-base-content/30" />
        <h3 class="mt-2 text-sm font-semibold text-base-content">No targets</h3>
        <p class="mt-1 text-sm text-base-content/60">Get started by creating a new target.</p>
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
