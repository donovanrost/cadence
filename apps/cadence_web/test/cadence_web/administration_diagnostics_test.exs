defmodule CadenceWeb.AdministrationDiagnosticsTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Cadence.Auth.Scope
  alias Cadence.Reads.Dashboards.RuntimeDiagnostics
  alias Cadence.Telemetry.RuntimeHealth
  alias CadenceWeb.{AdministrationDiagnostics, TestFixtures}

  @validator Path.expand(
               "../../../../frontend/modules/dashboards-and-exploration/src/features/runtime-diagnostics/validation.ts",
               __DIR__
             )

  setup do
    user = TestFixtures.persist_user!(capabilities: [:platform_admin])
    scope = Scope.new(%{user: user, admin_mode?: true})

    conn =
      user
      |> TestFixtures.member_conn()
      |> put_session(:admin_mode_expires_at, CadenceWeb.AdminMode.expires_at())

    RuntimeHealth.reset()
    on_exit(fn -> RuntimeHealth.reset() end)
    {:ok, conn: conn, scope: scope, user: user}
  end

  test "host diagnostics loads without any frontend release and preserves filter navigation", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/admin/runtime?dashboard_id=selected-dashboard")
    assert has_element?(view, "#application-shell")
    assert [snapshot] = host_snapshot(view)["diagnostics"]
    assert snapshot["id"] == "dashboards.runtime-diagnostics"
    assert snapshot["status"] == "ready"
    assert snapshot["data"]["filters"]["values"]["dashboard_id"] == "selected-dashboard"

    render_hook(view, "host:context", %{"path" => "/admin/runtime?mission_id=selected-mission"})
    assert [refreshed] = host_snapshot(view)["diagnostics"]
    assert refreshed["data"]["filters"]["values"]["mission_id"] == "selected-mission"

    render_hook(view, "host:context", %{"path" => "/admin"})
    assert host_snapshot(view)["diagnostics"] == []
  end

  test "refresh reauthorizes a revoked session", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/runtime")
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => "/admin/runtime"})
    assert_redirect(view, "/sign-in")
  end

  test "platform eligibility alone does not authorize a diagnostic contribution", %{
    scope: scope,
    user: user
  } do
    assert AdministrationDiagnostics.load(Scope.new(%{user: user}), %{}) == []
    assert {:error, :unavailable} = RuntimeDiagnostics.contribution(Scope.new(%{user: user}), %{})

    assert {:error, :unavailable} =
             RuntimeDiagnostics.contribution(scope, %{"dashboard_id" => %{}})

    assert [%{status: "unavailable"} = unavailable] =
             AdministrationDiagnostics.load(scope, %{"component" => "forged"})

    refute Map.has_key?(unavailable, :data)
  end

  test "actual empty, populated and selected producer DTOs pass the feature's TypeScript validator",
       %{scope: scope} do
    assert {:ok, empty} = RuntimeDiagnostics.contribution(scope, %{})
    assert_consumer_accepts(empty.data)

    RuntimeHealth.execute(
      RuntimeHealth,
      [:cadence, :dashboards, :runtime_invalidation, :decision],
      %{invalidated_artifacts: 2},
      %{
        invalidation_event_id: "diagnostics-contract-decision",
        dashboard_id: "dashboard-contract",
        mission_id: "mission-contract",
        boundary: :source_watermark_changed,
        decision_status: :filtered,
        refresh_allowed?: false,
        refresh_reason: :stale_for_context,
        decision: %{credential: "must-not-escape", affected_placement_ids: ["placement-1"]}
      }
    )

    assert {:ok, populated} =
             RuntimeDiagnostics.contribution(scope, %{"dashboard_id" => "dashboard-contract"})

    assert [row] = populated.data.decisions
    assert_consumer_accepts(populated.data)

    assert {:ok, selected} =
             RuntimeDiagnostics.contribution(scope, %{
               "dashboard_id" => "dashboard-contract",
               "decision" => row.key
             })

    assert selected.data.selection.detail
    refute Jason.encode!(selected.data) =~ "must-not-escape"
    assert_consumer_accepts(selected.data)

    assert {:ok, missing} =
             RuntimeDiagnostics.contribution(scope, %{"decision" => "missing-decision"})

    assert missing.data.selection.missing
    assert_consumer_accepts(missing.data)
  end

  defp host_snapshot(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]

  defp assert_consumer_accepts(data) do
    node =
      System.find_executable("node") ||
        flunk("Node is required for producer/consumer contract validation")

    script =
      "import {assertRuntimeDiagnostics} from #{Jason.encode!(@validator)}; assertRuntimeDiagnostics(JSON.parse(process.argv[1]));"

    {output, status} =
      System.cmd(
        node,
        ["--no-warnings", "--input-type=module", "-e", script, Jason.encode!(data)],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
