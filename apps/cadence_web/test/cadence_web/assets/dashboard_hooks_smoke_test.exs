defmodule CadenceWeb.Assets.DashboardHooksSmokeTest do
  use ExUnit.Case, async: true

  test "dashboard browser-adjacent hooks preserve copy and grid contracts" do
    app_root = Path.expand("../../..", __DIR__)
    script = Path.join(app_root, "assets/test/dashboard_hooks_smoke_test.mjs")

    assert {output, 0} = System.cmd("node", [script], cd: app_root, stderr_to_stdout: true)
    assert output =~ "dashboard_hooks_smoke_test passed"
  end
end
