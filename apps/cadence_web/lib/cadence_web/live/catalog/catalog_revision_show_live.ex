defmodule CadenceWeb.CatalogRevisionShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Catalog
  alias Cadence.MissionModels

  @impl true
  def mount(%{"catalog_revision_id" => catalog_revision_id}, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    case Catalog.fetch_revision(organization_id, mission.mission_id, catalog_revision_id) do
      {:ok, revision} ->
        {:ok,
         socket
         |> assign(:page_title, revision.revision_label)
         |> assign(:nav_item, :catalog)
         |> assign_revision_context(organization_id, mission, revision)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Catalog revision not found.")
         |> redirect(to: ~p"/missions/#{mission.mission_id}/catalog")}
    end
  end

  defp assign_revision_context(socket, organization_id, mission, revision) do
    mission_id = mission.mission_id

    database =
      fetch_optional(fn ->
        Catalog.fetch_database(organization_id, mission_id, revision.catalog_database_id)
      end)

    artifact =
      fetch_optional(fn ->
        Catalog.fetch_artifact(organization_id, mission_id, revision.artifact_id)
      end)

    import_run =
      fetch_optional(fn ->
        Catalog.fetch_import_run(organization_id, mission_id, revision.import_run_id)
      end)

    mission_model =
      fetch_optional(fn ->
        MissionModels.fetch_revision(
          organization_id,
          mission_id,
          revision.mission_model_revision_id
        )
      end)

    runtime_plans =
      fetch_optional(fn ->
        MissionModels.fetch_runtime_plans(
          organization_id,
          mission_id,
          revision.mission_model_revision_id
        )
      end)

    runtime_plans = runtime_plans || %{}

    socket
    |> assign(:revision, revision_header_dto(revision))
    |> assign(:navigation, navigation_dto(mission, database, revision))
    |> assign(:provenance, provenance_dto(mission_id, revision, database, artifact, import_run))
    |> assign(:runtime_usage, runtime_usage_dto())
    |> assign(:mission_model, mission_model_dto(mission_model, runtime_plans))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="catalog-revision-show-page">
        <.vue
          id="catalog-revision-show-component"
          v-component="FederatedFullPageSurface"
          application_key="mission_catalog"
          surface_id="catalog_revision_show"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id, catalog_revision_id: @revision.catalog_revision_id}}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp revision_header_dto(revision) do
    %{
      title: revision.revision_label,
      number_label: "Revision #{revision.revision_number}"
    }
  end

  defp navigation_dto(mission, nil, revision) do
    %{
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Catalog", href: ~p"/missions/#{mission.mission_id}/catalog"},
        %{label: revision.revision_label, href: nil}
      ]
    }
  end

  defp navigation_dto(mission, database, revision) do
    %{
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Catalog", href: ~p"/missions/#{mission.mission_id}/catalog"},
        %{
          label: database.name,
          href:
            ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
        },
        %{label: revision.revision_label, href: nil}
      ]
    }
  end

  defp provenance_dto(mission_id, revision, database, artifact, import_run) do
    %{
      id: "catalog-revision-provenance",
      title: "Revision provenance",
      rows: [
        detail_row("Database", database && database.name),
        detail_row("Artifact", artifact && artifact.artifact_name,
          href: artifact_href(artifact, mission_id)
        ),
        detail_row("Import run", import_run && import_run.import_run_id,
          href: import_run_href(import_run, mission_id),
          style: "mono"
        ),
        detail_row("Content SHA-256", revision.content_sha256, style: "hash")
      ]
    }
  end

  defp artifact_href(nil, _mission_id), do: nil

  defp artifact_href(artifact, mission_id) do
    ~p"/missions/#{mission_id}/catalog/artifacts/#{artifact.artifact_id}"
  end

  defp import_run_href(nil, _mission_id), do: nil

  defp import_run_href(import_run, mission_id) do
    ~p"/missions/#{mission_id}/catalog/imports/#{import_run.import_run_id}"
  end

  defp runtime_usage_dto do
    %{
      id: "catalog-revision-runtime-usage",
      title: "Runtime usage",
      summary_id: "catalog-runtime-usage-summary",
      summary: "No runtime bindings yet.",
      action: %{
        id: "catalog-revision-runtime-action",
        label: "Use this revision in runtime",
        disabled: true
      }
    }
  end

  defp mission_model_dto(nil, _runtime_plans) do
    %{
      id: "catalog-mission-model",
      title: "Mission Model",
      available: false,
      empty_message: "Mission Model unavailable.",
      rows: []
    }
  end

  defp mission_model_dto(mission_model, runtime_plans) do
    %{
      id: "catalog-mission-model",
      title: "Mission Model",
      available: true,
      empty_message: "Mission Model unavailable.",
      rows: [
        detail_row("Revision", mission_model.revision_id, style: "hash"),
        detail_row("Declarations", map_size(mission_model.declarations)),
        detail_row("Space systems", map_size(mission_model.space_systems)),
        detail_row("Ready plans", ready_plan_count(runtime_plans))
      ]
    }
  end

  defp detail_row(label, value, opts \\ []) do
    %{
      label: label,
      value: value,
      href: Keyword.get(opts, :href),
      style: Keyword.get(opts, :style, "default")
    }
  end

  defp ready_plan_count(plans) do
    Enum.count(plans, fn {_target, plan} -> plan.status == :ready end)
  end

  defp fetch_optional(fun) when is_function(fun, 0) do
    case fun.() do
      {:ok, value} -> value
      {:error, _reason} -> nil
    end
  end
end
