defmodule Cadence.Dashboards.LibraryLifecycle do
  @moduledoc """
  Library widget update and retire (DECISIONS #76 Q6/Q10, plans/dashboards-library.md).

  A library item is retired, never deleted: old dashboard versions still place its versions, so
  they keep resolving for compare and restore. A retired item leaves the listing and reads as not
  found. Retiring is refused while any dashboard's current version places it, checked under the
  item's row lock in the same transaction as the retire, and a save refuses a placement of a
  retired item under a share lock on it (`live_items/3`), so a concurrent add and retire can't
  leave a current version placing a retired item.

  Both writes guard on `expected_version`, the item's `latest_version`:
  `{:library_item_changed, latest_version}` when it moved.
  """

  import Ecto.Query

  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.{Authoring, AuthoringInput, ConfigAudit, DashboardLibraryItem}
  alias Cadence.Dashboards.DocumentStore.DashboardRow
  alias Cadence.Repo

  @doc """
  Renames or redescribes an item (`%{"name"?, "description"?}`; a new definition is a new
  version). `{:ok, item}` or `{:error, :not_found | :invalid_input |
  {:library_item_changed, latest_version} | :forbidden}`.
  """
  def update_item(
        %Scope{} = scope,
        mission,
        item_id,
        input,
        expected_version,
        expected_updated_at \\ nil
      ) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, changes} <- changes(input),
         {:ok, observed} <- observed_at(expected_updated_at) do
      transaction(fn ->
        item =
          locked_item!(scope.organization_id, mission, item_id, {expected_version, observed})

        item
        |> Ecto.Changeset.change(Map.put(changes, :updated_by, scope.user.user_id))
        |> Repo.update!()
      end)
    end
  end

  @doc """
  Retires an item. `:ok`, or `{:error, :not_found | {:library_item_changed, latest_version} |
  {:library_item_in_use, %{used_by: %{dashboards: [%{id, name, placements,
  pinned_versions}]}, consumer_count}} | :forbidden}`.
  """
  def retire_item(
        %Scope{} = scope,
        mission,
        item_id,
        expected_version,
        expected_updated_at \\ nil
      ) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, observed} <- observed_at(expected_updated_at) do
      transaction(fn -> retire_locked(scope, mission, item_id, {expected_version, observed}) end)
    end
  end

  defp retire_locked(scope, mission, item_id, expected) do
    item = locked_item!(scope.organization_id, mission, item_id, expected)

    case used_by(scope.organization_id, mission, item_id) do
      [] ->
        item
        |> Ecto.Changeset.change(retired_at: DateTime.utc_now(), retired_by: scope.user.user_id)
        |> Repo.update!()

        ConfigAudit.record(scope, mission, :library_item_retired, %{
          kind: "library_item",
          id: item_id,
          label: item.name
        })

      dashboards ->
        Repo.rollback(
          {:library_item_in_use,
           %{used_by: %{dashboards: dashboards}, consumer_count: length(dashboards)}}
        )
    end
  end

  @doc """
  For a save: `:ok` when every library item `document` places is live, share-locking them until
  the save commits; else `{:error, {:library_item_retired, item_id}}`.
  """
  def live_items(organization_id, mission_id, document) do
    ids =
      document.placements
      |> Enum.filter(&(&1.content_kind == :library and is_binary(&1.library_widget_id)))
      |> Enum.map(& &1.library_widget_id)
      |> Enum.uniq()

    live =
      if ids == [] do
        []
      else
        live_query(organization_id, mission_id)
        |> where([i], i.dashboard_library_item_id in ^ids)
        |> lock("FOR SHARE")
        |> select([i], i.dashboard_library_item_id)
        |> Repo.all()
      end

    case ids -- live do
      [] -> :ok
      [retired | _] -> {:error, {:library_item_retired, retired}}
    end
  end

  @doc """
  Whether a live item has `version` (add_library_widget): `:ok`, or a field error,
  `{:library_item_unavailable, "library_item_id"}` or `{:library_version_unavailable, "version"}`.
  """
  def version_available(organization_id, mission_id, item_id, version) do
    item =
      live_query(organization_id, mission_id)
      |> where([i], i.dashboard_library_item_id == ^item_id)
      |> select([i], i.latest_version)
      |> Repo.one()

    cond do
      is_nil(item) -> {:error, {:library_item_unavailable, "library_item_id"}}
      version > item -> {:error, {:library_version_unavailable, "version"}}
      true -> :ok
    end
  end

  @doc """
  The editor outline's view of the items a document places, in one query: `%{item_id => %{name,
  retired}}`. `retired` is true exactly when `live_items/3` would refuse the save: the item is
  retired or gone (a gone id has no name).
  """
  def placed_items(_organization_id, _mission_id, []), do: %{}

  def placed_items(organization_id, mission_id, ids) do
    found =
      from(i in DashboardLibraryItem,
        where:
          i.organization_id == ^organization_id and i.mission_id == ^mission_id and
            i.dashboard_library_item_id in ^ids,
        select: {i.dashboard_library_item_id, %{name: i.name, retired: not is_nil(i.retired_at)}}
      )
      |> Repo.all()
      |> Map.new()

    Map.new(ids, &{&1, Map.get(found, &1, %{name: nil, retired: true})})
  end

  @doc "Library items that haven't been retired (the listing's and reads' scope)."
  def live_query(organization_id, mission_id) do
    from(i in DashboardLibraryItem,
      where:
        i.organization_id == ^organization_id and i.mission_id == ^mission_id and
          is_nil(i.retired_at)
    )
  end

  # Dashboards whose current version places the item (the used_by_count rule).
  @doc "Active dashboards placing the item: `[%{id, name, placements, pinned_versions}]` (D21)."
  def used_by(organization_id, mission_id, item_id) do
    match = %{
      "placements" => [%{"content" => %{"kind" => "library", "library_widget_id" => item_id}}]
    }

    from(d in DashboardRow,
      where:
        d.organization_id == ^organization_id and d.mission_id == ^mission_id and
          d.lifecycle_state == "active" and fragment("? @> ?", d.document, ^match),
      order_by: d.dashboard_id,
      select: %{
        id: d.dashboard_id,
        name: d.name,
        pinned_versions:
          fragment(
            "(SELECT coalesce(jsonb_agg(DISTINCT (p->'content'->>'library_version')::bigint), '[]'::jsonb) FROM jsonb_array_elements(?->'placements') AS p WHERE p->'content'->>'kind' = 'library' AND p->'content'->>'library_widget_id' = ?)",
            d.document,
            ^item_id
          ),
        placements:
          fragment(
            "(SELECT count(*) FROM jsonb_array_elements(?->'placements') AS p WHERE p->'content'->>'kind' = 'library' AND p->'content'->>'library_widget_id' = ?)",
            d.document,
            ^item_id
          )
      }
    )
    |> Repo.all()
  end

  # Stale when the version moved, or (given the row as read) its updated_at did: a rename or
  # description change adds no version, so a second tab's stale edit is caught by updated_at.
  defp locked_item!(organization_id, mission_id, item_id, {expected_version, observed_at}) do
    item =
      live_query(organization_id, mission_id)
      |> where([i], i.dashboard_library_item_id == ^item_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    cond do
      is_nil(item) ->
        Repo.rollback(:not_found)

      item.latest_version != expected_version or moved?(item.updated_at, observed_at) ->
        Repo.rollback({:library_item_changed, item.latest_version})

      true ->
        item
    end
  end

  defp moved?(_updated_at, nil), do: false
  defp moved?(updated_at, observed), do: DateTime.compare(updated_at, observed) != :eq

  defp observed_at(nil), do: {:ok, nil}
  defp observed_at(%DateTime{} = at), do: {:ok, at}

  defp observed_at(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> {:ok, at}
      _invalid -> {:error, :invalid_input}
    end
  end

  defp observed_at(_other), do: {:error, :invalid_input}

  defp changes(input) when is_map(input) do
    name = input["name"]
    description = input["description"]

    cond do
      Map.keys(input) -- ["name", "description"] != [] ->
        {:error, :invalid_input}

      not is_nil(name) and not (AuthoringInput.text?(name, 120) and String.trim(name) != "") ->
        {:error, :invalid_input}

      not is_nil(description) and not AuthoringInput.text?(description, 4096) ->
        {:error, :invalid_input}

      true ->
        {:ok,
         %{name: name && String.trim(name), description: description}
         |> Enum.reject(fn {_key, value} -> is_nil(value) end)
         |> Map.new()}
    end
  end

  defp changes(_input), do: {:error, :invalid_input}

  defp transaction(fun) do
    case Repo.transaction(fun) do
      {:ok, :ok} -> :ok
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end
end
