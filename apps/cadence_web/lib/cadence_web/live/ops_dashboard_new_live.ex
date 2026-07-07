defmodule CadenceWeb.OpsDashboardNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.Document
  alias CadenceWeb.CommsComponents

  @impl true
  def mount(_params, _session, socket) do
    %{current_mission: mission} = socket.assigns

    {:ok,
     socket
     |> assign(:page_title, "New Dashboard")
     |> assign(:return_to, ~p"/missions/#{mission.mission_id}/ops/dashboards")
     |> assign(:form, to_form(%{"name" => "", "description" => ""}, as: :dashboard))}
  end

  @impl true
  def handle_event("validate", %{"dashboard" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :dashboard))}
  end

  @impl true
  def handle_event("save", %{"dashboard" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case CommsComponents.normalize_text(params["name"]) do
      nil ->
        {:noreply, put_flash(socket, :error, "Name is required.")}

      name ->
        document =
          Document.from_map(%{
            "schema_version" => 1,
            "dashboard_id" => Cadence.Ids.new("ops_dashboard"),
            "organization_id" => scope.organization_id,
            mission_id: mission.mission_id,
            name: name,
            description: CommsComponents.normalize_text(params["description"]),
            placements: [],
            metadata: %{"source" => "ops_dashboard_new_live"}
          })

        case Cadence.Dashboards.persist_document(scope.organization_id, document) do
          {:ok, persisted} ->
            {:noreply,
             push_navigate(socket,
               to: ~p"/missions/#{mission.mission_id}/ops/dashboards/#{persisted.dashboard_id}"
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, format_error(reason))}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="ops-dashboard-new-page" class="flex flex-1 min-h-0">
      <div class="flex-1 min-w-0 overflow-y-auto">
        <div class="mx-auto max-w-md px-6 pt-24">
        <h1 class="hud-label">New Dashboard</h1>
        <p class="mt-1 text-sm text-base-content/70">
          A mission-shared telemetry screen. After creating it, add widgets bound to dictionary
          points.
        </p>

        <.form
          for={@form}
          id="dashboard-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-6 space-y-6"
        >
          <.input field={@form[:name]} type="text" label="Name" required />
          <.input
            field={@form[:description]}
            type="text"
            label="Description (what operators use this screen for)"
          />

          <.form_actions submit="Create Dashboard" cancel_navigate={@return_to} />
        </.form>
        </div>
      </div>
      <.mission_context_rail fleet_health={@fleet_health} />
    </div>
    """
  end

  defp format_error(%Ecto.Changeset{} = changeset), do: CommsComponents.format_error(changeset)
  defp format_error(reason), do: "Failed to create dashboard: #{inspect(reason)}"
end
