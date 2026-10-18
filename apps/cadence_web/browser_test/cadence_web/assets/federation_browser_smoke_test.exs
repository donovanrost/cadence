Code.require_file(Path.expand("../../support/federation_browser_smoke_setup.exs", __DIR__))

defmodule CadenceWeb.Assets.FederationBrowserSmokeTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  alias Ecto.Adapters.SQL.Sandbox
  alias CadenceWeb.Assets.FederationBrowserSmokeSetup
  alias CadenceWeb.Assets.DashboardRenderedViewportRunner
  import Phoenix.LiveViewTest

  @tag :browser_smoke
  test "mission entry sends authorized context through incremental props" do
    assert Application.fetch_env!(:live_vue, :enable_props_diff)
    user = CadenceWeb.TestFixtures.persist_user!()
    organization = CadenceWeb.TestFixtures.persist_org!()
    CadenceWeb.TestFixtures.grant_membership!(user, organization)
    mission = CadenceWeb.TestFixtures.persist_mission!(organization)
    {:ok, view, _html} = live(CadenceWeb.TestFixtures.member_conn(user), "/missions")
    initial = LiveVue.Test.get_vue(view, id: "application-shell")
    assert initial.use_diff
    assert initial.component == "BrowserHost"

    render_hook(view, "host:context", %{"path" => "/missions/#{mission.mission_id}"})
    shell = LiveVue.Test.get_vue(view, id: "application-shell")

    assert ["replace", "/snapshot", snapshot] =
             Enum.find(shell.props_diff, fn [_op, path | _value] -> path == "/snapshot" end)

    assert snapshot["context"]["mission"]["mission_id"] == mission.mission_id
  end

  @tag :browser_smoke
  test "concurrent ephemeral Bandit endpoints retain their owned ports", %{
    sandbox_owner: sandbox_owner
  } do
    :ok = Sandbox.mode(Cadence.Repo, {:shared, sandbox_owner})

    results =
      Task.async_stream(
        1..2,
        fn _index -> DashboardRenderedViewportRunner.start_browser_endpoint_link!(0) end,
        max_concurrency: 2,
        ordered: false,
        timeout: 5_000
      )
      |> Enum.to_list()

    endpoints =
      Enum.flat_map(results, fn
        {:ok, endpoint} -> [endpoint]
        _ -> []
      end)

    on_exit(fn ->
      Enum.each(endpoints, fn {endpoint_pid, _port} ->
        DashboardRenderedViewportRunner.stop_browser_endpoint(endpoint_pid)
      end)
    end)

    assert Enum.all?(results, &match?({:ok, {_pid, port}} when is_integer(port) and port > 0, &1))
    assert Enum.uniq(Enum.map(endpoints, &elem(&1, 1))) |> length() == 2
  end

  @tag :browser_smoke
  test "authenticated production federation surfaces pass the browser gate", %{
    sandbox_owner: sandbox_owner
  } do
    assert :ok = FederationBrowserSmokeSetup.run(sandbox_owner)
  end
end
