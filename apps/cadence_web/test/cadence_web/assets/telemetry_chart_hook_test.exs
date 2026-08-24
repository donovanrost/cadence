defmodule CadenceWeb.Assets.TelemetryChartComponentTest do
  use ExUnit.Case, async: true

  test "telemetry chart LiveVue controller preserves its browser contract" do
    app_root = Path.expand("../../..", __DIR__)
    script = Path.join(app_root, "assets/test/telemetry_chart_append_test.mjs")

    assert {output, 0} = System.cmd("node", [script], cd: app_root, stderr_to_stdout: true)
    assert output =~ "telemetry_chart_append_test passed"
  end
end
