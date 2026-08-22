defmodule CadenceWeb.OpsDashboardNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.Document
  alias CadenceWeb.CommsComponents

  @impl true
  def mount(params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    mode = creation_mode(params)

    {mode, form_params, source_dashboard} =
      creation_state(mode, params, scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, page_title(mode))
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:creation_mode, mode)
     |> assign(:source_dashboard, source_dashboard)
     |> assign(:return_to, ~p"/missions/#{mission.mission_id}/ops/dashboards")
     |> assign(:form, to_form(form_params, as: :dashboard))}
  end

  @impl true
  def handle_event("validate", %{"dashboard" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :dashboard))}
  end

  @impl true
  def handle_event("save", %{"dashboard" => params}, socket) do
    case CommsComponents.normalize_text(params["name"]) do
      nil ->
        {:noreply, put_flash(socket, :error, "Name is required.")}

      name ->
        persist_creation(socket, params, name)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-dashboard-new-page" class="h-full overflow-y-auto bg-base-100">
        <div class="mx-auto max-w-3xl px-6 py-12 lg:py-16">
          <div class="border-l-2 border-primary pl-4">
            <p class="font-mono text-[0.65rem] uppercase tracking-[0.2em] text-primary/70">
              Dashboard authoring / {mode_label(@creation_mode)}
            </p>
            <h1 class="mt-1 text-2xl font-bold tracking-tight">{@page_title}</h1>
            <p class="mt-2 max-w-2xl text-sm text-base-content/65">
              {mode_description(@creation_mode)}
            </p>
          </div>

          <div
            :if={@source_dashboard}
            id="dashboard-clone-source"
            class="mt-6 border border-primary/20 bg-primary/5 p-3"
            data-source-dashboard-id={@source_dashboard.dashboard_id}
          >
            <p class="hud-label">Source dashboard</p>
            <p class="mt-1 text-sm font-semibold">{@source_dashboard.name}</p>
            <p class="mt-1 font-mono text-[0.65rem] text-base-content/45">
              {@source_dashboard.widget_count} widgets · v{@source_dashboard.latest_version}
            </p>
          </div>

          <.form
            for={@form}
            id="dashboard-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-7 space-y-6 border border-base-300 bg-base-200/20 p-5"
          >
            <.input field={@form[:name]} type="text" label="Name" required />
            <.input
              field={@form[:description]}
              type="text"
              label="Description (what operators use this screen for)"
            />
            <.input
              :if={@creation_mode == :import}
              field={@form[:document_json]}
              type="textarea"
              label="Dashboard document JSON"
              required
              class="textarea textarea-bordered min-h-80 w-full font-mono text-xs"
            />

            <p :if={@creation_mode == :import} class="text-xs text-base-content/55">
              Cadence validates and migrates the document before creating a new mission-scoped
              dashboard identity. Runtime bindings and widget semantics are preserved.
            </p>

            <.form_actions submit={submit_label(@creation_mode)} cancel_navigate={@return_to} />
          </.form>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp persist_creation(socket, params, name) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    description = CommsComponents.normalize_text(params["description"])

    result =
      case socket.assigns.creation_mode do
        :clone ->
          Cadence.Dashboards.clone_document(
            scope.organization_id,
            mission.mission_id,
            socket.assigns.source_dashboard.dashboard_id,
            name: name,
            description: description,
            actor_id: current_user_id(scope)
          )

        :import ->
          Cadence.Dashboards.import_document(
            scope.organization_id,
            mission.mission_id,
            Map.get(params, "document_json", ""),
            name: name,
            description: description,
            actor_id: current_user_id(scope)
          )

        :new ->
          document =
            Document.from_map(%{
              "schema_version" => 1,
              "dashboard_id" => Cadence.Ids.new("ops_dashboard"),
              "organization_id" => scope.organization_id,
              mission_id: mission.mission_id,
              name: name,
              description: description,
              placements: [],
              metadata: %{
                "source" => "ops_dashboard_new_live",
                "created_by" => current_user_id(scope)
              }
            })

          Cadence.Dashboards.persist_document(scope.organization_id, document)
      end

    case result do
      {:ok, persisted} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/missions/#{mission.mission_id}/ops/dashboards/#{persisted.dashboard_id}/edit"
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  defp creation_mode(%{"mode" => "import"}), do: :import

  defp creation_mode(%{"source_dashboard_id" => source_dashboard_id})
       when is_binary(source_dashboard_id) and source_dashboard_id != "",
       do: :clone

  defp creation_mode(_params), do: :new

  defp creation_state(:clone, params, organization_id, mission_id) do
    source_dashboard_id = params["source_dashboard_id"]

    source =
      Cadence.Dashboards.list_dashboard_summaries(organization_id, mission_id)
      |> Enum.find(&(&1.dashboard_id == source_dashboard_id))

    case source do
      nil ->
        {:new, default_form_params(), nil}

      source ->
        {:clone,
         %{
           "name" => "Copy of #{source.name}",
           "description" => source.description || ""
         }, source}
    end
  end

  defp creation_state(:import, _params, _organization_id, _mission_id) do
    {:import, Map.put(default_form_params(), "document_json", ""), nil}
  end

  defp creation_state(:new, _params, _organization_id, _mission_id) do
    {:new, default_form_params(), nil}
  end

  defp default_form_params, do: %{"name" => "", "description" => ""}

  defp page_title(:clone), do: "Clone Dashboard"
  defp page_title(:import), do: "Import Dashboard"
  defp page_title(:new), do: "New Dashboard"

  defp mode_label(:clone), do: "Clone"
  defp mode_label(:import), do: "Import"
  defp mode_label(:new), do: "Create"

  defp mode_description(:clone),
    do: "Create an independent draft from an existing mission dashboard."

  defp mode_description(:import),
    do: "Validate a versioned Cadence dashboard document before creating a new draft."

  defp mode_description(:new),
    do: "Create a mission-shared telemetry workspace, then compose it in the staged Editor."

  defp submit_label(:clone), do: "Clone into Editor"
  defp submit_label(:import), do: "Validate & Import"
  defp submit_label(:new), do: "Create in Editor"

  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil

  defp format_error(%Ecto.Changeset{} = changeset), do: CommsComponents.format_error(changeset)
  defp format_error({:invalid_dashboard_json, _error}), do: "Dashboard JSON is not valid."

  defp format_error(:dashboard_document_must_be_an_object),
    do: "Dashboard JSON must contain one document object."

  defp format_error(reason), do: "Failed to create dashboard: #{inspect(reason)}"
end
