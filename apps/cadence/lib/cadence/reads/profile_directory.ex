defmodule Cadence.Reads.ProfileDirectory do
  @moduledoc """
  The Setup profiles list: each active spacecraft profile at its latest
  version, with how many spacecraft pin it and how many of those pin an older
  version, how many per-spacecraft overrides it has (as the detail's `override_count`) and its
  `last_change` (as the detail's). Callers authorize first.
  """

  alias Cadence.Reads.{CatalogCompositions, CatalogRollout}
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.Overrides
  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftTypeStore

  @protocol_labels %{
    tm: "CCSDS TM",
    aos: "CCSDS AOS",
    uslp: "CCSDS USLP",
    tc: "CCSDS TC",
    space_packet: "CCSDS Space Packet"
  }

  @doc "Display label for a protocol enum value."
  @spec protocol_label(atom() | nil) :: binary() | nil
  def protocol_label(nil), do: nil
  def protocol_label(value), do: Map.get(@protocol_labels, value, to_string(value))

  @doc "`[%{value, label}]` options for a protocol field."
  @spec protocol_options(:downlink | :uplink | :packet) :: [map()]
  def protocol_options(:downlink), do: options(SpacecraftType.downlink_protocols())
  def protocol_options(:uplink), do: options(SpacecraftType.uplink_protocols())
  def protocol_options(:packet), do: options(SpacecraftType.packet_protocols())

  @spec load(binary(), binary()) :: [map()]
  def load(organization_id, mission_id) do
    profiles = SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id)
    revisions = Cadence.Catalog.list_revisions(organization_id, mission_id)

    build(
      profiles,
      SpacecraftStore.fleet_summary(organization_id, mission_id).profile_version_counts,
      Map.new(revisions, &{&1.catalog_revision_id, &1.revision_number}),
      %{
        override_counts: override_counts(organization_id, mission_id),
        version_times: version_times(organization_id, mission_id, profiles),
        compositions:
          CatalogCompositions.by_catalog_revision(
            organization_id,
            mission_id,
            revisions,
            Enum.map(profiles, & &1.catalog_revision_id)
          )
      }
    )
  end

  @doc """
  Pure builder over latest profile versions, per-(profile, version) spacecraft counts, catalog
  revision numbers (id => number) and `extras`: `override_counts` (profile id => count),
  `version_times` (`{profile id, version}` => when that version was made) and `compositions`
  (catalog revision id => its composition, D2 #543).
  """
  @spec build([SpacecraftType.t()], [map()], %{binary() => pos_integer()}, map()) :: [map()]
  def build(profiles, version_counts, revision_numbers \\ %{}, extras \\ %{}) do
    override_counts = Map.get(extras, :override_counts, %{})
    version_times = Map.get(extras, :version_times, %{})
    compositions = Map.get(extras, :compositions, %{})
    counts = Enum.group_by(version_counts, & &1.spacecraft_type_id)

    Enum.map(profiles, fn %SpacecraftType{} = profile ->
      pinned = Map.get(counts, profile.spacecraft_type_id, [])

      %{
        id: profile.spacecraft_type_id,
        name: profile.display_name,
        version: profile.version,
        downlink_protocol: enum(profile.downlink_protocol),
        uplink_protocol: enum(profile.uplink_protocol),
        packet_protocol: enum(profile.packet_protocol),
        catalog_revision: CatalogRollout.ref(profile.catalog_revision_id, revision_numbers),
        composition: Map.get(compositions, profile.catalog_revision_id),
        spacecraft_count: pinned |> Enum.map(& &1.count) |> Enum.sum(),
        spacecraft_on_older_versions:
          pinned
          |> Enum.filter(&(&1.spacecraft_type_version < profile.version))
          |> Enum.map(& &1.count)
          |> Enum.sum(),
        override_count: Map.get(override_counts, profile.spacecraft_type_id, 0),
        last_change:
          last_change(
            profile,
            Map.get(version_times, {profile.spacecraft_type_id, profile.version})
          )
      }
    end)
  end

  # The detail's shape (ProfileDetail): which version and when; no revision or actor yet.
  defp last_change(_profile, nil), do: nil

  defp last_change(profile, at),
    do: %{version: profile.version, revision: nil, at: at, actor: nil}

  # Override entries (spacecraft × path) per profile, as the detail counts them, in bounded
  # batches over the fleet.
  defp override_counts(organization_id, mission_id) do
    profile_of =
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id)
      |> Enum.reject(&is_nil(&1.spacecraft_type_id))
      |> Map.new(&{&1.spacecraft_id, &1.spacecraft_type_id})

    profile_of
    |> Map.keys()
    |> Enum.chunk_every(SpacecraftStore.max_batch_size())
    |> Enum.flat_map(&Overrides.list(organization_id, mission_id, &1))
    |> Enum.reduce(%{}, fn {spacecraft_id, paths}, acc ->
      Map.update(acc, profile_of[spacecraft_id], map_size(paths), &(&1 + map_size(paths)))
    end)
  end

  defp version_times(organization_id, mission_id, profiles) do
    for profile <- profiles,
        row <-
          SpacecraftTypeStore.list_spacecraft_type_version_history(
            organization_id,
            mission_id,
            profile.spacecraft_type_id
          ),
        row.version == profile.version,
        into: %{},
        do: {{profile.spacecraft_type_id, row.version}, row.created_at}
  end

  defp enum(nil), do: nil
  defp enum(value), do: %{value: to_string(value), label: protocol_label(value)}

  defp options(values), do: Enum.map(values, &enum/1)
end
