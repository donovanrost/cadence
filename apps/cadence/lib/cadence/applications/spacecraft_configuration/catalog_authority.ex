defmodule Cadence.Applications.SpacecraftConfiguration.CatalogAuthority do
  @moduledoc """
  One writer for a spacecraft's catalog (DECISIONS #65). While a spacecraft's profile (with its
  overrides) names a catalog revision, that is the catalog: the spacecraft's configuration
  document follows it, a change set applies it (catalog-path generations, #36), and the
  per-spacecraft configuration refuses a different one. Spacecraft without a profile catalog
  keep setting it in their own configuration.

  Spacecraft whose configuration still uses another catalog than their profile sets are
  mismatches: they keep running on what they have until a change set touching them converges
  them; nothing re-points them silently.
  """

  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.Overrides
  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftType.Effective
  alias Cadence.SpacecraftTypeStore

  @doc "The catalog revision the spacecraft's profile (with its overrides) sets, or nil."
  @spec effective(map(), struct()) :: binary() | nil
  def effective(mission, spacecraft) do
    case SpacecraftStore.fetch_pinned_profile(mission, spacecraft) do
      {:ok, %SpacecraftType{} = profile} ->
        overrides =
          mission.organization_id
          |> Overrides.list(mission.mission_id, [spacecraft.spacecraft_id])
          |> Map.get(spacecraft.spacecraft_id, %{})

        Effective.resolve(profile, overrides)["catalog_revision_id"]

      _no_profile ->
        nil
    end
  end

  @doc """
  `effective/2` for many spacecraft (`%{id => spacecraft}`), reading their overrides in one query:
  `%{id => catalog_revision_id | nil}`. Fleet-scale previews use it (director 11-14).
  """
  @spec effective_many(map(), %{binary() => struct()}) :: %{binary() => binary() | nil}
  def effective_many(mission, spacecraft) when is_map(spacecraft) do
    overrides = Overrides.list(mission.organization_id, mission.mission_id, Map.keys(spacecraft))

    profiles = profiles(mission.organization_id, mission.mission_id, Map.values(spacecraft))

    Map.new(spacecraft, fn {id, sc} ->
      profile = profiles[{sc.spacecraft_type_id, sc.spacecraft_type_version}]
      effective = profile && Effective.resolve(profile, Map.get(overrides, id, %{}))
      {id, effective && effective["catalog_revision_id"]}
    end)
  end

  @doc """
  `:ok` when the spacecraft's own configuration may use `catalog_revision_id`: its profile sets
  none, or sets exactly that one. Otherwise `{:error, :spacecraft_catalog_set_by_profile}`.
  """
  @spec check(map(), struct(), binary() | nil) ::
          :ok | {:error, :spacecraft_catalog_set_by_profile}
  def check(mission, spacecraft, catalog_revision_id) do
    case effective(mission, spacecraft) do
      nil -> :ok
      ^catalog_revision_id -> :ok
      _other -> {:error, :spacecraft_catalog_set_by_profile}
    end
  end

  @doc """
  `:ok` when the spacecraft's own configuration may carry these commanding and telemetry
  switches: those a change set has set on the spacecraft (L22) are its only writer, so the
  configuration must match them. Otherwise `{:error, :spacecraft_switch_set_by_change_set}`.
  """
  @spec switches_check(struct(), map()) :: :ok | {:error, :spacecraft_switch_set_by_change_set}
  def switches_check(spacecraft, document) do
    set = [
      {"commanding_enabled", spacecraft.commanding_enabled},
      {"telemetry_enabled", spacecraft.telemetry_enabled}
    ]

    if Enum.all?(set, fn {key, value} -> is_nil(value) or document[key] == value end),
      do: :ok,
      else: {:error, :spacecraft_switch_set_by_change_set}
  end

  @doc """
  Spacecraft whose configuration uses another catalog than their profile sets:
  `[%{spacecraft_id, effective_catalog_revision_id, configured_catalog_revision_id}]`.
  """
  @spec mismatches(binary(), binary()) :: [map()]
  def mismatches(org, mission_id) do
    configured =
      org
      |> Drafts.catalog_usage_entries(mission_id)
      |> Map.new(&{&1.spacecraft_id, &1.catalog_revision_id})

    ids = Map.keys(configured)

    if ids == [] do
      []
    else
      spacecraft =
        ids
        |> Enum.chunk_every(SpacecraftStore.max_batch_size())
        |> Enum.reduce(%{}, fn chunk, acc ->
          {:ok, found} = SpacecraftStore.fetch_spacecrafts(org, mission_id, chunk)
          Map.merge(acc, found)
        end)

      overrides = Overrides.list(org, mission_id, ids)
      profiles = profiles(org, mission_id, Map.values(spacecraft))

      for {id, sc} <- spacecraft,
          profile = profiles[{sc.spacecraft_type_id, sc.spacecraft_type_version}],
          profile != nil,
          effective =
            Effective.resolve(profile, Map.get(overrides, id, %{}))["catalog_revision_id"],
          effective != nil and effective != configured[id] do
        %{
          spacecraft_id: id,
          effective_catalog_revision_id: effective,
          configured_catalog_revision_id: configured[id]
        }
      end
      |> Enum.sort_by(& &1.spacecraft_id)
    end
  end

  @doc false
  def profiles(org, mission, spacecraft) do
    pins =
      for sc <- spacecraft,
          is_binary(sc.spacecraft_type_id) and is_integer(sc.spacecraft_type_version),
          do: {sc.spacecraft_type_id, sc.spacecraft_type_version}

    {:ok, profiles} =
      SpacecraftTypeStore.fetch_spacecraft_type_versions_in_batches(org, mission, pins)

    profiles
  end
end
