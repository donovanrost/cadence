defmodule CadenceWeb.ApplicationReleaseRegistryTest do
  use Cadence.DataCase, async: false

  Code.require_file(
    Path.expand("../../browser_test/support/federation_release_fixture.exs", __DIR__)
  )

  alias CadenceWeb.ApplicationReleaseRegistry
  alias CadenceWeb.Assets.FederationReleaseFixture

  @now "2026-09-01T19:00:00Z"

  test "requires an explicit snapshot clock" do
    assert {:error, {:integrity_failure, :invalid_snapshot_clock}} =
             ApplicationReleaseRegistry.snapshot()

    assert {:error, {:integrity_failure, :invalid_snapshot_clock}} =
             ApplicationReleaseRegistry.all()

    assert {:error, {:integrity_failure, :invalid_snapshot_clock}} =
             ApplicationReleaseRegistry.fetch("telemetry_decom", 1, "packet_bindings", 1)
  end

  test "accepts canonical Z clocks and rejects pre-epoch, offset, malformed, and bad options" do
    assert {:ok, _milliseconds} = ApplicationReleaseRegistry.normalize_now(@now)

    assert {:ok, _milliseconds} =
             ApplicationReleaseRegistry.normalize_now("2026-09-01T19:00:00.000Z")

    assert {:ok, _milliseconds} =
             ApplicationReleaseRegistry.normalize_now(~U[2026-09-01 19:00:00Z])

    assert {:ok, _snapshot} = ApplicationReleaseRegistry.snapshot(now: @now)

    invalid_clocks = [
      -1,
      ~U[1969-12-31 23:59:59Z],
      "1969-12-31T23:59:59Z",
      "2026-09-03 00:00:00",
      "2026-09-03T00:00:00+00:00",
      "not-a-canonical-timestamp"
    ]

    for invalid <- invalid_clocks do
      assert {:error, {:integrity_failure, :invalid_snapshot_clock}} =
               ApplicationReleaseRegistry.normalize_now(invalid)

      assert {:error, {:integrity_failure, :invalid_snapshot_clock}} =
               ApplicationReleaseRegistry.snapshot(now: invalid)
    end

    assert {:error, {:integrity_failure, :invalid_snapshot_options}} =
             ApplicationReleaseRegistry.snapshot(%{})

    assert {:error, {:integrity_failure, :invalid_snapshot_options}} =
             ApplicationReleaseRegistry.all(%{})

    assert {:error, {:integrity_failure, :invalid_snapshot_options}} =
             ApplicationReleaseRegistry.all([:not_a_keyword])

    assert {:error, {:integrity_failure, :invalid_snapshot_options}} =
             ApplicationReleaseRegistry.fetch("telemetry_decom", 1, "packet_bindings", 1, %{})
  end

  test "advertises no release for headless Telemetry Decom (#669); every static release is an asset" do
    assert {:error, :unknown_application_release} =
             ApplicationReleaseRegistry.fetch("telemetry_decom", 1, "packet_bindings", 1,
               now: @now
             )

    assert Enum.all?(ApplicationReleaseRegistry.all(now: @now), fn {_key, release} ->
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
             ApplicationReleaseRegistry.snapshot(now: @now)
  end

  # The fixture builds and validates the ops-console production remote before packaging both
  # generations.
  # It needs the federation publication output (pnpm run build:publication), so CI runs it in a
  # job that builds that output (`--only frontend_publication`) and excludes it elsewhere.
  @tag timeout: 120_000
  @tag :frontend_publication
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

    accepted = ApplicationReleaseRegistry.snapshot(now: fixture.now)
    assert {:ok, %{source: :database, entries: entries}} = accepted
    # ops_console only: #709 removed organization_admin (its only surface was the notifications
    # bell), #671 mission_catalog and spacecraft, #917 comms, #669 telemetry_decom's surfaces.
    assert length(entries) == 1

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
             ApplicationReleaseRegistry.snapshot(now: fixture.expires_at)

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
