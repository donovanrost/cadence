defmodule Cadence.Reads.CatalogRollout do
  @moduledoc """
  Catalog C3 "Roll out to": what staging a catalog revision on each profile would move.

  Every non-archived spacecraft pinned to a profile (at any version) counts in exactly one
  bucket, in this order (domain, #65):
  - `override_pinned`: an override sets its own `catalog_revision_id`, so it keeps it either way;
  - `already_on_revision`: its configured catalog (latest configuration) is the revision;
  - otherwise it is movable.

  `moves_default` is the movable ones on the profile's current version: a plain profile op moves
  only those. `moves_all` is the movable ones at any version: a rollout naming them re-pins them
  to the new profile version. Spacecraft without a profile are never moved (`unprofiled_count`).
  Callers authorize first.
  """

  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Catalog
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.Overrides
  alias Cadence.SpacecraftTypeStore

  @spec load(binary(), binary(), binary()) :: {:ok, map()} | {:error, :catalog_revision_not_found}
  def load(organization_id, mission_id, revision_id) do
    with {:ok, revision} <- Catalog.fetch_revision(organization_id, mission_id, revision_id) do
      spacecraft = SpacecraftStore.list_spacecraft(organization_id, mission_id)

      {:ok,
       build(%{
         revision_id: revision.catalog_revision_id,
         numbers: revision_numbers(organization_id, mission_id),
         profiles: SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id),
         spacecraft: spacecraft,
         own_catalog: own_catalog(organization_id, mission_id, spacecraft),
         configured: configured(organization_id, mission_id)
       })}
    end
  end

  @doc """
  Pure builder. `numbers`: revision id => number; `own_catalog`: ids of spacecraft whose
  override sets `catalog_revision_id`; `configured`: spacecraft id => configured revision id.
  """
  @spec build(map()) :: map()
  def build(
        %{revision_id: target, numbers: numbers, profiles: profiles, spacecraft: spacecraft} =
          input
      ) do
    by_profile = Enum.group_by(spacecraft, & &1.spacecraft_type_id)

    %{
      revision: ref(target, numbers),
      profiles:
        Enum.map(profiles, &profile(&1, Map.get(by_profile, &1.spacecraft_type_id, []), input)),
      unprofiled_count: length(Map.get(by_profile, nil, []))
    }
  end

  @doc "`{id, number, label}` for a catalog revision id (`label` is \"rev N\"), or nil."
  @spec ref(binary() | nil, %{binary() => pos_integer()}) :: map() | nil
  def ref(nil, _numbers), do: nil

  def ref(id, numbers) do
    number = Map.get(numbers, id)
    %{id: id, number: number, label: number && "rev #{number}"}
  end

  defp profile(profile, pinned, %{revision_id: target, numbers: numbers} = input) do
    buckets =
      Enum.map(
        pinned,
        &{&1.spacecraft_type_version == profile.version, bucket(&1, target, input)}
      )

    count = fn pred -> Enum.count(buckets, pred) end

    %{
      id: profile.spacecraft_type_id,
      name: profile.display_name,
      current_revision: ref(profile.catalog_revision_id, numbers),
      spacecraft_count: length(pinned),
      on_current_version: count.(&elem(&1, 0)),
      on_older_versions: count.(&(not elem(&1, 0))),
      override_pinned: count.(&(elem(&1, 1) == :override_pinned)),
      already_on_revision: count.(&(elem(&1, 1) == :already_on_revision)),
      moves_default: count.(&(&1 == {true, :movable})),
      moves_all: count.(&(elem(&1, 1) == :movable))
    }
  end

  defp bucket(spacecraft, target, %{own_catalog: own, configured: configured}) do
    cond do
      MapSet.member?(own, spacecraft.spacecraft_id) -> :override_pinned
      Map.get(configured, spacecraft.spacecraft_id) == target -> :already_on_revision
      true -> :movable
    end
  end

  defp revision_numbers(organization_id, mission_id) do
    organization_id
    |> Catalog.list_revisions(mission_id)
    |> Map.new(&{&1.catalog_revision_id, &1.revision_number})
  end

  defp own_catalog(organization_id, mission_id, spacecraft) do
    spacecraft
    |> Enum.map(& &1.spacecraft_id)
    |> Enum.chunk_every(SpacecraftStore.max_batch_size())
    |> Enum.flat_map(fn ids ->
      for {id, overrides} <- Overrides.list(organization_id, mission_id, ids),
          Map.has_key?(overrides, "catalog_revision_id"),
          do: id
    end)
    |> MapSet.new()
  end

  defp configured(organization_id, mission_id) do
    organization_id
    |> Drafts.catalog_usage_entries(mission_id)
    |> Map.new(&{&1.spacecraft_id, &1.catalog_revision_id})
  end
end
