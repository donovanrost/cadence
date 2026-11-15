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
  - **Switches** (L22): a spacecraft whose commanding or telemetry switch the set changed gets
    a derived configuration with it (with a new catalog in the same revision). Turning
    commanding off cancels its waiting commands (`commanding_disabled`) and refuses while one is
    being sent; turning telemetry on needs packet inputs (`ConfigurationSwitches`).
  - **Framing** (#33/#45): entries are rebuilt from effective profile framing, marked
    `framing_authority: "profile"`.

  Then it stores the fleet, creates the change-set activation request, and admits and records
  the activation (generation N+1) with publishing deferred. The caller publishes and converges
  the runtime after commit.
  """

  alias Cadence.Activations
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.SpacecraftConfiguration.{Active, CatalogAuthority, Drafts, Review}
  alias Cadence.Catalog
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Commanding.{Cancellation, RequestActivity}
  alias Cadence.Control.{ConfigurationApids, ConfigurationSwitches}
  alias Cadence.Governance
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModels.CatalogApids
  alias Cadence.Missions
  alias Cadence.Platform.ConfigurationSettings
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
         switches = switch_targets(mission, touched, active.entries),
         commanding_off = ConfigurationSwitches.commanding_off(switches),
         :ok <- nothing_in_flight(org, set.mission_id, Map.keys(targets)),
         :ok <- nothing_in_flight(org, set.mission_id, commanding_off, :commanding),
         :ok <- telemetry_inputs(switches, active.entries),
         apids = apid_changes(mission, touched, active.entries),
         :ok <- apids_defined(apids),
         derivations = derivations(targets, switches, ConfigurationApids.derivations(apids)),
         {:ok, items} <- derive_configurations(mission, active.entries, derivations, input),
         {:ok, binding_set} <- next_binding_set(mission, active, items) do
      base = Map.merge(active.entries, Map.new(items, &{&1.id, &1.entry}))

      org
      |> changed_entries(set.mission_id, touched, base, active.entries)
      |> activate_changed(input, active, binding_set, %{
        catalog_changed: Map.keys(targets),
        commanding_disabled: commanding_off
      })
    else
      {:ok, _no_active_activation} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp activate_changed(changed, _input, _active, _binding_set, _catalog_ids)
       when changed == %{},
       do: {:ok, nil}

  # Commands not yet released on a spacecraft whose catalog changes (#65) or whose commanding is
  # turned off (L22) are canceled with the apply, each with its reason.
  defp activate_changed(changed, input, active, binding_set, cancel) do
    with {:ok, by_catalog} <- cancel_waiting(input, cancel.catalog_changed, "catalog_changed"),
         {:ok, by_switch} <-
           cancel_waiting(
             input,
             cancel.commanding_disabled -- cancel.catalog_changed,
             "commanding_disabled"
           ),
         {:ok, result} <- activate(input, active, binding_set, changed) do
      {:ok, Map.put(result, :canceled_request_ids, by_catalog ++ by_switch)}
    end
  end

  ## Switches (L22)

  defp switch_targets(mission, ids, entries) do
    ids = Enum.filter(ids, &Map.has_key?(entries, &1))

    {:ok, spacecraft} =
      SpacecraftStore.fetch_spacecrafts_in_batches(
        mission.organization_id,
        mission.mission_id,
        ids
      )

    ConfigurationSwitches.targets(spacecraft, entries)
  end

  # Telemetry turned on decodes what the configuration names; without packet inputs there's
  # nothing to decode, so the apply refuses (the preview shows it as a blocking HOLD).
  defp telemetry_inputs(switches, entries) do
    case Enum.reject(
           ConfigurationSwitches.telemetry_on(switches),
           &ConfigurationSwitches.packet_inputs?(entries[&1])
         ) do
      [] -> :ok
      ids -> {:error, {:telemetry_packet_inputs_required, ids}}
    end
  end

  # One derived configuration per spacecraft, with its new catalog, switches and APIDs together.
  defp derivations(targets, switches, apids) do
    targets
    |> Map.new(fn {id, to} -> {id, %{"catalog_revision_id" => to}} end)
    |> Map.merge(switches, fn _id, left, right -> Map.merge(left, right) end)
    |> Map.merge(apids, fn _id, left, right -> Map.merge(left, right) end)
  end

  ## Handled APIDs (L22)

  @doc """
  What an apply would change in these spacecraft's decoded APIDs (the L22 HOLDs):
  `%{changes: %{id => %{from, to, stray}}, names: %{id => name}, labels: %{catalog => "rev N"},
  catalogs: %{id => catalog}}`.
  """
  @spec apid_impact(String.t(), String.t(), [String.t()]) :: map()
  def apid_impact(organization_id, mission_id, ids) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, %{activation: %{}} = active} <- Active.load(mission) do
      {effective, changes} = apid_state(mission, ids, active.entries)

      {:ok, spacecraft} =
        SpacecraftStore.fetch_spacecrafts_in_batches(
          organization_id,
          mission_id,
          Map.keys(changes)
        )

      catalogs =
        Map.new(changes, fn {id, _change} -> {id, effective[id]["catalog_revision_id"]} end)

      %{
        changes: changes,
        names: Map.new(spacecraft, fn {id, sc} -> {id, sc.display_name} end),
        catalogs: catalogs,
        labels:
          revision_labels(
            organization_id,
            mission_id,
            Map.new(catalogs, fn {id, catalog} -> {id, %{from: nil, to: catalog}} end)
          )
      }
    else
      _no_active_activation -> %{changes: %{}, names: %{}, catalogs: %{}, labels: %{}}
    end
  end

  defp apid_changes(mission, ids, entries), do: mission |> apid_state(ids, entries) |> elem(1)

  # Effective catalog and handled APIDs for spacecraft whose profile sets their catalog (#65).
  defp apid_state(mission, ids, entries) do
    ids = Enum.filter(ids, &Map.has_key?(entries, &1))
    org = mission.organization_id
    overrides = Overrides.list(org, mission.mission_id, ids)
    {:ok, spacecraft} = SpacecraftStore.fetch_spacecrafts_in_batches(org, mission.mission_id, ids)

    effective =
      for {id, sc} <- spacecraft,
          {:ok, profile} <- [pinned_profile(org, mission.mission_id, sc)],
          values = Effective.resolve(profile, Map.get(overrides, id, %{})),
          is_binary(values["catalog_revision_id"]),
          into: %{},
          do: {id, Map.take(values, ["catalog_revision_id", "handled_apids"])}

    catalog_apids =
      effective
      |> Map.values()
      |> Enum.map(& &1["catalog_revision_id"])
      |> Enum.uniq()
      |> Map.new(fn catalog ->
        case CatalogApids.apids(org, mission.mission_id, catalog) do
          {:ok, apids} -> {catalog, apids}
          {:error, _reason} -> {catalog, []}
        end
      end)

    {effective, ConfigurationApids.changes(effective, entries, catalog_apids)}
  end

  # A list naming APIDs the catalog doesn't define refuses the apply (a blocking HOLD).
  defp apids_defined(changes) do
    case for({id, %{stray: [_ | _]}} <- changes, do: id) do
      [] -> :ok
      ids -> {:error, {:handled_apids_not_in_catalog, ids}}
    end
  end

  @doc "What an apply would do to these spacecraft's switches (L22 HOLDs)."
  defdelegate switch_impact(organization_id, mission_id, ids),
    to: ConfigurationSwitches,
    as: :impact

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
      latest = Drafts.latest_many(org, mission_id, ids)
      Enum.filter(ids, &newer_configuration?(Map.get(latest, &1), active.entries[&1]))
    else
      _no_active_activation -> []
    end
  end

  defp newer_configuration?(nil, _entry), do: false

  defp newer_configuration?(latest, entry),
    do: latest.configuration_revision_id != (entry || %{})["configuration_revision_id"]

  defp catalog_targets(mission, ids, entries) do
    ids = Enum.filter(ids, &Map.has_key?(entries, &1))

    {:ok, spacecraft} =
      SpacecraftStore.fetch_spacecrafts_in_batches(
        mission.organization_id,
        mission.mission_id,
        ids
      )

    effective = CatalogAuthority.effective_many(mission, Map.new(spacecraft))

    for {id, to} <- effective,
        to != nil and to != entries[id]["catalog_revision_id"],
        into: %{},
        do: {id, to}
  end

  # #65: a spacecraft releasing or radiating a command right now keeps its catalog until that
  # finishes (the preview shows it as a blocking HOLD; this guards the race).
  defp nothing_in_flight(org, mission_id, ids, why \\ :catalog)

  defp nothing_in_flight(_org, _mission_id, [], _why), do: :ok

  defp nothing_in_flight(org, mission_id, ids, why) do
    case RequestActivity.in_flight(org, mission_id, endpoints(org, mission_id, ids)) do
      [] ->
        :ok

      requests ->
        reason =
          if why == :commanding,
            do: :commanding_command_in_flight,
            else: :catalog_command_in_flight

        {:error, {reason, Enum.map(requests, & &1.command_request_id)}}
    end
  end

  # One compile input per distinct catalog, passed to every spacecraft on it (Review.
  # cached_inputs/3): step 4 (11-15) read and decoded it once per spacecraft, 499 times.
  defp derive_configurations(mission, entries, derivations, %{applier: applier}) do
    derivations
    |> Enum.reduce_while({:ok, [], [], %{}}, fn {id, changes}, {:ok, items, rows, cache} ->
      with running when is_binary(running) <-
             entries[id]["configuration_revision_id"] ||
               {:error, :spacecraft_configuration_required},
           {:ok, row} <-
             Drafts.derive(
               mission.organization_id,
               mission.mission_id,
               running,
               changes,
               applier["id"]
             ),
           {:ok, inputs, cache} <- Review.cached_inputs(cache, mission, row.catalog_revision_id),
           {:ok, item} <- Review.compile(mission, id, row, inputs) do
        {:cont, {:ok, [item | items], [row | rows], cache}}
      else
        {:error, reason} -> {:halt, {:error, {reason, id}}}
      end
    end)
    |> case do
      {:ok, items, rows, _cache} -> restamped(mission, items, rows)
      {:error, reason} -> {:error, reason}
    end
  end

  # derive/5 projected each spacecraft's stored decom config, so their bases moved (11-15 drift fix).
  defp restamped(mission, items, rows) do
    :ok = Drafts.restamp_bases(mission, rows)
    {:ok, items}
  end

  defp next_binding_set(_mission, active, []), do: {:ok, active.binding_set}

  # Hashed and applied as it reads back, like Control.Activations: the in-memory build carries
  # packet field ids the store doesn't keep, so its hash could never re-admit after a restart
  # (2026-11-12, catalog-generations.md).
  defp next_binding_set(mission, active, items) do
    with {:ok, persisted} <-
           Governance.persist_binding_set(
             mission.organization_id,
             Review.binding_set(mission, active, items)
           ) do
      Governance.fetch_binding_set(
        mission.organization_id,
        mission.mission_id,
        persisted.binding_set_id,
        persisted.version
      )
    end
  end

  # #65: commands not yet released on a spacecraft whose catalog changes are canceled with the
  # apply, so they don't fail closed at release (mid-pass) or trip stop-on-failure.
  defp cancel_waiting(_input, [], _reason), do: {:ok, []}

  defp cancel_waiting(%{set: set}, ids, reason) do
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
        reason <> ": " <> set.change_set_id,
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
             binding_set_content_sha256: BindingSet.content_sha256(binding_set),
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
    {:ok, spacecraft} = SpacecraftStore.fetch_spacecrafts_in_batches(org, mission_id, ids)

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
