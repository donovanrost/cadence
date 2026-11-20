defmodule CadenceWeb.Console.DashboardDirectoryController do
  @moduledoc """
  The console dashboard directory and its commands (owner: api-ops). Contract:
  docs/apogee/api/dashboards.md (D1 list, D2 star, D3 archive/restore, D4 create/duplicate,
  D6 record a view). Wraps `Reads.Dashboards.Directory`, `Dashboards.DirectoryActions` and
  `Dashboards.Creation`, which authorize: star and views for any mission operator; archive,
  restore, create and duplicate for dashboard authors.
  """

  use CadenceWeb, :controller

  require Logger

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    Creation,
    DirectoryActions,
    Documents,
    PlaylistStore,
    PublishReadinessPresentation,
    ValidationResult
  }

  alias Cadence.Reads.Dashboards.{Authors, BindingSummary, Directory}
  alias CadenceWeb.Console.Problem

  @filters ~w(tags starred archived sort page)

  def index(conn, params) do
    filters =
      params
      |> Map.take(@filters)
      |> then(&if(params["q"], do: Map.put(&1, "query", params["q"]), else: &1))

    case Directory.load(scope(conn), mission(conn), filters) do
      {:ok, model} -> json(conn, %{data: directory(conn, model)})
      {:error, :invalid_filters} -> Problem.respond(conn, :invalid_params)
      {:error, _denied_or_unavailable} -> Problem.respond(conn, :dashboard_unavailable)
    end
  end

  def star(conn, %{"dashboard_id" => id}), do: set_star(conn, id, true)
  def unstar(conn, %{"dashboard_id" => id}), do: set_star(conn, id, false)

  def view(conn, %{"dashboard_id" => id}) do
    with {:ok, _summary} <- active(conn, id),
         {:ok, _preference} <-
           Dashboards.record_dashboard_view(
             scope(conn).organization_id,
             mission(conn),
             scope(conn).user.user_id,
             id
           ) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} -> Problem.respond(conn, :not_found)
      _error -> Problem.respond(conn, :dashboard_unavailable)
    end
  end

  # Archiving a dashboard a playlist shows needs `confirm: true` (director Q10).
  def archive(conn, %{"dashboard_id" => id} = params) do
    used_by = PlaylistStore.using_dashboard(scope(conn).organization_id, mission(conn), id)

    with {:ok, _summary} <- active(conn, id),
         :ok <- confirmed(used_by, params["confirm"]) do
      lifecycle(conn, "archive", id)
    else
      {:error, :not_found} ->
        Problem.respond(conn, :not_found)

      {:error, :in_use} ->
        Problem.respond(conn, :dashboard_in_use, %{used_by: %{playlists: used_by}})
    end
  end

  def restore(conn, %{"dashboard_id" => id}), do: lifecycle(conn, "restore", id)

  def create(conn, params) do
    input =
      params
      |> Map.take(~w(name description tags spacecraft))
      # Optional fields may come as null (qa: the console sent description: null).
      |> Map.reject(fn {key, value} -> key != "name" and is_nil(value) end)
      |> Map.put_new("description", "")

    case creation_fields(input) do
      :ok -> create_dashboard(conn, input)
      {:invalid, field} -> Problem.respond(conn, :invalid_params, %{field: field})
    end
  end

  defp create_dashboard(conn, input) do
    case Creation.create(scope(conn), mission(conn), %{mode: "new"}, input) do
      {:ok, created} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{id: created.dashboard_id, version: created.version}})

      {:error, :forbidden} ->
        Problem.respond(conn, :forbidden)

      {:invalid, :spacecraft} ->
        Problem.respond(conn, :invalid_params, %{field: "spacecraft"})

      {:invalid, _reason} ->
        Problem.respond(conn, :invalid_params, %{field: "name"})

      error ->
        command_error(conn, error, "name")
    end
  end

  # Which field is wrong, before Creation's all-or-nothing check (it only says :fields).
  defp creation_fields(input) do
    cond do
      not (is_binary(input["name"]) and String.trim(input["name"]) != "" and
               byte_size(input["name"]) <= 512) ->
        {:invalid, "name"}

      not (is_binary(input["description"]) and byte_size(input["description"]) <= 4096) ->
        {:invalid, "description"}

      not tags?(Map.get(input, "tags", [])) ->
        {:invalid, "tags"}

      not spacecraft?(Map.get(input, "spacecraft")) ->
        {:invalid, "spacecraft"}

      true ->
        :ok
    end
  end

  defp tags?(tags) when is_list(tags) and length(tags) <= 10,
    do: Enum.all?(tags, &(is_binary(&1) and String.trim(&1) != "" and byte_size(&1) <= 64))

  defp tags?(_tags), do: false

  defp spacecraft?(nil), do: true

  defp spacecraft?(%{"mode" => mode} = value) when mode in ~w(context fleet),
    do: map_size(value) == 1

  defp spacecraft?(%{"mode" => "fixed", "spacecraft_id" => id} = value),
    do: map_size(value) == 2 and is_binary(id) and id != ""

  defp spacecraft?(_value), do: false

  def duplicate(conn, %{"dashboard_id" => id} = params) do
    input = %{"dashboard_id" => id, "name" => to_string(params["name"] || "")}

    case DirectoryActions.execute(scope(conn), mission(conn), "duplicate", input) do
      {:ok, %{dashboard_id: new_id}} ->
        {:ok, summary} =
          Documents.fetch_summary(scope(conn).organization_id, mission(conn), new_id)

        conn
        |> put_status(:created)
        |> json(%{data: %{id: new_id, version: summary.latest_version}})

      error ->
        command_error(conn, error, "name")
    end
  end

  defp set_star(conn, id, starred) do
    input = %{"dashboard_id" => id, "starred" => starred}

    with {:ok, _summary} <- active(conn, id),
         {:ok, _starred} <- DirectoryActions.execute(scope(conn), mission(conn), "star", input) do
      send_resp(conn, :no_content, "")
    else
      error -> command_error(conn, error, "dashboard_id")
    end
  end

  defp lifecycle(conn, event, id) do
    case DirectoryActions.execute(scope(conn), mission(conn), event, %{"dashboard_id" => id}) do
      {:ok, %{archived: archived}} -> json(conn, %{data: %{archived: archived}})
      error -> command_error(conn, error, "dashboard_id")
    end
  end

  defp command_error(conn, {:error, reason}, _field)
       when reason in [:not_found, :dashboard_not_found],
       do: Problem.respond(conn, :not_found)

  defp command_error(conn, {:error, :invalid_name}, _field),
    do: Problem.respond(conn, :invalid_params, %{field: "name"})

  defp command_error(conn, {:error, reason}, _field)
       when reason in [:forbidden, :unauthorized, :authenticated_user_required],
       do: Problem.respond(conn, :forbidden)

  defp command_error(conn, {:error, :invalid_request}, field),
    do: Problem.respond(conn, :invalid_params, %{field: field})

  # Creating or duplicating publishes the first version (D9's rule): say what isn't ready.
  defp command_error(
         conn,
         {:error, {:invalid_dashboard_document, %ValidationResult{errors: errors}}},
         _field
       ),
       do:
         Problem.respond(conn, :dashboard_not_ready, %{
           placements: PublishReadinessPresentation.editor_issues(errors)
         })

  defp command_error(conn, error, _field) do
    Logger.warning("dashboard directory command failed: #{inspect(error, limit: 20)}")
    Problem.respond(conn, :dashboard_unavailable)
  end

  defp confirmed([], _confirm), do: :ok
  defp confirmed(_used_by, confirm) when confirm in [true, "true"], do: :ok
  defp confirmed(_used_by, _confirm), do: {:error, :in_use}

  defp active(conn, id) do
    case Documents.fetch_summary(scope(conn).organization_id, mission(conn), id) do
      {:ok, %{lifecycle_state: "active"} = summary} -> {:ok, summary}
      _missing_or_archived -> {:error, :not_found}
    end
  end

  # Directory's rows, rebuilt with the fields the console contract adds (updated_by's id, the
  # spacecraft binding summary); the LiveView keeps Directory's own row shape.
  defp directory(conn, model) do
    org = scope(conn).organization_id
    rows = model.rows ++ model.shortcuts.starred ++ model.shortcuts.recent
    ids = Enum.map(rows, & &1.id)

    summaries =
      (Documents.list_summaries(org, mission(conn)) ++
         Documents.list_archived_summaries(org, mission(conn)))
      |> Map.new(&{&1.dashboard_id, &1})

    authors =
      summaries
      |> Map.take(ids)
      |> Map.values()
      |> Enum.map(& &1.published_by)
      |> then(&Authors.members(org, &1))

    context = %{
      summaries: summaries,
      authors: authors,
      spacecraft: BindingSummary.load(org, mission(conn), ids)
    }

    %{
      dashboards: Enum.map(model.rows, &row(&1, context)),
      available_tags: model.available_tags,
      total: model.total,
      page: model.filters["page"],
      pages: model.pages,
      page_size: model.page_size,
      can_create: model.author,
      shortcuts: %{
        starred: Enum.map(model.shortcuts.starred, &row(&1, context)),
        recent: Enum.map(model.shortcuts.recent, &row(&1, context))
      }
    }
  end

  defp row(row, context) do
    author_id = context.summaries |> Map.get(row.id, %{}) |> Map.get(:published_by)

    %{
      id: row.id,
      name: row.name,
      description: row.description,
      tags: row.tags,
      archived: row.archived,
      starred: row.starred,
      current_version: row.version,
      updated_at: row.updated_at,
      updated_by: Authors.person(context.authors, author_id),
      viewed_at: row.viewed_at,
      spacecraft: Map.get(context.spacecraft, row.id)
    }
  end

  defp scope(conn), do: conn.assigns.current_scope
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
