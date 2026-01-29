defmodule CadenceWeb.MissionLive.ChannelShow do
  @moduledoc """
  LiveView for displaying and managing a single channel with its bindings.
  """
  use CadenceWeb, :live_view

  alias Cadence.{Links, Transports}
  alias Cadence.Links.Binding

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

  defp apply_action(socket, :show, params) do
    load_channel(socket, params)
    |> assign(:binding, nil)
  end

  defp apply_action(socket, :edit, params) do
    load_channel(socket, params)
    |> assign(:binding, nil)
  end

  defp apply_action(socket, :new_binding, params) do
    socket = load_channel(socket, params)
    channel = socket.assigns.channel

    socket
    |> assign(:binding, %Binding{channel_id: channel.id})
  end

  defp apply_action(socket, :edit_binding, params) do
    socket = load_channel(socket, params)
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id
    binding_id = params["binding_id"]

    case Links.get_binding(org_id, mission.id, binding_id) do
      {:ok, binding} ->
        assign(socket, :binding, binding)

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Binding not found")
        |> push_patch(to: channel_path(socket))
    end
  end

  defp load_channel(socket, %{"link_id" => link_id, "channel_id" => channel_id}) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    with {:ok, link} <- Links.get_link(org_id, mission.id, link_id),
         {:ok, channel} <- Links.get_channel(org_id, mission.id, channel_id) do
      bindings = Links.list_bindings_for_channel(org_id, mission.id, channel.id)
      interfaces = Transports.list_interfaces(org_id, mission.id)

      socket
      |> assign(:page_title, "Channel: SCID #{channel.scid} / VCID #{channel.vcid}")
      |> assign(:link, link)
      |> assign(:channel, channel)
      |> assign(:bindings, bindings)
      |> assign(:interfaces, interfaces)
    else
      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Channel or link not found")
        |> push_navigate(to: ~p"/missions/#{mission}/links")
    end
  end

  @impl true
  def handle_info({CadenceWeb.ChannelLive.FormComponent, {:saved, channel}}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    bindings = Links.list_bindings_for_channel(org_id, mission.id, channel.id)

    {:noreply,
     socket
     |> assign(:channel, channel)
     |> assign(:bindings, bindings)}
  end

  def handle_info({CadenceWeb.BindingLive.FormComponent, {:saved, _binding}}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id
    channel = socket.assigns.channel

    bindings = Links.list_bindings_for_channel(org_id, mission.id, channel.id)
    {:noreply, assign(socket, :bindings, bindings)}
  end

  @impl true
  def handle_event("delete_binding", %{"id" => binding_id}, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    with :ok <- authorize_manage(socket),
         {:ok, binding} <- Links.get_binding(org_id, mission.id, binding_id),
         {:ok, _} <- Links.delete_binding(org_id, mission.id, binding) do
      bindings = Links.list_bindings_for_channel(org_id, mission.id, socket.assigns.channel.id)

      {:noreply,
       socket
       |> put_flash(:info, "Binding deleted successfully")
       |> assign(:bindings, bindings)}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Binding not found")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to delete bindings")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete binding")}
    end
  end

  defp authorize_manage(socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
      :ok -> :ok
      {:error, _} -> {:error, :unauthorized}
    end
  end

  defp channel_path(socket) do
    ~p"/missions/#{socket.assigns.mission}/links/#{socket.assigns.link}/channels/#{socket.assigns.channel}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
      <.header>
        <div class="flex items-center gap-3">
          <.channel_id channel={@channel} />
          <.direction_badge direction={@channel.direction} />
          <.enabled_indicator enabled={@channel.enabled} />
        </div>
        <:subtitle>
          <span class="text-base-content/60">
            Link: SCID {@link.scid}
            <%= if @link.name do %>
              ({@link.name})
            <% end %>
          </span>
        </:subtitle>
        <:actions>
          <.link patch={~p"/missions/#{@mission}/links/#{@link}/channels/#{@channel}/edit"}>
            <.button>Edit Channel</.button>
          </.link>
          <.link navigate={~p"/missions/#{@mission}/links/#{@link}"}>
            <.button variant="ghost">Back to Link</.button>
          </.link>
        </:actions>
      </.header>
      
    <!-- Bindings Section -->
      <div class="mt-8">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold">Transport Bindings</h3>
          <.link patch={~p"/missions/#{@mission}/links/#{@link}/channels/#{@channel}/bindings/new"}>
            <.button>
              <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add Binding
            </.button>
          </.link>
        </div>

        <%= if @bindings == [] do %>
          <div class="card bg-base-200">
            <div class="card-body text-center py-8">
              <.icon name="hero-link-slash" class="h-8 w-8 mx-auto text-base-content/40 mb-2" />
              <p class="text-sm text-base-content/50">
                No transport bindings configured for this channel.
              </p>
              <p class="text-xs text-base-content/40 mt-1">
                Bindings connect this channel to transport interfaces for data flow.
              </p>
            </div>
          </div>
        <% else %>
          <div class="overflow-x-auto bg-base-200 rounded-lg">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Interface</th>
                  <th>Direction</th>
                  <th>Role</th>
                  <th>Priority</th>
                  <th>Desired State</th>
                  <th class="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                <%= for binding <- @bindings do %>
                  <tr class="hover:bg-base-300/50">
                    <td>
                      <.link
                        navigate={~p"/missions/#{@mission}/transports/#{binding.transport_id}"}
                        class="link link-primary"
                      >
                        {binding.interface.name}
                      </.link>
                      <div class="text-xs text-base-content/50">
                        <.transport_type_badge type={binding.interface.type} />
                      </div>
                    </td>
                    <td>
                      <.direction_badge direction={binding.direction} />
                    </td>
                    <td>
                      <.role_badge role={binding.role} />
                    </td>
                    <td class="font-mono">{binding.priority}</td>
                    <td>
                      <.state_badge state={binding.desired_state} />
                    </td>
                    <td class="text-right">
                      <.link
                        patch={
                          ~p"/missions/#{@mission}/links/#{@link}/channels/#{@channel}/bindings/#{binding}/edit"
                        }
                        class="link link-primary text-sm"
                      >
                        Edit
                      </.link>
                      <button
                        type="button"
                        phx-click="delete_binding"
                        phx-value-id={binding.id}
                        data-confirm="Are you sure you want to delete this binding?"
                        class="link link-error text-sm ml-2"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
      
    <!-- Quick Reference -->
      <div class="mt-8 card bg-base-200">
        <div class="card-body">
          <h4 class="card-title text-sm">Quick Reference</h4>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
            <div>
              <span class="text-base-content/60">Roles:</span>
              <ul class="list-disc list-inside mt-1 text-xs">
                <li><strong>Primary</strong> - Main data path</li>
                <li><strong>Backup</strong> - Failover path</li>
                <li><strong>Replay</strong> - Historical data</li>
                <li><strong>Any</strong> - No specific role</li>
              </ul>
            </div>
            <div>
              <span class="text-base-content/60">States:</span>
              <ul class="list-disc list-inside mt-1 text-xs">
                <li><strong>Active</strong> - Binding is live</li>
                <li><strong>Inactive</strong> - Binding is paused</li>
                <li><strong>Draining</strong> - Finishing pending data</li>
              </ul>
            </div>
            <div>
              <span class="text-base-content/60">Priority:</span>
              <p class="text-xs mt-1">
                Lower values = higher priority. Used for selection when multiple bindings are active.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Edit Channel Modal -->
    <.modal
      :if={@live_action == :edit}
      id="edit-channel-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/links/#{@link}/channels/#{@channel}")}
    >
      <.live_component
        module={CadenceWeb.ChannelLive.FormComponent}
        id={@channel.id}
        title="Edit Channel"
        action={:edit}
        channel={@channel}
        link={@link}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/links/#{@link}/channels/#{@channel}"}
      />
    </.modal>

    <!-- New Binding Modal -->
    <.modal
      :if={@live_action == :new_binding}
      id="new-binding-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/links/#{@link}/channels/#{@channel}")}
    >
      <.live_component
        module={CadenceWeb.BindingLive.FormComponent}
        id={:new}
        title="New Binding"
        action={:new}
        binding={@binding}
        channel={@channel}
        link={@link}
        interfaces={@interfaces}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/links/#{@link}/channels/#{@channel}"}
      />
    </.modal>

    <!-- Edit Binding Modal -->
    <.modal
      :if={@live_action == :edit_binding}
      id="edit-binding-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/links/#{@link}/channels/#{@channel}")}
    >
      <.live_component
        module={CadenceWeb.BindingLive.FormComponent}
        id={@binding.id}
        title="Edit Binding"
        action={:edit}
        binding={@binding}
        channel={@channel}
        link={@link}
        interfaces={@interfaces}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/links/#{@link}/channels/#{@channel}"}
      />
    </.modal>
    """
  end
end
