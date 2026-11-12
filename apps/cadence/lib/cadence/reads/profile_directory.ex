defmodule Cadence.Reads.ProfileDirectory do
  @moduledoc """
  The Setup profiles list: each active spacecraft profile at its latest
  version, with how many spacecraft pin it and how many of those pin an older
  version. Callers authorize first.
  """

  alias Cadence.Reads.CatalogRollout
  alias Cadence.SpacecraftType

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
    build(
      Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id),
      Cadence.SpacecraftStore.fleet_summary(organization_id, mission_id).profile_version_counts,
      organization_id
      |> Cadence.Catalog.list_revisions(mission_id)
      |> Map.new(&{&1.catalog_revision_id, &1.revision_number})
    )
  end

  @doc """
  Pure builder over latest profile versions, per-(profile, version) spacecraft counts and catalog
  revision numbers (id => number).
  """
  @spec build([SpacecraftType.t()], [map()], %{binary() => pos_integer()}) :: [map()]
  def build(profiles, version_counts, revision_numbers \\ %{}) do
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
        spacecraft_count: pinned |> Enum.map(& &1.count) |> Enum.sum(),
        spacecraft_on_older_versions:
          pinned
          |> Enum.filter(&(&1.spacecraft_type_version < profile.version))
          |> Enum.map(& &1.count)
          |> Enum.sum()
      }
    end)
  end

  defp enum(nil), do: nil
  defp enum(value), do: %{value: to_string(value), label: protocol_label(value)}

  defp options(values), do: Enum.map(values, &enum/1)
end
