Code.require_file(
  Path.expand("../../../browser_test/support/dashboard_rendered_viewport_runner.exs", __DIR__)
)

defmodule CadenceWeb.Assets.DashboardRenderedViewportRunnerTest do
  use ExUnit.Case, async: false

  alias CadenceWeb.Assets.DashboardRenderedViewportRunner

  test "TERM observation uses one absolute deadline despite continued output" do
    port = stubborn_port()
    assert_receive {^port, {:data, data}}, 1_000
    assert data =~ "ready"
    Enum.each(1..50, fn _ -> send(self(), {port, {:data, "output chunk\n"}}) end)
    started_at = System.monotonic_time(:millisecond)

    try do
      {output, status} =
        DashboardRenderedViewportRunner.terminate_dashboard_viewport_smoke(
          port,
          "",
          10,
          10
        )

      elapsed = System.monotonic_time(:millisecond) - started_at
      assert status == 124
      assert output =~ "observed after KILL"
      assert elapsed < 300, "TERM deadline was reset by output chunks (#{elapsed}ms)"
      assert Port.info(port) == nil
    after
      DashboardRenderedViewportRunner.close_dashboard_viewport_smoke_port(port)
    end
  end

  test "normal exit and timeout exit both close the owned port" do
    shell = System.find_executable("sh") || raise "sh executable is required"

    port =
      Port.open({:spawn_executable, shell}, [
        :binary,
        :exit_status,
        :use_stdio,
        {:args, ["-c", "exit 7"]}
      ])

    try do
      {_output, status} =
        DashboardRenderedViewportRunner.collect_dashboard_viewport_smoke(
          port,
          "",
          System.monotonic_time(:millisecond) + 1_000,
          1_000,
          10
        )

      assert status == 7
      assert Port.info(port) == nil
    after
      DashboardRenderedViewportRunner.close_dashboard_viewport_smoke_port(port)
    end
  end

  defp stubborn_port do
    shell = System.find_executable("sh") || raise "sh executable is required"

    Port.open(
      {:spawn_executable, shell},
      [
        :binary,
        :exit_status,
        :use_stdio,
        {:args, ["-c", "trap '' TERM; printf 'ready\\n'; while :; do :; done"]}
      ]
    )
  end
end
