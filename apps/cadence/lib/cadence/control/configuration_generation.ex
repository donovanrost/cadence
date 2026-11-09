defmodule Cadence.Control.ConfigurationGeneration do
  @moduledoc """
  Builds the runtime activation for a change-set apply in which the profile is the framing
  authority (DECISIONS #33/#35/#36, `docs/apogee/domain/framing-ingress.md`). Behind the
  per-mission flag `Cadence.Platform.ConfigurationSettings.profile_framing_generations?/2`.

  Runs **inside** the apply transaction: when it fails, nothing of the change set is applied.
  For the spacecraft the set touched that have an active fleet entry, it rebuilds their entry
  from effective profile framing, marked `framing_authority: "profile"`. Then it stores the
  fleet, creates the change-set activation request, and admits and records the activation
  (generation N+1) with publishing deferred. The caller publishes and converges the runtime
  after commit. v1 is framing only: the active binding set is reused, and catalog changes are
  refused before they get here.
  """

  alias Cadence.Activations
  alias Cadence.Applications.SpacecraftConfiguration.Active
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Missions
  alias Cadence.Platform.{ConfigurationSettings, ContentHash}
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.Overrides
  alias Cadence.SpacecraftType.Effective
  alias Cadence.SpacecraftTypeStore

  @framing_keys ~w(frame_size secondary_header_length ocf_length fecf)

  @type input :: %{
          set: map(),
          applier: map(),
          approvals: [map()],
          entries: [map()],
          revision: pos_integer()
        }

  @spec build(input()) :: {:ok, nil | map()} | {:error, term()}
  def build(%{set: set} = input) do
    touched = touched_spacecraft(input.entries)

    if touched != [] and
         ConfigurationSettings.profile_framing_generations?(set.organization_id, set.mission_id),
       do: build_for(input, touched),
       else: {:ok, nil}
  end

  defp build_for(%{set: set} = input, touched) do
    with {:ok, mission} <- Missions.fetch_mission(set.organization_id, set.mission_id),
         {:ok, %{activation: %{}, binding_set: binding_set} = active} <- Active.load(mission) do
      set.organization_id
      |> changed_entries(set.mission_id, touched, active.entries)
      |> activate_changed(input, active, binding_set)
    else
      {:ok, _no_active_activation} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp activate_changed(changed, _input, _active, _binding_set) when changed == %{},
    do: {:ok, nil}

  defp activate_changed(changed, input, active, binding_set),
    do: activate(input, active, binding_set, changed)

  defp activate(input, active, binding_set, changed) do
    mission_id = input.set.mission_id

    with {:ok, fleet} <- FleetSnapshot.store(mission_id, Map.merge(active.entries, changed)),
         metadata = metadata(fleet, input, changed),
         {:ok, request} <-
           ManagementActivations.request_from_change_set(%{
             binding_set: binding_set,
             requester: input.applier,
             metadata: metadata,
             approvals: input.approvals
           }),
         {:ok, activation} <-
           Activations.record_binding_set_activation(
             mission_id,
             binding_set.binding_set_id,
             binding_set.version,
             binding_set_content_sha256: ContentHash.term_sha256(binding_set),
             activation_request_id: request.activation_request_id,
             metadata: metadata,
             publish: false
           ) do
      {:ok,
       %{activation: activation, binding_set: binding_set, spacecraft_ids: Map.keys(changed)}}
    end
  end

  defp metadata(fleet, input, changed) do
    fleet
    |> FleetSnapshot.metadata(nil)
    |> Map.put("change_set", %{
      "id" => input.set.change_set_id,
      "revision" => input.revision,
      "spacecraft_ids" => changed |> Map.keys() |> Enum.sort()
    })
  end

  # Spacecraft whose effective profile config the set may have changed: pins moved (directly or
  # by a profile rollout) and overrides.
  defp touched_spacecraft(entries) do
    entries
    |> Enum.filter(&(&1.kind in ["spacecraft", "spacecraft_override"] and &1.op == :update))
    |> Enum.map(& &1.entity_id)
    |> Enum.uniq()
  end

  defp changed_entries(org, mission_id, ids, active_entries) do
    overrides = Overrides.list(org, mission_id, ids)
    {:ok, spacecraft} = SpacecraftStore.fetch_spacecrafts(org, mission_id, Enum.take(ids, 500))

    for {id, sc} <- spacecraft,
        entry = Map.get(active_entries, id),
        is_map(entry),
        {:ok, profile} <- [pinned_profile(org, mission_id, sc)],
        next = profile_framed(entry, Effective.resolve(profile, Map.get(overrides, id, %{}))),
        next != entry,
        into: %{} do
      {id, next}
    end
  end

  defp pinned_profile(_org, _mission_id, %{spacecraft_type_id: nil}), do: {:error, :no_profile}

  defp pinned_profile(org, mission_id, spacecraft) do
    SpacecraftTypeStore.fetch_spacecraft_type_version(
      org,
      mission_id,
      spacecraft.spacecraft_type_id,
      spacecraft.spacecraft_type_version
    )
  end

  defp profile_framed(entry, effective) do
    frame = effective["frame_parameters"] || %{}

    # Same shape and defaults as `ConfigurationInput.from_profile/1`, from effective values.
    protocol = %{
      "downlink" => effective["downlink_protocol"],
      "uplink" => effective["uplink_protocol"],
      "frame_size" => frame["frame_size"] || 1115,
      "secondary_header_length" => frame["secondary_header_length"] || 0,
      "insert_zone_length" => frame["insert_zone_length"] || 0,
      "ocf_length" => frame["ocf_length"] || 0,
      "truncated_primary_header" => frame["truncated_primary_header"] || false
    }

    entry
    |> put_in(["document", "protocol"], protocol)
    |> Map.put("framing", Map.take(frame, @framing_keys))
    |> Map.put("framing_authority", "profile")
  end
end
