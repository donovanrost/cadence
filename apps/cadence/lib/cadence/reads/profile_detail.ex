defmodule Cadence.Reads.ProfileDetail do
  @moduledoc """
  One spacecraft profile for the Setup detail view: header, schema-driven
  sections with current values (`Cadence.SpacecraftType.Schema`), inherit
  counts and version history. Callers authorize first.

  Profile-level routing rules and per-spacecraft overrides arrive with
  DECISIONS #3; until then `rules` and `overrides` are empty and
  `routing_model` is `:per_spacecraft`, so the UI can say routing is still
  configured per spacecraft.
  """

  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftType.Schema

  @spec load(binary(), binary(), binary()) :: {:ok, map()} | {:error, :spacecraft_type_not_found}
  def load(organization_id, mission_id, profile_id) do
    case Cadence.SpacecraftTypeStore.fetch_spacecraft_type(
           organization_id,
           mission_id,
           profile_id
         ) do
      {:ok, %SpacecraftType{} = profile} ->
        {:ok,
         build(%{
           profile: profile,
           versions:
             Cadence.SpacecraftTypeStore.list_spacecraft_type_version_history(
               organization_id,
               mission_id,
               profile_id
             ),
           version_counts:
             Cadence.SpacecraftStore.fleet_summary(organization_id, mission_id).profile_version_counts
         })}

      _missing ->
        {:error, :spacecraft_type_not_found}
    end
  end

  @doc "Pure builder; see `load/3` for the inputs."
  @spec build(map()) :: map()
  def build(%{profile: %SpacecraftType{} = profile} = input) do
    versions = Map.get(input, :versions, [])

    pinned =
      input
      |> Map.get(:version_counts, [])
      |> Enum.filter(&(&1.spacecraft_type_id == profile.spacecraft_type_id))

    inherit_count = pinned |> Enum.map(& &1.count) |> Enum.sum()

    %{
      profile: %{
        id: profile.spacecraft_type_id,
        name: profile.display_name,
        version: profile.version,
        catalog_revision: nil,
        protocols: %{
          downlink: enum_value(profile.downlink_protocol),
          uplink: enum_value(profile.uplink_protocol),
          packet: enum_value(profile.packet_protocol)
        },
        last_change: last_change(profile, versions)
      },
      inherit_count: inherit_count,
      on_older_versions:
        pinned
        |> Enum.filter(&(&1.spacecraft_type_version < profile.version))
        |> Enum.map(& &1.count)
        |> Enum.sum(),
      override_count: 0,
      sections: sections(profile),
      applications: profile.applications || %{},
      rules: [],
      overrides: [],
      routing_model: :per_spacecraft,
      versions: Enum.map(versions, &%{version: &1.version, created_at: &1.created_at, actor: nil})
    }
  end

  defp sections(profile) do
    Enum.map(Schema.sections(), fn section ->
      %{
        key: section.key,
        label: section.label,
        fields:
          Enum.map(section.fields, fn field ->
            field
            |> Map.put(:value, Schema.value(profile, field.path))
            |> Map.put(:overridden_by, 0)
          end)
      }
    end)
  end

  defp last_change(profile, versions) do
    case Enum.find(versions, &(&1.version == profile.version)) do
      nil -> nil
      version -> %{version: version.version, revision: nil, at: version.created_at, actor: nil}
    end
  end

  defp enum_value(nil), do: nil

  defp enum_value(value) do
    [option] = Schema.protocol_enum([value])
    option
  end
end
