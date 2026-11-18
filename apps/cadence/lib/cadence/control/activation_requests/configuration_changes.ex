defmodule Cadence.Control.ActivationRequests.ConfigurationChanges do
  @moduledoc """
  What a spacecraft configuration request changes, for L10's detail (#235; ux U94; lead's final
  shape 11-18 08:49:52Z): the reviewed spacecraft grouped by IDENTICAL change, so every distinct
  change is sent once, exact and never cut, however large the fleet.

  `{groups: [{rows, first_start, telemetry_enabled, count, spacecraft: [{spacecraft_id, name}]}],
  total}`. A group is the craft whose `rows`, `first_start` and `telemetry_enabled` are equal.
  Changed groups come first, in the request's order (its sorted spacecraft ids); the group with no
  changed row comes last. Each group names at most 100 craft (`names/4` pages the rest); `count`
  is exact. `total` counts every reviewed craft, so a craft whose reviewed version can't be read is
  in `total` but in no group (the console says so).

  Rows compare the reviewed version with what runs now (the mission's active entry); with nothing
  active (`first_start`), every set field is a row with `before: nil`. That's exact while the
  request is pending (approval refuses a review whose base moved), so only a pending request
  carries it; once decided it's nil (after an apply, what runs IS the reviewed content). The switches are never rows
  (change sets own them, DECISIONS #109); `telemetry_enabled` is the value it will run with.
  """
  alias Cadence.Applications.SpacecraftConfiguration.{Active, Drafts}
  alias Cadence.Catalog
  alias Cadence.Catalog.SpacecraftModelBindings
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  @page 100
  @protocol ~w(downlink uplink frame_size secondary_header_length insert_zone_length ocf_length truncated_primary_header)
  @labels %{
    "catalog_revision" => "Catalog revision",
    "telemetry_source" => "Packet source",
    "handled_apids" => "Decoded APIDs",
    "downlink" => "Downlink protocol",
    "uplink" => "Uplink protocol",
    "frame_size" => "Frame size",
    "secondary_header_length" => "Secondary header",
    "insert_zone_length" => "Insert zone",
    "ocf_length" => "OCF",
    "truncated_primary_header" => "Truncated primary header"
  }

  @doc "The grouped changes for a configuration request, or nil for any other request."
  @spec for_request(map(), map()) :: map() | nil
  def for_request(mission, request) do
    case groups(mission, request) do
      {:ok, groups, total} ->
        %{
          groups:
            Enum.map(groups, &Map.update!(&1, :spacecraft, fn ids -> Enum.take(ids, @page) end))
            |> name_groups(mission),
          total: total
        }

      :none ->
        nil
    end
  end

  @doc """
  The reviewed spacecraft of a configuration request, on every state (lead 11-18):
  `{spacecraft: [{id, name}] (at most 100, the request's order), spacecraft_total}`, or nil for
  any other request (so the console can link a decided request's craft).
  """
  @spec reviewed(map(), map()) :: map() | nil
  def reviewed(mission, %{metadata: %{"configuration_review" => _} = metadata}) do
    case SpacecraftModelBindings.reviewed_spacecraft_ids(metadata) do
      {:ok, ids} ->
        shown = Enum.take(ids, @page)
        names = names_for(mission, shown)

        %{
          spacecraft: Enum.map(shown, &%{id: &1, name: names[&1]}),
          spacecraft_total: length(ids)
        }

      {:error, _unreadable} ->
        nil
    end
  end

  def reviewed(_mission, _request), do: nil

  @doc "One page (100) of a group's craft names: `{spacecraft, next_offset}`."
  @spec names(map(), map(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, :configuration_changes_group_not_found}
  def names(mission, request, index, offset) do
    with {:ok, groups, _total} <- groups(mission, request),
         %{spacecraft: ids} <- Enum.at(groups, index) do
      page = ids |> Enum.drop(offset) |> Enum.take(@page)
      next = if offset + @page < length(ids), do: offset + @page

      {:ok, %{spacecraft: named(mission, page), next_offset: next}}
    else
      _none -> {:error, :configuration_changes_group_not_found}
    end
  end

  defp groups(mission, %{
         state: :approval_pending,
         metadata: %{"configuration_review" => _} = metadata
       }) do
    with {:ok, ids} <- SpacecraftModelBindings.reviewed_spacecraft_ids(metadata),
         {:ok, active} <- Active.load(mission) do
      reviewed = reviewed_documents(mission, metadata, ids)
      lookups = lookups(mission, reviewed, active, ids)

      groups =
        ids
        |> Enum.filter(&Map.has_key?(reviewed, &1))
        |> Enum.map(&change(&1, reviewed[&1], active.entries[&1], lookups))
        |> group()

      {:ok, groups, length(ids)}
    else
      _unreadable -> :none
    end
  end

  defp groups(_mission, _request), do: :none

  # The reviewed version of each craft: its latest saved version, one query, kept only when it IS
  # the reviewed one (a craft saved since the review is stale; it's counted in `total` only).
  defp reviewed_documents(mission, metadata, ids) do
    latest = Drafts.latest_many(mission.organization_id, mission.mission_id, ids)

    for id <- ids,
        %{configuration_revision_id: revision, document: document} <- [latest[id]],
        revision ==
          (SpacecraftModelBindings.review_for(metadata, id) || %{})["configuration_revision_id"],
        into: %{},
        do: {id, document}
  end

  defp change(id, document, active_entry, lookups) do
    before = active_entry && active_entry["document"]

    %{
      id: id,
      key:
        {rows(before, document, lookups), is_nil(before), document["telemetry_enabled"] == true}
    }
  end

  defp group(changes) do
    {groups, order} =
      Enum.reduce(changes, {%{}, []}, fn %{id: id, key: key}, {groups, order} ->
        if Map.has_key?(groups, key),
          do: {Map.update!(groups, key, &[id | &1]), order},
          else: {Map.put(groups, key, [id]), [key | order]}
      end)

    order
    |> Enum.reverse()
    |> Enum.map(fn {rows, first_start, telemetry} = key ->
      ids = Enum.reverse(groups[key])

      %{
        rows: rows,
        first_start: first_start,
        telemetry_enabled: telemetry,
        count: length(ids),
        spacecraft: ids
      }
    end)
    # A first start always changes something (the craft starts running), even with no set field.
    |> Enum.sort_by(&(&1.rows == [] and not &1.first_start))
  end

  defp rows(before, document, lookups) do
    before = before || %{}

    [
      {"catalog_revision", before["catalog_revision_id"], document["catalog_revision_id"],
       &catalog(&1, lookups)},
      {"telemetry_source", before["telemetry_source_endpoint_id"],
       document["telemetry_source_endpoint_id"], &source(&1, lookups)},
      {"handled_apids", apids(before["handled_apids"]), apids(document["handled_apids"]), & &1}
    ]
    |> Kernel.++(
      Enum.map(@protocol, fn field ->
        {field, get_in(before, ["protocol", field]), get_in(document, ["protocol", field]), & &1}
      end)
    )
    |> Enum.reject(fn {_field, from, to, _view} -> from == to end)
    |> Enum.map(fn {field, from, to, view} ->
      %{field: field, label: @labels[field], before: view.(from), after: view.(to)}
    end)
  end

  defp apids(nil), do: nil
  defp apids([]), do: nil
  defp apids(list) when is_list(list), do: Enum.sort(list)

  defp catalog(nil, _lookups), do: nil
  defp catalog(id, lookups), do: %{id: id, number: lookups.catalogs[id]}

  defp source(nil, _lookups), do: nil
  defp source(id, lookups), do: %{id: id, name: lookups.sources[id]}

  # Catalog revision numbers and packet source names, once for the whole request.
  defp lookups(mission, reviewed, active, ids) do
    documents =
      Map.values(reviewed) ++
        Enum.flat_map(ids, fn id -> List.wrap(get_in(active.entries, [id, "document"])) end)

    catalogs =
      documents
      |> Enum.map(& &1["catalog_revision_id"])
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Map.new(fn id ->
        case Catalog.fetch_revision(mission.organization_id, mission.mission_id, id) do
          {:ok, revision} -> {id, revision.revision_number}
          {:error, _} -> {id, nil}
        end
      end)

    sources =
      documents
      |> Enum.map(& &1["telemetry_source_endpoint_id"])
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> then(&SourceEndpoints.display_names(mission.organization_id, mission.mission_id, &1))

    %{catalogs: catalogs, sources: sources}
  end

  defp name_groups(groups, mission) do
    names = names_for(mission, Enum.flat_map(groups, & &1.spacecraft))

    Enum.map(groups, fn group ->
      %{group | spacecraft: Enum.map(group.spacecraft, &%{spacecraft_id: &1, name: names[&1]})}
    end)
  end

  defp named(mission, ids) do
    names = names_for(mission, ids)
    Enum.map(ids, &%{spacecraft_id: &1, name: names[&1]})
  end

  defp names_for(mission, ids) do
    case SpacecraftStore.fetch_spacecrafts_in_batches(
           mission.organization_id,
           mission.mission_id,
           ids
         ) do
      {:ok, found} -> Map.new(found, fn {id, craft} -> {id, craft.display_name} end)
      {:error, _bounds} -> %{}
    end
  end
end
