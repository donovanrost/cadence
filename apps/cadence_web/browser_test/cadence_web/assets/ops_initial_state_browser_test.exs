Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_runner.exs", __DIR__))

defmodule CadenceWeb.Assets.OpsInitialStateBrowserTest do
  use CadenceWeb.ConnCase, async: false
  import Ecto.Query
  alias CadenceWeb.TestFixtures

  setup do
    previous = Application.fetch_env(:cadence, :data_sources)
    Application.put_env(:cadence, :data_sources, persisted?: true, bootstrap_defaults?: false)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:cadence, :data_sources, value)
        :error -> Application.delete_env(:cadence, :data_sources)
      end
    end)

    :ok
  end

  @tag :browser_smoke
  @tag timeout: 600_000
  test "initial Ops routes render content or actionable prerequisites", c do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org, role: :organization_admin)

    base =
      Cadence.Dashboards.DocumentCodec.load!(
        Path.expand(
          "../../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
          __DIR__
        )
      )

    {:ok, _} =
      Cadence.Dashboards.Documents.persist(org.organization_id, %{
        base
        | organization_id: org.organization_id,
          mission_id: mission.mission_id,
          dashboard_id: "draft-dashboard",
          placements: [],
          sections: []
      })

    output_dir =
      System.get_env("CADENCE_INITIAL_STATE_ARTIFACTS") ||
        Path.join(
          System.tmp_dir!(),
          "cadence-ops-initial-state-#{System.unique_integer([:positive])}"
        )

    File.mkdir_p!(output_dir)

    port =
      CadenceWeb.Assets.DashboardRenderedViewportRunner.start_browser_endpoint_on_ephemeral_port!(
        c.sandbox_owner
      )

    {output, status} =
      CadenceWeb.Assets.DashboardRenderedViewportRunner.run_dashboard_viewport_smoke(
        [
          Path.expand(
            "../../../../../frontend/tools/phoenix/ops_initial_state_browser.mjs",
            __DIR__
          ),
          "http://127.0.0.1:#{port}",
          mission.mission_id,
          user.email,
          output_dir
        ],
        stdin: Jason.encode!(%{password: TestFixtures.default_password()}) <> "\n",
        timeout: 570_000
      )

    assert status == 0, output
    assert output =~ "OPS_LIFECYCLE_AUDIT_OK"

    assert Cadence.Repo.aggregate(
             from(r in Cadence.Commanding.CommandRequestRow,
               where: r.mission_id == ^mission.mission_id
             ),
             :count
           ) == 0

    assert %{published_version: nil} =
             Cadence.Repo.get_by!(Cadence.Dashboards.DocumentStore.DashboardRow,
               mission_id: mission.mission_id,
               dashboard_id: "draft-dashboard"
             )

    refute Cadence.Repo.get(Cadence.Activations.ActiveBindingSetRow, mission.mission_id)
  end
end
