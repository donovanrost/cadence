Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_runner.exs", __DIR__))

defmodule CadenceWeb.Assets.SpacecraftConfigurationBrowserTest do
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias CadenceWeb.Assets.DashboardRenderedViewportRunner, as: Runner
  alias CadenceWeb.TestFixtures

  @tag :browser_smoke
  @tag timeout: 300_000
  test "spacecraft setup preserves host navigation and drafts through Catalog and fleet switching",
       c do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org, display_name: "Kestrel")
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    first = TestFixtures.persist_spacecraft!(mission, display_name: "KESTREL-01", scid: 1)
    second = TestFixtures.persist_spacecraft!(mission, display_name: "KESTREL-02", scid: 2)

    revision =
      Fixtures.persist_qualified_revision!(org.organization_id, mission.mission_id,
        revision_label: "Flight 2026.9"
      )

    out = Path.join(System.tmp_dir!(), "cadence-spacecraft-configuration-browser")
    File.mkdir_p!(out)
    port = Runner.start_browser_endpoint_on_ephemeral_port!(c.sandbox_owner)

    {output, status} =
      Runner.run_dashboard_viewport_smoke(
        [
          Path.expand(
            "../../../../../frontend/tools/phoenix/spacecraft_configuration_browser.mjs",
            __DIR__
          ),
          "http://127.0.0.1:#{port}",
          mission.mission_id,
          user.email,
          first.spacecraft_id,
          second.spacecraft_id,
          revision.catalog_revision_id,
          out
        ],
        stdin: Jason.encode!(%{password: TestFixtures.default_password()}) <> "\n",
        timeout: 270_000
      )

    assert status == 0, output
    assert output =~ "SPACECRAFT_CONFIGURATION_BROWSER_OK"

    row =
      Cadence.Applications.SpacecraftConfiguration.Drafts.latest(
        org.organization_id,
        mission.mission_id,
        first.spacecraft_id
      )

    assert row.version == 1
    assert row.catalog_revision_id == revision.catalog_revision_id
    assert row.document["handled_apids"] == [42]
    assert row.document["commanding_enabled"]
    assert row.document["protocol"] == nil

    assert Cadence.Applications.SpacecraftConfiguration.Drafts.latest(
             org.organization_id,
             mission.mission_id,
             second.spacecraft_id
           ) == nil

    assert {:error, :no_active_binding_set} =
             Cadence.Activations.fetch_active_activation(org.organization_id, mission.mission_id)
  end
end
