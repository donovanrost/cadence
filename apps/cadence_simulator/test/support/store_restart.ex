defmodule CadenceSimulator.StoreRestart do
  @moduledoc """
  #331: waits until the provider store is back after a stop or kill, and READY.

  A GenServer registers its name before `init/1` runs, and the store builds its ETS mirror in
  `init/1` (loading the DETS file). Reads go straight to that table from the caller (qa #46), so a
  test that only waits for a new pid under the name can read before the table exists. That's the
  'table identifier does not refer to an existing ETS table' flake. A synchronous call to the new
  pid is handled only after `init/1` has returned, so once it answers, the mirror exists.
  """

  alias CadenceSimulator.Provider.Store

  @doc "The restarted store's pid, once it differs from `old` and has finished `init/1`."
  @spec await(pid(), pos_integer()) :: pid()
  def await(old, timeout_ms \\ 5_000) when is_pid(old) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    pid = await_new(old, deadline)
    # Answered only after init/1 returned, so the mirror table exists.
    _state = :sys.get_state(pid, max(deadline - System.monotonic_time(:millisecond), 100))
    pid
  end

  defp await_new(old, deadline) do
    case Process.whereis(Store) do
      pid when is_pid(pid) and pid != old ->
        pid

      _not_yet ->
        if System.monotonic_time(:millisecond) >= deadline,
          do: raise("the provider store didn't restart in time")

        Process.sleep(10)
        await_new(old, deadline)
    end
  end
end
