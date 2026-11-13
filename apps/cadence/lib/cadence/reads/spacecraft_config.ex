defmodule Cadence.Reads.SpacecraftConfig do
  @moduledoc """
  Investigate's Configuration tab (ux Investigate.md, Tab · Configuration): "What is this
  spacecraft running, and what changed?" Read-only. Contract: docs/apogee/api/ops.md.

    * `spacecraft`, `profile`, `routing_rules`: as the Setup detail (`Reads.SpacecraftDetail`),
      plus `archived` and each rule's transport station.
    * `catalog`: the revision its active configuration runs vs the one its profile sets (#65).
    * `overrides`: this spacecraft's overrides of its profile, labelled from the profile schema.
    * `pending`: the mission's open or in-review change set, when it touches this spacecraft.
    * `recent_revisions`: the last 5 applied revisions with an entry for it.

  Callers authorize first.
  """

  alias Cadence.Applications.SpacecraftConfiguration.{CatalogAuthority, Drafts}
  alias Cadence.Comms.{StationRefs, TransportStore}
  alias Cadence.Configuration.{ChangeSetStore, Status}
  alias Cadence.Reads.{ConfigLabels, ProfileRouting, SpacecraftDetail}
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftType.Schema

  @recent 5
  @entity_kinds ~w(spacecraft spacecraft_override spacecraft_routes)

  @spec load(binary(), binary(), binary()) :: {:ok, map()} | {:error, :spacecraft_not_found}
  def load(org, mission, spacecraft_id) do
    with {:ok, detail} <- SpacecraftDetail.load(org, mission, spacecraft_id),
         {:ok, craft} <- SpacecraftStore.fetch_spacecraft(org, mission, spacecraft_id) do
      scope = %{organization_id: org, mission_id: mission}
      {:ok, profile} = SpacecraftStore.fetch_pinned_profile(scope, craft)

      {:ok,
       %{
         spacecraft: Map.put(detail.spacecraft, :archived, archived(craft)),
         profile: profile_facts(detail.profile, profile),
         catalog: catalog(scope, craft),
         overrides: overrides(org, mission, spacecraft_id, profile),
         routing_rules: routing_rules(org, mission, detail.routing_rules),
         pending: pending(mission, spacecraft_id, craft.spacecraft_type_id),
         recent_revisions: recent_revisions(org, mission, spacecraft_id)
       }}
    end
  end

  defp archived(%{lifecycle_state: :archived} = craft),
    do: %{at: craft.archived_at, by: actor(craft.archived_by)}

  defp archived(_craft), do: nil

  defp actor(%{} = actor) do
    %{
      kind: actor["kind"] || actor[:kind],
      id: actor["id"] || actor[:id],
      name: actor["name"] || actor[:name]
    }
  end

  defp actor(_none), do: nil

  # §11c parity (fe-ops G1 fact line): the pinned version's lifecycle and protocols.
  defp profile_facts(nil, _pinned), do: nil

  defp profile_facts(profile, nil),
    do: Map.merge(profile, %{lifecycle: nil, uplink_protocol: nil, packet_protocol: nil})

  defp profile_facts(profile, pinned),
    do:
      Map.merge(profile, %{
        lifecycle: text(pinned.lifecycle_state),
        uplink_protocol: text(pinned.uplink_protocol),
        packet_protocol: text(pinned.packet_protocol)
      })

  defp text(nil), do: nil
  defp text(value), do: to_string(value)

  # The catalog its active configuration runs, and the one its profile (with overrides) sets.
  defp catalog(scope, craft) do
    numbers =
      Map.new(
        Cadence.Catalog.list_revisions(scope.organization_id, scope.mission_id),
        &{&1.catalog_revision_id, &1.revision_number}
      )

    running =
      scope.organization_id
      |> Drafts.catalog_usage_entries(scope.mission_id)
      |> Enum.find_value(&(&1.spacecraft_id == craft.spacecraft_id && &1.catalog_revision_id))

    %{
      running: catalog_ref(running, numbers),
      profile: catalog_ref(CatalogAuthority.effective(scope, craft), numbers)
    }
  end

  defp catalog_ref(nil, _numbers), do: nil
  defp catalog_ref(id, numbers), do: %{id: id, revision_number: Map.get(numbers, id)}

  defp overrides(_org, _mission, _spacecraft_id, nil), do: []

  defp overrides(org, mission, spacecraft_id, profile) do
    fields = schema_fields()

    org
    |> ProfileRouting.overrides(mission, profile)
    |> Enum.filter(&(&1.spacecraft.id == spacecraft_id))
    |> Enum.map(fn override ->
      {section, field} = Map.get(fields, override.path, {section_label(override.path), nil})

      %{
        section: section,
        path: override.path,
        label: field && field.label,
        unit: field && Map.get(field, :unit),
        profile_value_json: json(override.profile_value),
        spacecraft_value_json: json(override.spacecraft_value),
        reason: override.reason,
        set_at: override.set_at,
        actor: actor(override.actor)
      }
    end)
  end

  # JSON text; nil (not set) stays null.
  defp json(nil), do: nil
  defp json(value), do: Jason.encode!(value)

  defp schema_fields do
    for section <- Schema.sections(), field <- section.fields, into: %{} do
      {field.path, {section.label, field}}
    end
  end

  defp section_label("routing." <> _rest), do: "Routing"
  defp section_label(_path), do: "Other"

  # The Setup rules, with the station each rule's transport reaches.
  defp routing_rules(org, mission, rules) do
    ids = rules |> Enum.map(& &1.transport.id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    transports =
      case TransportStore.fetch_transports(org, mission, ids) do
        {:ok, found} -> found
        _too_many -> %{}
      end

    stations = StationRefs.index(org, mission)

    Enum.map(rules, fn rule ->
      Map.put(rule, :station, station(Map.get(transports, rule.transport.id), stations))
    end)
  end

  defp station(%{ground_station_id: id}, stations) when is_binary(id) do
    resolved = StationRefs.resolve(id, stations)
    %{id: id, code: resolved.code, name: resolved.name}
  end

  defp station(_transport, _stations), do: nil

  # The mission's one open or in-review change set, when any of its changes touches this
  # spacecraft or its profile. Changes are `/config/change-sets/:id`'s, plus `via`.
  defp pending(mission, spacecraft_id, profile_id) do
    with %{change_set_id: id} <- ChangeSetStore.active(mission),
         {:ok, set} <- Status.change_set(mission, id),
         [_ | _] = changes <- touching(set.changes, spacecraft_id, profile_id) do
      [
        %{
          change_set_id: set.id,
          state: to_string(set.state),
          base_revision: set.base_revision,
          changes: changes
        }
      ]
    else
      _none -> []
    end
  end

  defp touching(changes, spacecraft_id, profile_id) do
    for change <- changes,
        via = Enum.find_value(change.ops, &via(&1, spacecraft_id, profile_id)),
        do: Map.put(change, :via, via)
  end

  defp via(%{kind: kind, entity_id: id}, spacecraft_id, profile_id) do
    case to_string(kind) do
      kind when kind in ["spacecraft", "spacecraft_override"] and id == spacecraft_id -> kind
      "spacecraft_profile" when id == profile_id and not is_nil(id) -> "spacecraft_profile"
      _other -> nil
    end
  end

  # `/config/revisions/:n`'s shape (labelled), with only this spacecraft's entries, plus `via`.
  defp recent_revisions(org, mission, spacecraft_id) do
    @entity_kinds
    |> Enum.flat_map(&Status.entity_history(mission, &1, spacecraft_id))
    |> Enum.map(& &1.revision)
    |> Enum.uniq()
    |> Enum.sort(:desc)
    |> Enum.take(@recent)
    |> Enum.flat_map(fn number ->
      case Status.get_revision(org, mission, number) do
        {:ok, revision} -> [own_entries(org, mission, revision, spacecraft_id)]
        _missing -> []
      end
    end)
  end

  defp own_entries(org, mission, revision, spacecraft_id) do
    entries =
      Enum.filter(
        revision.entries,
        &(to_string(&1.kind) in @entity_kinds and &1.entity_id == spacecraft_id)
      )

    org
    |> ConfigLabels.revision(mission, %{revision | entries: entries})
    |> Map.put(:via, entries |> Enum.map(&to_string(&1.kind)) |> Enum.uniq() |> Enum.sort())
  end
end
