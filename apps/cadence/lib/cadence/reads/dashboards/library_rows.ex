defmodule Cadence.Reads.Dashboards.LibraryRows do
  @moduledoc """
  Console library reads (D21, fe-ops' docs/apogee/plans/dashboards-library.md): live (unretired)
  items a page at a time with their kind, use count and last change, and one item at a version
  with its history and the dashboards using it. Mission operators read; `can_edit` is the author
  check. Use counts follow the retire rule (`LibraryLifecycle.used_by/3`).
  """

  import Ecto.Query

  alias Cadence.Auth.Policy
  alias Cadence.Dashboards.{Authoring, DashboardLibraryVersion, LibraryLifecycle}
  alias Cadence.Reads.Dashboards.Authors
  alias Cadence.Repo

  @page_size 25
  @versions 100

  @spec list(map(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def list(scope, mission, params) do
    org = scope.organization_id

    with :ok <- authorize(scope, mission),
         {:ok, page} <- page(params["page"]) do
      query = org |> LibraryLifecycle.live_query(mission) |> search(params["q"])
      total = Repo.aggregate(query, :count)

      items =
        query
        |> order_by([i], asc: i.name, asc: i.dashboard_library_item_id)
        |> offset(^((page - 1) * @page_size))
        |> limit(@page_size)
        |> Repo.all()

      latest = latest_versions(items)
      names = Authors.names(org, Enum.map(items, &(&1.updated_by || &1.created_by)))

      {:ok,
       %{
         items:
           Enum.map(items, fn item ->
             item
             |> summary(latest, names)
             |> Map.put(
               :used_by_count,
               length(LibraryLifecycle.used_by(org, mission, item.dashboard_library_item_id))
             )
           end),
         total: total,
         page: page,
         pages: max(1, div(total + @page_size - 1, @page_size)),
         page_size: @page_size,
         can_edit: can_edit?(scope, mission)
       }}
    end
  end

  @spec get(map(), binary(), binary(), term()) :: {:ok, map()} | {:error, term()}
  def get(scope, mission, item_id, version_param) do
    org = scope.organization_id

    with :ok <- authorize(scope, mission),
         item when not is_nil(item) <- live_item(org, mission, item_id),
         {:ok, wanted} <- version(version_param, item.latest_version),
         versions = versions(item_id),
         %DashboardLibraryVersion{} = selected <- Enum.find(versions, &(&1.version == wanted)) do
      names =
        Authors.names(org, [
          item.updated_by,
          item.created_by | Enum.map(versions, & &1.created_by)
        ])

      latest = %{item_id => Enum.find(versions, &(&1.version == item.latest_version))}

      {:ok,
       %{
         item: summary(item, latest, names),
         version:
           version_row(selected, names)
           |> Map.put(:definition_json, Jason.encode!(selected.widget_definition)),
         versions: Enum.map(versions, &version_row(&1, names)),
         used_by: %{dashboards: LibraryLifecycle.used_by(org, mission, item_id)},
         can_edit: can_edit?(scope, mission)
       }}
    else
      nil -> {:error, :library_item_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp summary(item, latest, names) do
    version = Map.get(latest, item.dashboard_library_item_id)

    %{
      id: item.dashboard_library_item_id,
      name: item.name,
      description: item.description || "",
      kind: version && kind(version.widget_definition),
      latest_version: item.latest_version,
      updated_at: item.updated_at,
      updated_by: person(item.updated_by || item.created_by, names)
    }
  end

  defp version_row(version, names),
    do: %{
      version: version.version,
      summary: version.change_summary || "",
      saved_at: version.inserted_at,
      saved_by: person(version.created_by, names)
    }

  defp kind(definition) when is_map(definition),
    do: definition["widget_type_id"] || definition[:widget_type_id]

  defp kind(_definition), do: nil

  defp latest_versions([]), do: %{}

  defp latest_versions(items) do
    pairs = Enum.map(items, &{&1.dashboard_library_item_id, &1.latest_version})
    ids = Enum.map(pairs, &elem(&1, 0))

    DashboardLibraryVersion
    |> where([v], v.dashboard_library_item_id in ^ids)
    |> Repo.all()
    |> Enum.filter(&({&1.dashboard_library_item_id, &1.version} in pairs))
    |> Map.new(&{&1.dashboard_library_item_id, &1})
  end

  defp versions(item_id) do
    DashboardLibraryVersion
    |> where([v], v.dashboard_library_item_id == ^item_id)
    |> order_by([v], desc: v.version)
    |> limit(@versions)
    |> Repo.all()
  end

  defp live_item(org, mission, item_id) do
    org
    |> LibraryLifecycle.live_query(mission)
    |> where([i], i.dashboard_library_item_id == ^item_id)
    |> Repo.one()
  end

  defp search(query, q) when is_binary(q) and q != "" do
    text = String.trim(q)

    where(
      query,
      [i],
      fragment("strpos(lower(?), lower(?)) > 0", i.name, ^text) or
        fragment("strpos(lower(coalesce(?, '')), lower(?)) > 0", i.description, ^text)
    )
  end

  defp search(query, _q), do: query

  defp page(nil), do: {:ok, 1}
  defp page(n) when is_integer(n) and n > 0, do: {:ok, n}

  defp page(text) when is_binary(text) do
    case Integer.parse(text) do
      {n, ""} when n > 0 -> {:ok, n}
      _invalid -> {:error, {:invalid_params, %{page: "must be a positive integer"}}}
    end
  end

  defp page(_value), do: {:error, {:invalid_params, %{page: "must be a positive integer"}}}

  defp version(nil, latest), do: {:ok, latest}

  defp version(value, _latest) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> {:ok, n}
      _invalid -> {:error, {:invalid_params, %{version: "must be a positive integer"}}}
    end
  end

  defp person(id, names) when is_binary(id), do: %{id: id, name: Map.get(names, id)}
  defp person(_none, _names), do: nil

  defp authorize(scope, mission) do
    case Policy.authorize(scope, :operate_mission, %{
           organization_id: scope.organization_id,
           mission_id: mission
         }) do
      :ok -> :ok
      _denied -> {:error, :forbidden}
    end
  end

  defp can_edit?(scope, mission), do: Authoring.authorize(scope, mission) == :ok
end
