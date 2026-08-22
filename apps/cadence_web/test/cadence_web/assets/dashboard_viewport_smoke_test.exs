defmodule CadenceWeb.Assets.DashboardViewportSmokeTest do
  use ExUnit.Case, async: false

  test "dashboard viewport fixture renders without overflow or critical overlap" do
    app_root = Path.expand("../../..", __DIR__)
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} = System.cmd("node", [script], cd: app_root, stderr_to_stdout: true)
    assert output =~ "dashboard_viewport_smoke passed"
  end
end
