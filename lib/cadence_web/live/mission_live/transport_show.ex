defmodule CadenceWeb.MissionLive.TransportShow do
  @moduledoc """
  LiveView for displaying a single transport interface.
  """
  use CadenceWeb, :live_view

  alias Cadence.{Links, Transports}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"transport_id" => transport_id}, _uri, socket) do
    mission = socket.assigns.mission
    org_id = socket.assigns.current_scope.current_organization.id

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        case Transports.get_interface(org_id, mission.id, transport_id) do
          {:ok, interface} ->
            bindings = Links.list_bindings_for_transport(org_id, mission.id, interface.id)

            {:noreply,
             socket
             |> assign(:page_title, interface.name)
             |> assign(:interface, interface)
             |> assign(:bindings, bindings)}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, "Transport not found")
             |> push_navigate(to: ~p"/missions/#{mission}/transports")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-4">
      <.header>
        <div class="flex items-center gap-3">
          <.transport_type_badge type={@interface.type} />
          {@interface.name}
        </div>
        <:subtitle>
          <.enabled_indicator enabled={@interface.enabled} />
        </:subtitle>
        <:actions>
          <.link navigate={~p"/missions/#{@mission}/transports/#{@interface}/edit"}>
            <.button>Edit</.button>
          </.link>
          <.link navigate={~p"/missions/#{@mission}/transports"}>
            <.button variant="ghost">Back to Transports</.button>
          </.link>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
        <!-- Endpoint Configuration -->
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title text-sm">
              <.icon name="hero-server" class="h-4 w-4" /> Endpoint Configuration
            </h3>

            <%= if @interface.endpoint && @interface.endpoint != %{} do %>
              <dl class="grid grid-cols-2 gap-2 text-sm">
                <%= for {key, value} <- @interface.endpoint do %>
                  <dt class="text-base-content/60">{humanize_key(key)}</dt>
                  <dd class="font-mono">{value}</dd>
                <% end %>
              </dl>
            <% else %>
              <p class="text-sm text-base-content/50 italic">No endpoint configuration</p>
            <% end %>
          </div>
        </div>
        
    <!-- Transport Info -->
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title text-sm">
              <.icon name="hero-information-circle" class="h-4 w-4" /> Details
            </h3>

            <dl class="grid grid-cols-2 gap-2 text-sm">
              <dt class="text-base-content/60">Allowed Directions</dt>
              <dd>
                <div class="flex flex-wrap gap-1">
                  <%= for dir <- @interface.allowed_directions || [:both] do %>
                    <.direction_badge direction={dir} />
                  <% end %>
                </div>
              </dd>

              <dt class="text-base-content/60">Tags</dt>
              <dd>
                <%= if @interface.tags && @interface.tags != [] do %>
                  <div class="flex flex-wrap gap-1">
                    <%= for tag <- @interface.tags do %>
                      <span class="badge badge-sm badge-ghost">{tag}</span>
                    <% end %>
                  </div>
                <% else %>
                  <span class="text-base-content/40">-</span>
                <% end %>
              </dd>
            </dl>
          </div>
        </div>
      </div>
      
    <!-- Channel Bindings -->
      <div class="mt-6">
        <h3 class="text-lg font-semibold mb-4">Channel Bindings</h3>

        <%= if @bindings == [] do %>
          <div class="card bg-base-200">
            <div class="card-body text-center py-8">
              <.icon name="hero-link-slash" class="h-8 w-8 mx-auto text-base-content/40 mb-2" />
              <p class="text-sm text-base-content/50">
                No channels are bound to this transport.
              </p>
              <p class="text-xs text-base-content/40 mt-1">
                Configure bindings from the Links section.
              </p>
            </div>
          </div>
        <% else %>
          <div class="overflow-x-auto bg-base-200 rounded-lg">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/60">
                  <th>Channel</th>
                  <th>Link</th>
                  <th>Direction</th>
                  <th>Role</th>
                  <th>Priority</th>
                  <th>State</th>
                </tr>
              </thead>
              <tbody>
                <%= for binding <- @bindings do %>
                  <tr class="hover:bg-base-300/50">
                    <td>
                      <.channel_id channel={binding.channel} />
                    </td>
                    <td class="text-sm">
                      SCID {binding.channel.scid}
                    </td>
                    <td>
                      <.direction_badge direction={binding.direction} />
                    </td>
                    <td>
                      <.role_badge role={binding.role} />
                    </td>
                    <td class="font-mono text-sm">
                      {binding.priority}
                    </td>
                    <td>
                      <.state_badge state={binding.desired_state} />
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp humanize_key(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_key(key) when is_atom(key), do: humanize_key(Atom.to_string(key))
end
