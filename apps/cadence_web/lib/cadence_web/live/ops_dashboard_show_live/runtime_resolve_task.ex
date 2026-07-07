defmodule CadenceWeb.OpsDashboardShowLive.RuntimeResolveTask do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.EngineResolution
  alias CadenceWeb.ScopeLoader

  @worker_result :dashboard_engine_resolve_worker_result

  @spec resolve(term(), term(), term(), binary() | nil, keyword()) :: {term(), term()}
  def resolve(resolve_id, request, comparison_request, browser_test_sandbox_owner_key, opts \\ []) do
    case allow_current(browser_test_sandbox_owner_key, opts) do
      :ok ->
        resolve_allowed(
          resolve_id,
          request,
          comparison_request,
          browser_test_sandbox_owner_key,
          opts
        )

      {:error, reason} ->
        exit({:shutdown, {:browser_test_sandbox_owner_unavailable, reason}})
    end
  end

  defp resolve_allowed(
         resolve_id,
         request,
         comparison_request,
         browser_test_sandbox_owner_key,
         opts
       ) do
    case browser_test_sandbox_owner(browser_test_sandbox_owner_key, opts) do
      {:ok, owner} ->
        resolve_with_owner_guard(
          resolve_id,
          request,
          comparison_request,
          browser_test_sandbox_owner_key,
          owner,
          opts
        )

      :none ->
        {resolve_id, resolve_request_bundle(request, comparison_request, opts)}

      {:error, reason} ->
        exit({:shutdown, {:browser_test_sandbox_owner_unavailable, reason}})
    end
  end

  defp resolve_with_owner_guard(
         resolve_id,
         request,
         comparison_request,
         browser_test_sandbox_owner_key,
         owner,
         opts
       ) do
    owner_ref = Process.monitor(owner)
    parent = self()

    {worker_pid, worker_ref} =
      spawn_monitor(fn ->
        receive do
          :run ->
            send(
              parent,
              {@worker_result, self(), resolve_request_bundle(request, comparison_request, opts)}
            )

          :stop ->
            :ok
        end
      end)

    case allow_worker(browser_test_sandbox_owner_key, worker_pid, opts) do
      :ok ->
        send(worker_pid, :run)
        await_worker(resolve_id, worker_pid, worker_ref, owner_ref)

      {:error, reason} ->
        stop_worker(worker_pid, worker_ref)
        Process.demonitor(owner_ref, [:flush])
        exit({:shutdown, {:browser_test_sandbox_owner_unavailable, reason}})
    end
  end

  defp await_worker(resolve_id, worker_pid, worker_ref, owner_ref) do
    receive do
      {@worker_result, ^worker_pid, result} ->
        Process.demonitor(worker_ref, [:flush])
        Process.demonitor(owner_ref, [:flush])
        {resolve_id, result}

      {:DOWN, ^owner_ref, :process, _owner_pid, reason} ->
        stop_worker(worker_pid, worker_ref)
        exit({:shutdown, {:browser_test_sandbox_owner_unavailable, reason}})

      {:DOWN, ^worker_ref, :process, ^worker_pid, :normal} ->
        await_worker_result_after_normal_exit(resolve_id, worker_pid, owner_ref)

      {:DOWN, ^worker_ref, :process, ^worker_pid, reason} ->
        Process.demonitor(owner_ref, [:flush])
        exit(reason)
    end
  end

  defp await_worker_result_after_normal_exit(resolve_id, worker_pid, owner_ref) do
    receive do
      {@worker_result, ^worker_pid, result} ->
        Process.demonitor(owner_ref, [:flush])
        {resolve_id, result}
    after
      0 ->
        Process.demonitor(owner_ref, [:flush])
        exit({:shutdown, :dashboard_engine_resolve_worker_exited_without_result})
    end
  end

  defp stop_worker(worker_pid, worker_ref) do
    Process.exit(worker_pid, :kill)

    receive do
      {:DOWN, ^worker_ref, :process, ^worker_pid, _reason} -> :ok
    after
      100 -> Process.demonitor(worker_ref, [:flush])
    end
  end

  defp resolve_request_bundle(request, comparison_request, opts) do
    resolve_request_bundle_fn(opts).(request, comparison_request)
  end

  defp allow_current(browser_test_sandbox_owner_key, opts) do
    allow_current_fn(opts).(browser_test_sandbox_owner_key)
  end

  defp allow_worker(browser_test_sandbox_owner_key, worker_pid, opts) do
    allow_worker_fn(opts).(browser_test_sandbox_owner_key, worker_pid)
  end

  defp browser_test_sandbox_owner(browser_test_sandbox_owner_key, opts) do
    browser_test_sandbox_owner_fn(opts).(browser_test_sandbox_owner_key)
  end

  defp resolve_request_bundle_fn(opts) do
    Keyword.get(opts, :resolve_request_bundle, &EngineResolution.resolve_request_bundle/2)
  end

  defp allow_current_fn(opts) do
    Keyword.get(
      opts,
      :allow_browser_test_sandbox_owner,
      &ScopeLoader.allow_browser_test_sandbox_owner/1
    )
  end

  defp allow_worker_fn(opts) do
    Keyword.get(
      opts,
      :allow_browser_test_sandbox_owner_for,
      &ScopeLoader.allow_browser_test_sandbox_owner/2
    )
  end

  defp browser_test_sandbox_owner_fn(opts) do
    Keyword.get(opts, :browser_test_sandbox_owner, &ScopeLoader.browser_test_sandbox_owner/1)
  end
end
