defmodule CadenceWeb.OpsDashboardShowLive.RuntimeResolveTaskTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeResolveTask

  test "resolve returns the engine result in the calling process" do
    test_pid = self()

    result =
      RuntimeResolveTask.resolve(:resolve_1, :request, nil, :resolution_context,
        resolve_request_bundle: fn :request, nil, :resolution_context ->
          send(test_pid, {:resolved, self()})
          :engine_result
        end
      )

    assert result == {:resolve_1, :engine_result}
    assert_receive {:resolved, resolver_pid}
    assert resolver_pid == self()
  end
end
