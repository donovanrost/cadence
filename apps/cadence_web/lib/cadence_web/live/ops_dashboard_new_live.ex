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

    return_to = ~p"/missions/#{mission.mission_id}/ops/dashboards"

    {:ok,
     socket
     |> assign(:page_title, page_title(mode))
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:creation_mode, mode)
     |> assign(:source_dashboard, source_dashboard)
     |> assign(:dashboard_page, dashboard_page_dto(mode, source_dashboard, return_to))
     |> assign(:dashboard_form, dashboard_form_dto(mode, form_params))}
  end

  @impl true
  def handle_event("validate", %{"dashboard" => params}, socket) do
    {:noreply,
     assign(socket, :dashboard_form, dashboard_form_dto(socket.assigns.creation_mode, params))}
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
      <.vue
        id="ops-dashboard-new-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_new"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="contents"
      />
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

  defp dashboard_page_dto(mode, source_dashboard, return_to) do
    %{
      id: "ops-dashboard-new-page",
      mode: Atom.to_string(mode),
      eyebrow: "Dashboard authoring / #{mode_label(mode)}",
      heading: page_title(mode),
      description: mode_description(mode),
      source: source_dashboard_dto(source_dashboard),
      import_guidance: import_guidance(mode),
      cancel: %{id: "dashboard-cancel", label: "Cancel", href: return_to}
    }
  end

  defp dashboard_form_dto(mode, params) do
    %{
      id: "dashboard-form",
      name: %{
        id: "dashboard_name",
        name: "dashboard[name]",
        type: "text",
        label: "Name",
        value: string_param(params, "name"),
        required: true
      },
      description: %{
        id: "dashboard_description",
        name: "dashboard[description]",
        type: "text",
        label: "Description (what operators use this screen for)",
        value: string_param(params, "description"),
        required: false
      },
      document_json: document_json_field(mode, params),
      submit: %{id: "dashboard-submit", label: submit_label(mode)}
    }
  end

  defp document_json_field(:import, params) do
    %{
      id: "dashboard_document_json",
      name: "dashboard[document_json]",
      type: "textarea",
      label: "Dashboard document JSON",
      value: string_param(params, "document_json"),
      required: true
    }
  end

  defp document_json_field(_mode, _params), do: nil

  defp source_dashboard_dto(nil), do: nil

  defp source_dashboard_dto(source_dashboard) do
    %{
      id: "dashboard-clone-source",
      dashboard_id: source_dashboard.dashboard_id,
      name: source_dashboard.name,
      widget_count: source_dashboard.widget_count,
      latest_version: source_dashboard.latest_version
    }
  end

  defp string_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp import_guidance(:import) do
    "Cadence validates and migrates the document before creating a new mission-scoped " <>
      "dashboard identity. Runtime bindings and widget semantics are preserved."
  end

  defp import_guidance(_mode), do: nil

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
