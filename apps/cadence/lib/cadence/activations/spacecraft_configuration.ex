defmodule Cadence.Activations.SpacecraftConfiguration do
  @moduledoc "Atomically admits an exact reviewed spacecraft revision before recording its activation."

  alias Cadence.Applications.ConfigurationLock
  alias Cadence.Applications.SpacecraftConfiguration.Active, as: ConfigurationActive
  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput
  alias Cadence.Missions
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftTypeStore

  # Called inside the activation transaction, after the generation lock. Runtime
  # reconciliation and broadcasts happen only after this transaction commits.
  def admit(
        %{organization_id: org, metadata: %{"spacecraft_configuration_version" => 1} = metadata} =
          attrs
      )
      when is_binary(org) do
    ConfigurationLock.run(attrs.organization_id, attrs.mission_id, fn ->
      with %{
             "spacecraft_id" => id,
             "configuration_revision_id" => _revision_id,
             "configuration_token" => _token,
             "base_activation_id" => _base
           } <- metadata["configuration_review"],
           {:ok, mission} <- Missions.fetch_mission(attrs.organization_id, attrs.mission_id) do
        SpacecraftStore.with_locked_spacecraft(
          org,
          attrs.mission_id,
          id,
          &admit_current(mission, &1, metadata)
        )
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, :spacecraft_configuration_review_stale}
      end
    end)
  end

  def admit(%{metadata: metadata})
      when is_map_key(metadata, "spacecraft_configurations") or
             is_map_key(metadata, "spacecraft_configuration_version"),
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

  defp admit_current(mission, spacecraft, metadata) do
    %{
      "spacecraft_id" => id,
      "configuration_revision_id" => revision_id,
      "configuration_token" => token,
      "base_activation_id" => base
    } = metadata["configuration_review"]

    with {:ok, active} <- ConfigurationActive.load(mission),
         true <- base == (active.activation && active.activation.activation_id),
         current = ConfigurationDrafts.snapshot(mission, spacecraft),
         :ok <- ConfigurationDrafts.exact_token(current.token, token),
         true <- current.row != nil and current.row.configuration_revision_id == revision_id,
         entry when is_map(entry) <- metadata["spacecraft_configurations"][id],
         true <- entry["document"] == current.row.document,
         true <-
           entry["configuration_revision_id"] == revision_id and
             entry["configuration_version"] == current.row.version,
         {:ok, sources} <- ConfigurationActive.source_ids(mission, id),
         true <- sources == entry["source_endpoint_ids"],
         true <-
           Map.delete(metadata["spacecraft_configurations"], id) == Map.delete(active.entries, id),
         :ok <- apply_protocol(mission, spacecraft, current.row) do
      {:ok, :admitted}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :spacecraft_configuration_review_stale}
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
end
