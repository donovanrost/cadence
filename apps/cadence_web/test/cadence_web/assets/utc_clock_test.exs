defmodule CadenceWeb.Assets.UtcClockTest do
  use ExUnit.Case, async: true

  test "UTC clock preserves formatting, lifecycle, cleanup, and accessibility" do
    app_root = Path.expand("../../..", __DIR__)
    script = Path.join(app_root, "assets/test/utc_clock_test.mjs")

    assert {output, 0} = System.cmd("node", [script], cd: app_root, stderr_to_stdout: true)
    assert output =~ "utc_clock_test passed"
  end
end
