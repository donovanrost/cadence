defmodule CadenceWeb.ApplicationReleaseRegistryTest do
  use Cadence.DataCase, async: false

  Code.require_file(
    Path.expand("../../browser_test/support/federation_release_fixture.exs", __DIR__)
  )

  alias CadenceWeb.ApplicationReleaseRegistry
  alias CadenceWeb.Assets.FederationReleaseFixture

  test "keys the checked-in Comms release by application and surface versions" do
    assert {:ok, release} = ApplicationReleaseRegistry.fetch("comms_overview", 1, "overview", 1)

    assert release == %{
             federation: :module_federation,
             release_id: "comms-overview-v1",
             remote_name: "cadence_comms_overview",
             manifest_path: "/assets/application-host/comms-overview/mf-manifest.json",
             exposed_module: "./Application"
           }
  end

  test "does not advertise the unpublished Comms remote" do
    surfaces =
      ~w(overview validation transports transport routing routing_detail ground_stations ground_station)

    Enum.each(surfaces, fn surface_id ->
      assert {:error, :unknown_application_release} =
               ApplicationReleaseRegistry.fetch("comms", 1, surface_id, 1)
    end)

    refute Enum.any?(ApplicationReleaseRegistry.all(), fn {{application_key, _version, _surface,
                                                            _surface_version}, _release} ->
             application_key == "comms"
           end)
  end

  test "advertises the checked-in telemetry packet bindings release coordinate" do
    assert {:ok, release} =
             ApplicationReleaseRegistry.fetch("telemetry_decom", 1, "packet_bindings", 1)

    assert release == %{
             federation: :module_federation,
             release_id: "telemetry-decom-v1",
             remote_name: "cadence_telemetry_decom",
             manifest_path: "/assets/application-host/telemetry-decom/mf-manifest.json",
             exposed_module: "./Application"
           }

    assert Enum.all?(ApplicationReleaseRegistry.all(), fn {_key, release} ->
             String.starts_with?(release.manifest_path, "/assets/") and
               not String.contains?(release.manifest_path, "/releases/current")
           end)
  end

  test "reports missing post-cutover active history as an integrity failure" do
    assert [[0]] =
             Repo.query!("""
             SELECT cutover_epoch
             FROM frontend_release_activation_controls
             WHERE control_id = 1
             """).rows

    assert [[1]] =
             Repo.query!("""
             UPDATE frontend_release_activation_controls
             SET cutover_epoch = 1, cutover_at = now()
             WHERE control_id = 1
             RETURNING cutover_epoch
             """).rows

    assert {:error, {:integrity_failure, :active_generation_missing}} =
             ApplicationReleaseRegistry.snapshot()
  end

  test "fails closed for an expired active catalog without changing accepted state" do
    previous_config =
      Application.get_env(:cadence_web, :frontend_release_publication, :not_configured)

    Application.put_env(
      :cadence_web,
      :frontend_release_publication,
      FederationReleaseFixture.publication_config()
    )

    on_exit(fn ->
      case previous_config do
        :not_configured -> Application.delete_env(:cadence_web, :frontend_release_publication)
        config -> Application.put_env(:cadence_web, :frontend_release_publication, config)
      end
    end)

    fixture =
      FederationReleaseFixture.prepare_and_activate!(
        Path.expand("../..", __DIR__),
        sandbox_owner: self()
      )

    on_exit(fn -> FederationReleaseFixture.cleanup!(fixture) end)

    previous_snapshot_clock =
      Process.get(ApplicationReleaseRegistry.snapshot_clock_key(), :not_configured)

    Process.put(ApplicationReleaseRegistry.snapshot_clock_key(), "2026-09-02T00:00:00Z")

    on_exit(fn ->
      if previous_snapshot_clock == :not_configured do
        Process.delete(ApplicationReleaseRegistry.snapshot_clock_key())
      else
        Process.put(ApplicationReleaseRegistry.snapshot_clock_key(), previous_snapshot_clock)
      end
    end)

    accepted = ApplicationReleaseRegistry.snapshot()
    assert {:ok, %{source: :database, entries: entries}} = accepted
    assert length(entries) == 2

    accepted_control =
      Repo.query!("""
      SELECT cutover_epoch, cutover_at, legacy_catalog_publication_id
      FROM frontend_release_activation_controls
      WHERE control_id = 1
      """).rows

    accepted_generation =
      Repo.query!("""
      SELECT generation_id, catalog_publication_id, sequence
      FROM frontend_release_catalog_generations
      """).rows

    assert {:error, {:integrity_failure, :active_catalog_expired}} =
             ApplicationReleaseRegistry.snapshot(now: "2026-10-01T00:00:00Z")

    assert Repo.query!("""
           SELECT cutover_epoch, cutover_at, legacy_catalog_publication_id
           FROM frontend_release_activation_controls
           WHERE control_id = 1
           """).rows == accepted_control

    assert Repo.query!("""
           SELECT generation_id, catalog_publication_id, sequence
           FROM frontend_release_catalog_generations
           """).rows == accepted_generation
  end
end
