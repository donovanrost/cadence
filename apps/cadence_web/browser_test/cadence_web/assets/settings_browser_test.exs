Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_runner.exs", __DIR__))

defmodule CadenceWeb.Assets.SettingsBrowserTest do
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Commanding.WorkspaceSettings
  alias Cadence.Management.ConsoleSettings
  alias Cadence.Runtime.Missions
  alias CadenceWeb.Assets.DashboardRenderedViewportRunner, as: Runner
  alias CadenceWeb.TestFixtures

  @tag :browser_smoke
  @tag :runtime
  @tag timeout: 300_000
  test "scoped settings govern direct and independent spacecraft activation", c do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org, display_name: "Kestrel")
    requester = TestFixtures.persist_user!(display_name: "Maya Chen")
    reviewer = TestFixtures.persist_user!(display_name: "Eli Navarro")
    membership = TestFixtures.grant_membership!(requester, org)
    TestFixtures.grant_membership!(reviewer, org)
    scope = Scope.new(%{user: requester, organization_membership: membership})
    # #233: only an organization admin may loosen a mission's approval setting or change the
    # organization's, so a third person (never the requester or the reviewer) saves those.
    admin = TestFixtures.persist_user!(display_name: "Ana Ortiz")
    admin_membership = TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    admin_scope = Scope.new(%{user: admin, organization_membership: admin_membership})
    revision = Fixtures.persist_imported_revision!(org.organization_id, mission.mission_id)

    craft =
      Enum.map(["KESTREL-01", "KESTREL-02"], fn name ->
        item = TestFixtures.persist_spacecraft!(mission, display_name: name)

        document = %{
          SpacecraftConfigurationInput.empty()
          | "catalog_revision_id" => revision.catalog_revision_id,
            "commanding_enabled" => true
        }

        {:ok, _} =
          Drafts.save(
            scope,
            mission.mission_id,
            item.spacecraft_id,
            Drafts.snapshot(mission, item).token,
            document
          )

        item
      end)

    [first, second] = craft
    out = Path.join(System.tmp_dir!(), "cadence-settings-browser")
    File.mkdir_p!(out)
    port = Runner.start_browser_endpoint_on_ephemeral_port!(c.sandbox_owner)

    run_phase = fn phase ->
      Runner.run_dashboard_viewport_smoke(
        [
          Path.expand("../../../../../frontend/tools/phoenix/settings_browser.mjs", __DIR__),
          "http://127.0.0.1:#{port}",
          mission.mission_id,
          requester.email,
          reviewer.email,
          first.spacecraft_id,
          second.spacecraft_id,
          out,
          phase
        ],
        stdin: Jason.encode!(%{password: TestFixtures.default_password()}) <> "\n",
        timeout: 135_000
      )
    end

    # §11c(B) moved the mission settings page to the console too: the mission's settings are set
    # through the domain API the console's Setup › Settings uses. The requester, an ordinary
    # member, can't loosen the approval setting (#233); the organization admin does.
    direct = %{"approval_requirement" => "direct"}

    assert {:error, :approval_policy_change_requires_organization_admin} =
             ConsoleSettings.save(scope, mission.mission_id, "cadence.governance", direct, nil)

    for {save_scope, section, values} <- [
          {admin_scope, "cadence.governance", direct},
          {scope, "commanding.defaults", %{"shelf" => "minimized"}}
        ] do
      assert {:ok, %{state: :active}} =
               ConsoleSettings.save(
                 save_scope,
                 mission.mission_id,
                 section,
                 values,
                 nil
               )
    end

    {output, status} = run_phase.("mission")
    assert status == 0, output
    assert output =~ "SETTINGS_MISSION_PHASE_OK"

    # Then the organization requires independent approval with no mission override (§11c(A)
    # moved the organization settings page to the console). The organization's approval setting
    # is the organization admin's to change (#233).
    assert {:ok, %{state: :active}} =
             ConsoleSettings.save(
               admin_scope,
               nil,
               "cadence.governance",
               %{"allow_override" => false},
               nil
             )

    {output, status} = run_phase.("enforced")
    assert status == 0, output
    assert output =~ "SETTINGS_BROWSER_OK"
    assert {:ok, %{generation: 2}} = Missions.applied_spec(mission.mission_id)

    assert ActivationPolicy.load(org.organization_id, mission.mission_id).source ==
             "enforced"

    assert WorkspaceSettings.load(org.organization_id, mission.mission_id).effective["shelf"] ==
             "minimized"
  end
end
