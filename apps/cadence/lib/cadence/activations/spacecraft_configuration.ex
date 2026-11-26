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
           true <-
             Enum.all?(
               ids,
               &(framing_change?(entries[&1], active.entries[&1]) or
                   derived_configuration?(org, attrs.mission_id, entries[&1], active.entries[&1]))
             ),
           true <-
             Enum.all?(
               ids,
               &catalog_settled?(org, attrs.mission_id, entries[&1], active.entries[&1])
             ) do
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
        admit_spacecraft(mission, ids, evidence, metadata, active)
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

  defp admit_spacecraft(mission, ids, evidence, metadata, active) do
    Enum.reduce_while(ids, {:ok, :admitted}, fn id, _result ->
      result =
        SpacecraftStore.with_locked_spacecraft(
          mission.organization_id,
          mission.mission_id,
          id,
          &admit_current(mission, &1, evidence, metadata, active)
        )

      case result do
        {:ok, :admitted} -> {:cont, result}
        error -> {:halt, error}
      end
    end)
  end

  defp admit_current(mission, spacecraft, evidence, metadata, active) do
    with %{
           "spacecraft_id" => id,
           "configuration_revision_id" => revision_id,
           "configuration_token" => token,
           "base_activation_id" => base
         } <- evidence[spacecraft.spacecraft_id],
         true <- id == spacecraft.spacecraft_id,
         true <- base == (active.activation && active.activation.activation_id),
         current = ConfigurationDrafts.snapshot(mission, spacecraft),
         :ok <- ConfigurationDrafts.exact_token(current.token, token),
         true <- current.row != nil and current.row.configuration_revision_id == revision_id,
         {:ok, entry} <- reviewed_entry(metadata, id),
         true <- entry["document"] == current.row.document,
         true <-
           entry["configuration_revision_id"] == revision_id and
             entry["configuration_version"] == current.row.version,
         {:ok, sources} <- ConfigurationActive.source_ids(mission, id),
         true <- sources == entry["source_endpoint_ids"],
         :ok <- apply_protocol(mission, spacecraft, current.row) do
      {:ok, :admitted}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :spacecraft_configuration_review_stale}
    end
  end

  defp reviewed_entry(metadata, id) do
    case FleetSnapshot.entry(metadata, id) do
      {:ok, entry} -> {:ok, entry}
      {:error, _} -> {:error, :spacecraft_configuration_review_stale}
    end
  end

  defp apply_protocol(mission, spacecraft, row) do
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
        update_pin(mission, spacecraft)

      is_nil(protocol) ->
        update_pin(mission, %{spacecraft | spacecraft_type_id: nil, spacecraft_type_version: nil})

      true ->
        with {:ok, profile} <-
               SpacecraftTypeStore.persist_spacecraft_type(
                 mission.organization_id,
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
                 })
               ) do
          update_pin(mission, %{
            spacecraft
            | spacecraft_type_id: profile.spacecraft_type_id,
              spacecraft_type_version: profile.version
          })
        end
    end
  end

  defp update_pin(mission, spacecraft) do
    case SpacecraftStore.update_spacecraft(mission.organization_id, spacecraft) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @framing_fields ["framing", "framing_authority"]

  # DECISIONS #65: an entry that moves the catalog must be exactly the spacecraft's latest
  # configuration (the one the change set derived), with that catalog.
  defp catalog_settled?(_org, _mission_id, %{"catalog_revision_id" => same}, %{
         "catalog_revision_id" => same
       }),
       do: true

  defp catalog_settled?(org, mission_id, %{"configuration_revision_id" => id} = entry, _active)
       when is_binary(id) do
    case ConfigurationDrafts.fetch(org, mission_id, id) do
      {:ok, row} ->
        latest = ConfigurationDrafts.latest(org, mission_id, row.spacecraft_id)

        latest != nil and latest.configuration_revision_id == id and
          row.catalog_revision_id == entry["catalog_revision_id"]

      _missing ->
        false
    end
  end

  defp catalog_settled?(_org, _mission_id, _entry, _active), do: false

  # L22: a switch change on a spacecraft without profile framing. Its entry runs the
  # configuration the change set derived in this transaction (the spacecraft's latest), with
  # framing and protocol exactly as active.
  defp derived_configuration?(
         org,
         mission_id,
         %{"configuration_revision_id" => id} = entry,
         active
       )
       when is_binary(id) and is_map(active) do
    case ConfigurationDrafts.fetch(org, mission_id, id) do
      {:ok, row} ->
        latest = ConfigurationDrafts.latest(org, mission_id, row.spacecraft_id)

        latest != nil and latest.configuration_revision_id == id and
          id != active["configuration_revision_id"] and
          Map.take(entry, @framing_fields) == Map.take(active, @framing_fields) and
          get_in(entry, ["document", "protocol"]) == get_in(active, ["document", "protocol"])

      _missing ->
        false
    end
  end

  defp derived_configuration?(_org, _mission_id, _entry, _active), do: false

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
