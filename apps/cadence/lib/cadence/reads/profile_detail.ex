defmodule Cadence.Reads.ProfileDetail do
  @moduledoc """
  One spacecraft profile for the Setup detail view: header, schema-driven
  sections with current values (`Cadence.SpacecraftType.Schema`), inherit
  counts and version history. Callers authorize first.

  Profile-level routing rules and per-spacecraft overrides come from
  `Cadence.Reads.ProfileRouting` (DECISIONS #3). `routing_model` is `:profile`
  when the profile has rules, else `:per_spacecraft` (legacy per-spacecraft
  rules not yet lifted onto the profile).
  """

  alias Cadence.Catalog
  alias Cadence.Reads.{CatalogRollout, ProfileRouting}
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
        revisions = Catalog.list_revisions(organization_id, mission_id)

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
             Cadence.SpacecraftStore.fleet_summary(organization_id, mission_id).profile_version_counts,
           rules: ProfileRouting.rules(organization_id, mission_id, profile),
           overrides: ProfileRouting.overrides(organization_id, mission_id, profile),
           extra_routes: ProfileRouting.extra_routes(organization_id, mission_id, profile),
           catalog_choices: Enum.map(revisions, &catalog_choice/1),
           revision_numbers: Map.new(revisions, &{&1.catalog_revision_id, &1.revision_number})
         })}

      _missing ->
        {:error, :spacecraft_type_not_found}
    end
  end

  @doc "Pure builder; see `load/3` for the inputs."
  @spec build(map()) :: map()
  def build(%{profile: %SpacecraftType{} = profile} = input) do
    versions = Map.get(input, :versions, [])
    rules = Map.get(input, :rules, [])
    overrides = Map.get(input, :overrides, [])

    pinned =
      input
      |> Map.get(:version_counts, [])
      |> Enum.filter(&(&1.spacecraft_type_id == profile.spacecraft_type_id))

    inherit_count = pinned |> Enum.map(& &1.count) |> Enum.sum()
    pinned_by_version = Map.new(pinned, &{&1.spacecraft_type_version, &1.count})

    %{
      profile: %{
        id: profile.spacecraft_type_id,
        name: profile.display_name,
        version: profile.version,
        # {id, number, label} as the profile list sends it (qa 11-18: the console requires the
        # number; {id} alone made the page unreadable for a profile with a catalog revision).
        catalog_revision:
          CatalogRollout.ref(profile.catalog_revision_id, Map.get(input, :revision_numbers, %{})),
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
      override_count: length(overrides),
      sections: sections(profile, overrides, Map.get(input, :catalog_choices)),
      applications: profile.applications || %{},
      rules: rules,
      overrides: overrides,
      # ux U79: each spacecraft's own extra routes, beside the field overrides.
      extra_routes: Map.get(input, :extra_routes, []),
      routing_model: if(rules == [], do: :per_spacecraft, else: :profile),
      # ux: "12 spacecraft on v5".
      versions:
        Enum.map(versions, fn version ->
          %{
            version: version.version,
            created_at: version.created_at,
            actor: nil,
            spacecraft_count: Map.get(pinned_by_version, version.version, 0)
          }
        end)
    }
  end

  defp sections(profile, overrides, catalog_choices) do
    counts = Enum.frequencies_by(overrides, &(&1.path |> to_string() |> String.replace("/", ".")))

    Enum.map(Schema.sections(), fn section ->
      %{
        key: section.key,
        label: section.label,
        fields:
          Enum.map(section.fields, fn field ->
            field
            |> with_choices(catalog_choices)
            |> Map.put(:value, Schema.value(profile, field.path))
            |> Map.put(:overridden_by, Map.get(counts, field.path, 0))
          end)
      }
    end)
  end

  # fe-setup: the catalog field offers the mission's catalog revisions, newest first, so the
  # form renders a select. Without any, the field keeps no enum.
  defp with_choices(%{path: "catalog_revision_id"} = field, [_ | _] = choices),
    do: Map.put(field, :enum, choices)

  defp with_choices(field, _choices), do: field

  defp catalog_choice(revision),
    do: %{value: revision.catalog_revision_id, label: catalog_label(revision)}

  # ux U25 / Profile.md P3 (611078ce): "rev 4 · imported 11-10", or "rev 4 · <source>" when the
  # import date isn't known. Never "rN": that's a change-set revision ("since r3" on the same row).
  @doc false
  @spec catalog_label(map()) :: binary()
  def catalog_label(%{revision_number: number} = revision) do
    case {revision.inserted_at, (revision.metadata || %{})["source_artifact_name"]} do
      {%{} = at, _source} -> "rev #{number} · imported " <> Calendar.strftime(at, "%m-%d")
      {nil, source} when is_binary(source) -> "rev #{number} · #{source}"
      {nil, nil} -> "rev #{number}"
    end
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
