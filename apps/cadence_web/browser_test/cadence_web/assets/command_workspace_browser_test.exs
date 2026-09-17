Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_runner.exs", __DIR__))

defmodule CadenceWeb.Assets.CommandWorkspaceBrowserTest do
  use CadenceWeb.ConnCase, async: false
  import Ecto.Query
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.{CommandQueueEntryRow, CommandRequestRow, StagedCommandItemRow}
  alias Cadence.Management.Commanding.WorkspaceSettings
  alias Cadence.Repo
  alias CadenceWeb.Assets.DashboardRenderedViewportRunner, as: Runner
  alias CadenceWeb.TestFixtures

  @tag :browser_smoke
  @tag timeout: 300_000
  test "production workspace retains context through fleet preparation and reviewed submission",
       c do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org, display_name: "Kestrel")
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    scope = Cadence.Auth.Scope.new(%{user: user, organization_membership: membership})
    settings = WorkspaceSettings.load(org.organization_id, mission.mission_id)

    assert {:ok, _} =
             WorkspaceSettings.save(scope, mission.mission_id, settings.token, %{
               "value" => %{"shelf" => "minimized"}
             })

    model = CommandAuthoringFixtures.activate!(org.organization_id, mission.mission_id)

    for {name, endpoint_name, scid} <- [
          {"KESTREL-01", "Primary OBC", 1},
          {"KESTREL-02", "Secondary OBC", 2}
        ] do
      craft = TestFixtures.persist_spacecraft!(mission, display_name: name)

      CommandAuthoringFixtures.target!(org.organization_id, mission.mission_id, %{
        spacecraft_id: craft.spacecraft_id,
        display_name: endpoint_name,
        scid: scid
      })
    end

    out =
      System.get_env("CADENCE_COMMAND_WORKSPACE_ARTIFACTS") ||
        Path.join(
          System.tmp_dir!(),
          "cadence-command-workspace-#{System.unique_integer([:positive])}"
        )

    File.mkdir_p!(out)
    port = Runner.start_browser_endpoint_on_ephemeral_port!(c.sandbox_owner)

    {output, status} =
      Runner.run_dashboard_viewport_smoke(
        [
          Path.expand(
            "../../../../../frontend/tools/phoenix/command_workspace_browser.mjs",
            __DIR__
          ),
          "http://127.0.0.1:#{port}",
          mission.mission_id,
          user.email,
          model.commands_by_name["COMMAND_1"],
          out,
          model.commands_by_name["COMMAND_2"]
        ],
        stdin: Jason.encode!(%{password: TestFixtures.default_password()}) <> "\n",
        timeout: 270_000
      )

    assert status == 0, output
    assert output =~ "COMMAND_WORKSPACE_BROWSER_OK"

    drafts =
      Repo.all(from(row in StagedCommandItemRow, where: row.mission_id == ^mission.mission_id))

    assert length(drafts) == 2

    assert Enum.sort(Enum.map(drafts, &get_in(&1.argument_values_document, ["value", "amount"]))) ==
             [2, 7]

    assert Enum.all?(drafts, &(&1.lifecycle_state == "submitted"))

    requests =
      Repo.all(from(row in CommandRequestRow, where: row.mission_id == ^mission.mission_id))

    assert length(requests) == 4
    {direct, staged} = Enum.split_with(requests, &is_nil(&1.source_command_stage_id))
    assert length(direct) == 2
    assert Enum.all?(direct, &(&1.lifecycle_state == "queued"))
    assert length(staged) == 2
    assert Enum.all?(staged, &(&1.lifecycle_state == "approval_pending"))

    assert Repo.aggregate(
             from(row in CommandQueueEntryRow, where: row.mission_id == ^mission.mission_id),
             :count
           ) == 2
  end
end
