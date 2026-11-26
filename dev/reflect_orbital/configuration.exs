defmodule Cadence.Dev.ReflectOrbital.Configuration do
  @moduledoc "Imports and assigns the demo command and telemetry database to the Earendil fleet."
  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Catalog
  alias Cadence.Catalog.{Actor, Artifact}
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F
  alias Cadence.MissionModels.TelemetryProjection

  def prepare(scope, opts \\ []) do
    # #513: the import names the person who ran the seed, the scope this seed acts as.
    revision = import_database(Keyword.put_new(opts, :run_by, scope.user.user_id))
    {:ok, mission} = Cadence.Missions.fetch_mission(F.organization_id(), F.mission_id())
    {:ok, telemetry} = TelemetryProjection.load(F.organization_id(), F.mission_id(), revision)
    apids = telemetry.packet_definitions |> Enum.map(& &1.apid) |> Enum.uniq() |> Enum.sort()
    10 = length(apids)
    fleet = Cadence.SpacecraftStore.list_spacecraft(F.organization_id(), F.mission_id())
    500 = length(fleet)

    fleet
    |> Enum.with_index(1)
    |> Enum.each(fn {craft, index} ->
      {:ok, %{routes: routes, findings: []}} =
        ProviderScheduling.list_ready_downlink_routes(
          F.organization_id(),
          F.mission_id(),
          craft.spacecraft_id
        )

      2 = length(routes)
      [source_endpoint_id] = routes |> Enum.map(& &1.source_endpoint_id) |> Enum.uniq()
      {:ok, profile} = Cadence.SpacecraftStore.fetch_pinned_profile(mission, craft)
      current = Drafts.snapshot(mission, craft)

      document = %{
        "catalog_revision_id" => revision.catalog_revision_id,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "telemetry_source_endpoint_id" => source_endpoint_id,
        "handled_apids" => apids,
        "protocol" => SpacecraftConfigurationInput.from_profile(profile)
      }

      unless current.saved == document and not current.external_changes do
        {:ok, _saved} =
          Drafts.save(scope, F.mission_id(), craft.spacecraft_id, current.token, document)
      end

      if rem(index, 50) == 0,
        do: IO.puts("Configured #{index}/500 spacecraft for telemetry and commanding")
    end)

    %{mission: mission, revision: revision, apids: apids, fleet: fleet}
  end

  @doc """
  Imports the demo database as it reads now and returns its revision, without touching any
  spacecraft configuration. For moving a fleet onto it with a change set (#65): the artifact id
  is content-addressed, so this is a no-op returning the existing revision when nothing changed.
  """
  # `opts` must name `run_by`, the user id of the person running it (#513).
  def import_revision(opts), do: import_database(opts)

  # The legacy reference database has no verifiers, so commands would never read satisfied.
  # The demo adds uplink verifiers to a few commands as it reads the file (#44); the reference
  # file itself stays untouched. COP-1 completion means the spacecraft's FARM accepted the frame.
  @verified_commands ~w(NOOP RESET_COUNTERS SET_MODE)
  @verifiers """
      verifiers:
        - name: Uplink started
          phase: start
          timeout_ms: 30000
          success_criteria:
            criteria_type: comparison
            subject_ref: transport:started
            comparison: equal
            value: true
        - name: Accepted on board
          phase: completion
          timeout_ms: 30000
          success_criteria:
            criteria_type: comparison
            subject_ref: transport:completed
            comparison: equal
            value: true
  """

  # SET_MODE also checks telemetry: the spacecraft's HK.sc_mode reads the mode it was sent
  # (raw: sc_mode's state table makes the engineering value a label). Lets #38 verifier scope
  # be tested live: only the target spacecraft's HK can satisfy it.
  @mode_verifier """
        - name: Mode applied
          phase: completion
          timeout_ms: 60000
          success_criteria:
            criteria_type: comparison
            subject_ref: telemetry:HK.sc_mode
            comparison: equal
            value_from_argument: mode
            use_calibrated: false
  """

  # Who imported the demo catalog (lead 11-14/11-17): the seed names itself as a system actor (a
  # stable ref, never a person) and, since #513, the person who ran it (`run_by`), who counts as
  # the model's importer, so a second admin approves it.
  defp seed_actor(run_by),
    do: Actor.system("seed:reflect-orbital-v1", "Reflect Orbital demo seed", run_by)

  defp with_demo_verifiers(source) do
    Enum.reduce(@verified_commands, source, fn name, acc ->
      line = "  - name: #{name}\n"
      ^line = if String.contains?(acc, line), do: line, else: raise("#{name} not found")
      verifiers = if name == "SET_MODE", do: @verifiers <> @mode_verifier, else: @verifiers
      String.replace(acc, line, line <> verifiers, global: false)
    end)
  end

  defp import_database(opts) do
    run_by = Keyword.fetch!(opts, :run_by)

    id = "catalog-earendil-command-telemetry"
    source = F.database_path() |> File.read!() |> with_demo_verifiers()
    digest = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)

    case Catalog.fetch_database(F.organization_id(), F.mission_id(), id) do
      {:ok, _} ->
        :ok

      {:error, :catalog_database_not_found} ->
        {:ok, _} =
          Catalog.create_database(F.organization_id(), F.mission_id(), %{
            catalog_database_id: id,
            name: "Demo Spacecraft — Command & Telemetry",
            catalog_family: :combined,
            default_importer_key: "cadence_yaml",
            created_by: seed_actor(run_by),
            description:
              "The repository's complete demo_spacecraft.yaml, assigned to the Earendil demonstration fleet.",
            metadata: F.metadata()
          })
    end

    artifact_id = "artifact-earendil-ct-#{digest}"

    existing =
      Catalog.list_revisions(F.organization_id(), F.mission_id(), id)
      |> Enum.find(&(&1.artifact_id == artifact_id))

    if existing && not Keyword.get(opts, :reimport?, false) do
      existing
    else
      artifact =
        Artifact.new(%{
          artifact_id: artifact_id,
          mission_id: F.mission_id(),
          catalog_family: :combined,
          artifact_name: "demo_spacecraft.yaml",
          format_key: "cadence_yaml",
          media_type: "application/yaml",
          source_artifact: source,
          uploaded_by: seed_actor(run_by),
          metadata:
            Map.put(
              F.metadata(),
              "source_path",
              "dev/catalogs/demo_spacecraft.yaml"
            )
        })

      {:ok, run} =
        Catalog.start_revision_import(
          F.organization_id(),
          F.mission_id(),
          id,
          artifact,
          "cadence_yaml",
          requested_by: seed_actor(run_by)
        )

      await_import(run.import_run_id, 120)

      {:ok, revision} =
        Catalog.fetch_revision_by_import_run(
          F.organization_id(),
          F.mission_id(),
          run.import_run_id
        )

      revision
    end
  end

  defp await_import(_id, 0), do: raise("Timed out importing demo_spacecraft.yaml")

  defp await_import(id, remaining) do
    {:ok, run} = Catalog.fetch_import_run(F.organization_id(), F.mission_id(), id)

    case run.status do
      :completed ->
        :ok

      :failed ->
        raise "Database import failed: #{inspect(run.failure_reason)}"

      _ ->
        Process.sleep(500)
        await_import(id, remaining - 1)
    end
  end
end
