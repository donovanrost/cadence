defmodule Cadence.Control.ConfigurationGeneration do
  @moduledoc """
  Builds the runtime activation for a change-set apply (DECISIONS #33/#35/#36/#65,
  `docs/apogee/domain/framing-ingress.md`, `catalog-generations.md`). Behind the per-mission flag
  `Cadence.Platform.ConfigurationSettings.profile_framing_generations?/2`.

  Runs **inside** the apply transaction: when it fails, nothing of the change set is applied.
  For the spacecraft the set touched that have an active fleet entry:

  - **Catalog** (#36/#65): a spacecraft whose profile (with overrides) now names another catalog
    gets a derived configuration revision with that catalog, compiled by the per-spacecraft
    review's builder (`Review.compile/3`), and the binding set is rebuilt with its new
    telemetry contribution. Commands not yet released on it are canceled
    (`catalog_changed`); one releasing or radiating refuses the apply.
  - **Framing** (#33/#45): entries are rebuilt from effective profile framing, marked
    `framing_authority: "profile"`.

  Then it stores the fleet, creates the change-set activation request, and admits and records
  the activation (generation N+1) with publishing deferred. The caller publishes and converges
  the runtime after commit.
  """

  alias Cadence.Activations
  alias Cadence.Applications.SpacecraftConfiguration.{Active, CatalogAuthority, Drafts, Review}
  alias Cadence.Catalog
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Commanding.{Cancellation, RequestActivity}
  alias Cadence.Governance
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Missions
  alias Cadence.Platform.{ConfigurationSettings, ContentHash}
  alias Cadence.SourceEndpoints
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

  @doc """
  The spacecraft among `ids` whose runtime framing an apply would change: those with an active
  fleet entry that differs from their effective profile framing. The framing compatibility HOLD
  checks exactly these, so it fires only when a generation would follow (DECISIONS #45).
  """
  @spec changed_spacecraft(String.t(), String.t(), [String.t()]) :: [String.t()]
  def changed_spacecraft(_organization_id, _mission_id, []), do: []

  def changed_spacecraft(organization_id, mission_id, ids) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, %{activation: %{}} = active} <- Active.load(mission) do
      organization_id
      |> changed_entries(mission_id, ids, active.entries, active.entries)
      |> Map.keys()
    else
      _no_active_activation -> []
    end
  end

  defp build_for(%{set: set} = input, touched) do
    org = set.organization_id

    with {:ok, mission} <- Missions.fetch_mission(org, set.mission_id),
         {:ok, %{activation: %{}} = active} <- Active.load(mission),
         targets = catalog_targets(mission, touched, active.entries),
         :ok <- nothing_in_flight(org, set.mission_id, Map.keys(targets)),
         {:ok, items} <- derive_catalogs(mission, active.entries, targets, input.applier),
         {:ok, binding_set} <- next_binding_set(mission, active, items) do
      base = Map.merge(active.entries, Map.new(items, &{&1.id, &1.entry}))

      org
      |> changed_entries(set.mission_id, touched, base, active.entries)
      |> activate_changed(input, active, binding_set, Map.keys(targets))
    else
      {:ok, _no_active_activation} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp activate_changed(changed, _input, _active, _binding_set, _catalog_ids)
       when changed == %{},
       do: {:ok, nil}

  defp activate_changed(changed, input, active, binding_set, catalog_ids) do
    with {:ok, canceled} <- cancel_waiting(input, catalog_ids),
         {:ok, result} <- activate(input, active, binding_set, changed) do
      {:ok, Map.put(result, :canceled_request_ids, canceled)}
    end
  end

  ## Catalog-path generations (DECISIONS #36/#65)

  @doc """
  The spacecraft among `ids` whose catalog an apply would change: those with an active fleet
  entry whose catalog differs from the one their profile (with overrides) sets.
  `%{spacecraft_id => %{from, to}}`.
  """
  @spec catalog_changes(String.t(), String.t(), [String.t()]) :: map()
  def catalog_changes(_organization_id, _mission_id, []), do: %{}

  def catalog_changes(organization_id, mission_id, ids) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, %{activation: %{}} = active} <- Active.load(mission) do
      mission
      |> catalog_targets(ids, active.entries)
      |> Map.new(fn {id, to} ->
        {id, %{from: active.entries[id]["catalog_revision_id"], to: to}}
      end)
    else
      _no_active_activation -> %{}
    end
  end

  @doc """
  What applying a catalog change to `ids` would do (the catalog compatibility HOLDs, #65):
  `%{changes: %{id => %{from, to}}, waiting: [request], in_flight: [request], pending: [id]}`.
  `pending` are spacecraft with a newer configuration that isn't active yet.
  """
  @spec catalog_impact(String.t(), String.t(), [String.t()]) :: map()
  def catalog_impact(organization_id, mission_id, ids) do
    changes = catalog_changes(organization_id, mission_id, ids)
    changed = Map.keys(changes)
    endpoints = endpoints(organization_id, mission_id, changed)

    %{
      changes: changes,
      labels: revision_labels(organization_id, mission_id, changes),
      waiting: RequestActivity.waiting(organization_id, mission_id, endpoints),
      in_flight: RequestActivity.in_flight(organization_id, mission_id, endpoints),
      pending: pending_configuration(organization_id, mission_id, changed)
    }
  end

  # "rev N" for each catalog revision a change names, as the catalog pages name them.
  defp revision_labels(org, mission_id, changes) do
    changes
    |> Map.values()
    |> Enum.flat_map(&[&1.from, &1.to])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(fn id ->
      case Catalog.fetch_revision(org, mission_id, id) do
        {:ok, %{revision_number: number}} when is_integer(number) -> {id, "rev #{number}"}
        _missing -> {id, id}
      end
    end)
  end

  defp pending_configuration(_org, _mission_id, []), do: []

  defp pending_configuration(org, mission_id, ids) do
    with {:ok, mission} <- Missions.fetch_mission(org, mission_id),
         {:ok, %{activation: %{}} = active} <- Active.load(mission) do
      Enum.filter(ids, fn id ->
        latest = Drafts.latest(org, mission_id, id)

        latest != nil and
          latest.configuration_revision_id != active.entries[id]["configuration_revision_id"]
      end)
    else
      _no_active_activation -> []
    end
  end

  defp catalog_targets(mission, ids, entries) do
    ids = Enum.filter(ids, &Map.has_key?(entries, &1))

    {:ok, spacecraft} =
      SpacecraftStore.fetch_spacecrafts(
        mission.organization_id,
        mission.mission_id,
        Enum.take(ids, 500)
      )

    for {id, sc} <- spacecraft,
        to = CatalogAuthority.effective(mission, sc),
        to != nil and to != entries[id]["catalog_revision_id"],
        into: %{},
        do: {id, to}
  end

  # #65: a spacecraft releasing or radiating a command right now keeps its catalog until that
  # finishes (the preview shows it as a blocking HOLD; this guards the race).
  defp nothing_in_flight(_org, _mission_id, []), do: :ok

  defp nothing_in_flight(org, mission_id, ids) do
    case RequestActivity.in_flight(org, mission_id, endpoints(org, mission_id, ids)) do
      [] ->
        :ok

      requests ->
        {:error, {:catalog_command_in_flight, Enum.map(requests, & &1.command_request_id)}}
    end
  end

  defp derive_catalogs(mission, entries, targets, applier) do
    Enum.reduce_while(targets, {:ok, []}, fn {id, to}, {:ok, items} ->
      with running when is_binary(running) <-
             entries[id]["configuration_revision_id"] ||
               {:error, :spacecraft_configuration_required},
           {:ok, row} <-
             Drafts.derive_catalog(
               mission.organization_id,
               mission.mission_id,
               running,
               to,
               applier["id"]
             ),
           {:ok, item} <- Review.compile(mission, id, row) do
        {:cont, {:ok, [item | items]}}
      else
        {:error, reason} -> {:halt, {:error, {reason, id}}}
      end
    end)
  end

  defp next_binding_set(_mission, active, []), do: {:ok, active.binding_set}

  defp next_binding_set(mission, active, items) do
    mission
    |> Review.binding_set(active, items)
    |> then(&Governance.persist_binding_set(mission.organization_id, &1))
  end

  # #65: commands not yet released on a spacecraft whose catalog changes are canceled with the
  # apply, so they don't fail closed at release (mid-pass) or trip stop-on-failure.
  defp cancel_waiting(_input, []), do: {:ok, []}

  defp cancel_waiting(%{set: set}, ids) do
    org = set.organization_id

    waiting =
      org
      |> RequestActivity.waiting(set.mission_id, endpoints(org, set.mission_id, ids))
      |> Enum.map(& &1.command_request_id)

    outcome =
      Cancellation.cancel(
        org,
        set.mission_id,
        waiting,
        "catalog_changed: " <> set.change_set_id,
        %{
          "actor_kind" => "system",
          "id" => "change_set:" <> set.change_set_id
        }
      )

    {:ok, outcome.canceled}
  end

  defp endpoints(org, mission_id, ids) do
    wanted = MapSet.new(ids)

    org
    |> SourceEndpoints.list_source_endpoints(mission_id)
    |> Enum.filter(&MapSet.member?(wanted, &1.spacecraft_id))
    |> Enum.map(& &1.source_endpoint_id)
  end

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

  # Entries are rebuilt from `base` (the active ones, with new catalogs compiled in) and kept
  # when they differ from what's active.
  defp changed_entries(org, mission_id, ids, base, active_entries) do
    overrides = Overrides.list(org, mission_id, ids)
    {:ok, spacecraft} = SpacecraftStore.fetch_spacecrafts(org, mission_id, Enum.take(ids, 500))

    for {id, sc} <- spacecraft,
        entry = Map.get(base, id),
        is_map(entry),
        next = next_entry(org, mission_id, sc, entry, Map.get(overrides, id, %{})),
        is_map(next) and next != Map.get(active_entries, id),
        into: %{} do
      {id, next}
    end
  end

  defp next_entry(org, mission_id, spacecraft, entry, overrides) do
    case pinned_profile(org, mission_id, spacecraft) do
      {:ok, profile} -> profile_framed(entry, Effective.resolve(profile, overrides))
      {:error, _no_profile} -> unprofiled(org, mission_id, entry)
    end
  end

  # Unpinning a profile-framed spacecraft (or a rollback undoing its pin) hands framing back:
  # the profile marks are dropped so the runtime uses transport framing again, and the protocol
  # returns to the spacecraft's own configuration when it has one. Entries that were never
  # profile-framed are left alone.
  defp unprofiled(org, mission_id, %{"framing_authority" => "profile"} = entry) do
    entry
    |> Map.drop(["framing", "framing_authority"])
    |> restore_protocol(org, mission_id)
  end

  defp unprofiled(_org, _mission_id, entry), do: entry

  defp restore_protocol(%{"configuration_revision_id" => id} = entry, org, mission_id)
       when is_binary(id) do
    # Exactly as the configuration has it, including an explicit nil protocol.
    case Drafts.fetch(org, mission_id, id) do
      {:ok, %{document: %{} = document}} ->
        put_in(entry, ["document", "protocol"], Map.get(document, "protocol"))

      _configuration_missing ->
        entry
    end
  end

  defp restore_protocol(entry, _org, _mission_id), do: entry

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
