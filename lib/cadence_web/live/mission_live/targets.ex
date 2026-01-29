defmodule CadenceWeb.MissionLive.Targets do
  @moduledoc """
  LiveView for managing targets within a mission.
  """
  use CadenceWeb, :live_view

  alias Cadence.Targets

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

    # Subscribe to real-time target status updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "targets:#{mission.id}")
    end

    targets = Targets.list_targets_with_preloads(mission)

    socket
    |> assign(:page_title, "Targets")
    |> assign(:targets, targets)
    |> assign(:target, nil)
  end

  defp apply_action(socket, :new, _params) do
    mission = socket.assigns.mission
    targets = Targets.list_targets_with_preloads(mission)

    socket
    |> assign(:page_title, "New Target")
    |> assign(:targets, targets)
    |> assign(:target, %Targets.Target{})
  end

  @impl true
  def handle_info({CadenceWeb.TargetLive.FormComponent, {:saved, _target}}, socket) do
    targets = Targets.list_targets_with_preloads(socket.assigns.mission)
    {:noreply, assign(socket, :targets, targets)}
  end

  # Real-time target status updates via PubSub
  def handle_info({:target_changed, _event_type, updated_target}, socket) do
    # Update the target in the list with the new data
    targets =
      Enum.map(socket.assigns.targets, fn target ->
        if target.id == updated_target.id do
          # Merge status fields from the domain entity into the schema
          %{
            target
            | status: updated_target.status,
              circuit_breaker_status: updated_target.circuit_breaker_status
          }
        else
          target
        end
      end)

    {:noreply, assign(socket, :targets, targets)}
  end

  # Catch-all for other PubSub events we don't handle
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete", %{"id" => target_id}, socket) do
    with {:ok, target} <- fetch_target(socket, target_id),
         :ok <- authorize_manage_targets(socket),
         {:ok, _} <- Targets.delete_target(target) do
      targets = list_targets(socket)

      {:noreply,
       socket
       |> put_flash(:info, "Target deleted successfully")
       |> assign(:targets, targets)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Target not found in this mission")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete targets")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete target")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
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
        <:col :let={target} label="SCID">
          <%= if target.scid do %>
            <span class="font-mono text-sm">{target.scid}</span>
          <% else %>
            <span class="text-base-content/40 text-sm">-</span>
          <% end %>
        </:col>
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
          <.link navigate={~p"/missions/#{@mission}/targets/#{target}"}>View</.link>
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
    </div>

    <.modal
      :if={@live_action == :new}
      id="target-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/targets")}
    >
      <.live_component
        module={CadenceWeb.TargetLive.FormComponent}
        id={:new}
        title={@page_title}
        action={:new}
        target={@target}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/targets"}
      />
    </.modal>
    """
  end

  defp fetch_target(socket, target_id) do
    mission = socket.assigns.mission

    case Targets.get_target(target_id, mission.id) do
      {:ok, target} -> {:ok, target}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp authorize_manage_targets(socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok -> :ok
      {:error, _} -> {:error, :unauthorized}
    end
  end

  defp list_targets(socket) do
    Targets.list_targets_with_preloads(socket.assigns.mission)
  end
end
