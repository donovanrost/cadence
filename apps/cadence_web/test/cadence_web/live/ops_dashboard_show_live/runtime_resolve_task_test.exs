defmodule CadenceWeb.OpsDashboardShowLive.RuntimeResolveTaskTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeResolveTask

  test "resolve returns the engine result and allows the guarded worker" do
    test_pid = self()
    owner = self()

    result =
      RuntimeResolveTask.resolve(:resolve_1, :request, nil, "browser-key",
        allow_browser_test_sandbox_owner: fn key ->
          send(test_pid, {:allow_current, key, self()})
          :ok
        end,
        browser_test_sandbox_owner: fn "browser-key" -> {:ok, owner} end,
        allow_browser_test_sandbox_owner_for: fn key, worker_pid ->
          send(test_pid, {:allow_worker, key, worker_pid})
          :ok
        end,
        resolve_request_bundle: fn :request, nil ->
          send(test_pid, {:resolved, self()})
          :engine_result
        end
      )

    assert result == {:resolve_1, :engine_result}
    assert_receive {:allow_current, "browser-key", caller_pid}
    assert caller_pid == self()
    assert_receive {:allow_worker, "browser-key", worker_pid}
    assert_receive {:resolved, ^worker_pid}
  end

  test "resolve kills the guarded worker when the browser sandbox owner exits" do
    test_pid = self()
    owner = waiting_process()
    owner_ref = Process.monitor(owner)

    resolver =
      spawn(fn ->
        outcome =
          try do
            {:ok,
             RuntimeResolveTask.resolve(:resolve_1, :request, nil, "browser-key",
               allow_browser_test_sandbox_owner: fn _key -> :ok end,
               browser_test_sandbox_owner: fn "browser-key" -> {:ok, owner} end,
               allow_browser_test_sandbox_owner_for: fn _key, _worker_pid -> :ok end,
               resolve_request_bundle: fn :request, nil ->
                 send(test_pid, {:worker_started, self()})

                 receive do
                   :finish -> :engine_result
                 end
               end
             )}
          catch
            :exit, reason -> {:exit, reason}
          end

        send(test_pid, {:resolver_outcome, outcome})
      end)

    resolver_ref = Process.monitor(resolver)

    assert_receive {:worker_started, worker_pid}
    worker_ref = Process.monitor(worker_pid)

    Process.exit(owner, :shutdown)

    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :shutdown}

    assert_receive {:resolver_outcome,
                    {:exit, {:shutdown, {:browser_test_sandbox_owner_unavailable, :shutdown}}}}

    assert_receive {:DOWN, ^resolver_ref, :process, ^resolver, :normal}
    assert_receive {:DOWN, ^worker_ref, :process, ^worker_pid, :killed}
  end

  defp waiting_process do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end
end
