defmodule Cadence.Dev.ReflectOrbital.Configuration do
  @moduledoc "Imports and assigns the demo command and telemetry database to the Earendil fleet."
  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Dev.ReflectOrbital.Fixture, as: F
  alias Cadence.MissionModels.TelemetryProjection

  def prepare(scope, opts \\ []) do
    revision = import_database(opts)
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
        Cadence.Contacts.ProviderScheduling.list_ready_downlink_routes(
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

  defp import_database(opts) do
    id = "catalog-earendil-command-telemetry"
    source = File.read!(F.database_path())
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
          metadata:
            Map.put(
              F.metadata(),
              "source_path",
              "legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml"
            )
        })

      {:ok, run} =
        Catalog.start_revision_import(
          F.organization_id(),
          F.mission_id(),
          id,
          artifact,
          "cadence_yaml"
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
