defmodule Cadence.Activations.SpacecraftConfiguration do
  @moduledoc "Atomically admits an exact reviewed spacecraft revision before recording its activation."

  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Applications.SpacecraftConfiguration.Active, as: ConfigurationActive
  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Catalog.ChangeSetSpacecraft
  alias Cadence.Catalog.ConfigurationReviews
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput
  alias Cadence.Missions
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftTypeStore

  # A change-set generation (DECISIONS #35/#36): the change set already validated and wrote
  # the configuration in this same transaction. Admission checks the fleet it admits: every
  # spacecraft the set didn't change keeps exactly its active entry, and every changed one is
  # profile-framed, or hands profile framing back (unpinned) with nothing else changed.
  def admit(
        %{
          organization_id: org,
          metadata:
            %{
              "spacecraft_configuration_version" => 2,
              "change_set" => %{"id" => change_set_id}
            } = metadata
        } = attrs
      )
      when is_binary(org) and is_binary(change_set_id) do
    ConfigurationLock.run(org, attrs.mission_id, fn ->
      ids = ChangeSetSpacecraft.spacecraft_ids(org, attrs.mission_id, metadata)

      with true <- ids != [] and length(ids) == ChangeSetSpacecraft.count(metadata),
           {:ok, entries} <- FleetSnapshot.entries(metadata),
           {:ok, mission} <- Missions.fetch_mission(org, attrs.mission_id),
           {:ok, active} <- ConfigurationActive.load(mission),
           true <- Map.drop(entries, ids) == Map.drop(active.entries, ids),
           revisions = reviewed_revisions(org, attrs.mission_id, ids, entries),
           true <-
             Enum.all?(
               ids,
               &(framing_change?(entries[&1], active.entries[&1]) or
                   derived_configuration?(revisions, entries[&1], active.entries[&1]))
             ),
           true <-
             Enum.all?(ids, &catalog_settled?(revisions, entries[&1], active.entries[&1])) do
        {:ok, :admitted}
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :change_set_activation_stale}
      end
    end)
  end

  # Called inside the activation transaction, after the generation lock. Runtime
  # reconciliation and broadcasts happen only after this transaction commits.
  def admit(
        %{
          organization_id: org,
          metadata: %{"spacecraft_configuration_version" => 2} = metadata
        } = attrs
      )
      when is_binary(org) do
    ConfigurationLock.run(attrs.organization_id, attrs.mission_id, fn ->
      with {:ok, evidence} <-
             ConfigurationReviews.evidence(attrs.organization_id, attrs.mission_id, metadata),
           ids = evidence |> Map.keys() |> Enum.sort(),
           {:ok, entries} <- FleetSnapshot.entries(metadata),
           {:ok, mission} <- Missions.fetch_mission(attrs.organization_id, attrs.mission_id),
           {:ok, active} <- ConfigurationActive.load(mission),
           true <- Map.drop(entries, ids) == Map.drop(active.entries, ids) do
        admit_spacecraft(mission, ids, evidence, entries, active)
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :spacecraft_configuration_review_stale}
      end
    end)
  end

  def admit(%{metadata: metadata})
      when is_map_key(metadata, "spacecraft_configuration_version"),
      do: {:error, :invalid_spacecraft_model_bindings}

  # The historical internal activation API also serves unowned runtime binding
  # sets. Its caller resolves organization_id from the persisted mission first;
  # a registered mission always uses the scoped configuration guard below.
  # Spacecraft review metadata is rejected above for an unowned binding set.
  def admit(%{organization_id: nil}), do: {:ok, :legacy_unowned}

  def admit(attrs) do
    ConfigurationLock.run(attrs.organization_id, attrs.mission_id, fn ->
      case ConfigurationDrafts.legacy_apply_allowed(attrs.organization_id, attrs.mission_id) do
        :ok -> {:ok, :unscoped}
        error -> error
      end
    end)
  end

  # Admits a review of any number of spacecraft in a fixed number of queries (#1020): the rows are
  # locked in one statement, in id order, everything the checks compare is loaded in bulk, every
  # spacecraft is checked in memory in the same order and with the same first refusal as before, and
  # only when all pass is anything written (one update of the pins). One transaction, so a refusal
  # leaves nothing half-admitted.
  defp admit_spacecraft(mission, ids, evidence, entries, active) do
    %{organization_id: org, mission_id: mission_id} = mission

    with {:ok, locked} <- SpacecraftStore.lock_spacecraft(org, mission_id, ids) do
      latest = ConfigurationDrafts.latest_many(org, mission_id, ids)
      tokens = ConfigurationDrafts.tokens(mission, Enum.map(ids, &{locked[&1], latest[&1]}))
      sources = SourceEndpoints.list_source_endpoints_for_spacecrafts(org, mission_id, ids)

      context = %{
        evidence: evidence,
        entries: entries,
        active: active,
        locked: locked,
        latest: latest,
        tokens: tokens,
        sources: sources
      }

      with :ok <- check_all(ids, context),
           {:ok, pins} <- plan_pins(mission, ids, context) do
        SpacecraftStore.put_pins(org, mission_id, pins)
        {:ok, :admitted}
      end
    end
  end

  defp check_all(ids, context) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case check_current(id, context) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # One spacecraft's checks, in the order the per-spacecraft admission ran them.
  defp check_current(id, context) do
    %{evidence: evidence, entries: entries, active: active, tokens: tokens, latest: latest} =
      context

    row = latest[id]

    with %{
           "spacecraft_id" => ^id,
           "configuration_revision_id" => revision_id,
           "configuration_token" => token,
           "base_activation_id" => base
         } <- evidence[id],
         true <- base == (active.activation && active.activation.activation_id),
         :ok <- ConfigurationDrafts.exact_token(tokens[id], token),
         true <- row != nil and row.configuration_revision_id == revision_id,
         {:ok, entry} <- Map.fetch(entries, id),
         true <- entry["document"] == row.document,
         true <-
           entry["configuration_revision_id"] == revision_id and
             entry["configuration_version"] == row.version,
         {:ok, sources} <- source_ids(context.sources, id),
         true <- sources == entry["source_endpoint_ids"] do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :spacecraft_configuration_review_stale}
    end
  end

  # `ConfigurationActive.source_ids/2` over a bulk read: the spacecraft's endpoints, sorted, and the
  # same refusal above 100.
  defp source_ids(sources, id) do
    endpoints = Map.get(sources, id, [])

    if length(endpoints) <= 100,
      do: {:ok, endpoints |> Enum.map(& &1.source_endpoint_id) |> Enum.sort()},
      else: {:error, :spacecraft_source_limit_exceeded}
  end

  # What admitting does to each spacecraft's pin, decided in memory; the per-spacecraft profiles a
  # protocol needs are written first (one insert), then the pins (one update).
  defp plan_pins(mission, ids, context) do
    SpacecraftTypeStore.with_version_memo(fn ->
      plans = Enum.map(ids, &pin_plan(mission, context.locked[&1], context.latest[&1]))
      new_profiles = for {:new_profile, type, _spacecraft} <- plans, do: type

      with {:ok, stored} <-
             SpacecraftTypeStore.persist_spacecraft_types(mission.organization_id, new_profiles) do
        {:ok, Enum.map(plans, &resolve_pin(&1, stored))}
      end
    end)
  end

  defp resolve_pin({:pin, spacecraft}, _stored), do: pin(spacecraft)

  defp resolve_pin({:new_profile, type, spacecraft}, stored) do
    profile = Map.fetch!(stored, {type.spacecraft_type_id, type.version})

    pin(%{
      spacecraft
      | spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
    })
  end

  defp pin(spacecraft) do
    Map.take(spacecraft, [
      :spacecraft_id,
      :spacecraft_type_id,
      :spacecraft_type_version,
      :metadata
    ])
  end

  defp pin_plan(mission, spacecraft, row) do
    {:ok, pinned} = SpacecraftStore.fetch_pinned_profile(mission, spacecraft)
    protocol = row.document["protocol"]

    spacecraft = %{
      spacecraft
      | metadata:
          Map.put(
            spacecraft.metadata,
            "spacecraft_configuration_revision_id",
            row.configuration_revision_id
          )
    }

    cond do
      protocol == ConfigurationInput.from_profile(pinned) ->
        {:pin, spacecraft}

      is_nil(protocol) ->
        {:pin, %{spacecraft | spacecraft_type_id: nil, spacecraft_type_version: nil}}

      true ->
        {:new_profile,
         SpacecraftType.new(%{
           spacecraft_type_id:
             "spacecraft_configuration_profile_#{row.configuration_revision_id}",
           mission_id: mission.mission_id,
           version: 1,
           display_name: "#{spacecraft.display_name} communications · r#{row.version}",
           downlink_protocol: protocol["downlink"],
           uplink_protocol: protocol["uplink"],
           frame_parameters: Map.drop(protocol, ["downlink", "uplink"]),
           metadata: %{
             "spacecraft_configuration_revision_id" => row.configuration_revision_id,
             "spacecraft_id" => spacecraft.spacecraft_id
           }
         }), spacecraft}
    end
  end

  @framing_fields ["framing", "framing_authority"]

  # The revision rows the change set's entries name, and each one's spacecraft's latest, in two
  # queries for the whole set (they were two per spacecraft).
  defp reviewed_revisions(org, mission_id, ids, entries) do
    rows =
      ids
      |> Enum.map(&get_in(entries, [&1, "configuration_revision_id"]))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> then(&ConfigurationDrafts.fetch_many(org, mission_id, &1))

    latest =
      ConfigurationDrafts.latest_many(
        org,
        mission_id,
        rows |> Map.values() |> Enum.map(& &1.spacecraft_id) |> Enum.uniq()
      )

    %{rows: rows, latest: latest}
  end

  # DECISIONS #65: an entry that moves the catalog must be exactly the spacecraft's latest
  # configuration (the one the change set derived), with that catalog.
  defp catalog_settled?(_revisions, %{"catalog_revision_id" => same}, %{
         "catalog_revision_id" => same
       }),
       do: true

  defp catalog_settled?(revisions, %{"configuration_revision_id" => id} = entry, _active)
       when is_binary(id) do
    case revisions.rows do
      %{^id => row} ->
        latest = revisions.latest[row.spacecraft_id]

        latest != nil and latest.configuration_revision_id == id and
          row.catalog_revision_id == entry["catalog_revision_id"]

      _missing ->
        false
    end
  end

  defp catalog_settled?(_revisions, _entry, _active), do: false

  # L22: a switch change on a spacecraft without profile framing. Its entry runs the
  # configuration the change set derived in this transaction (the spacecraft's latest), with
  # framing and protocol exactly as active.
  defp derived_configuration?(revisions, %{"configuration_revision_id" => id} = entry, active)
       when is_binary(id) and is_map(active) do
    case revisions.rows do
      %{^id => row} ->
        latest = revisions.latest[row.spacecraft_id]

        latest != nil and latest.configuration_revision_id == id and
          id != active["configuration_revision_id"] and
          Map.take(entry, @framing_fields) == Map.take(active, @framing_fields) and
          get_in(entry, ["document", "protocol"]) == get_in(active, ["document", "protocol"])

      _missing ->
        false
    end
  end

  defp derived_configuration?(_revisions, _entry, _active), do: false

  defp framing_change?(%{"framing_authority" => "profile"}, _active), do: true

  defp framing_change?(%{} = entry, %{"framing_authority" => "profile"} = active),
    do: without_framing(entry) == without_framing(active)

  defp framing_change?(_entry, _active), do: false

  defp without_framing(entry) do
    entry
    |> Map.drop(@framing_fields)
    |> Map.update("document", %{}, &Map.delete(&1, "protocol"))
  end
end
