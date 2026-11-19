defmodule Cadence.Platform.ReadMemo do
  @moduledoc """
  A process-scoped snapshot for the reads of one attention load (U61, 11-16): `Reads.Attention`
  wraps each load and its counts in `with_memo/1`, and `Reads.PlanCoverageAttention` keeps its day
  read there with `fetch/2`, so a load's items, resolutions and counts share one read. Nothing in
  a load writes.

  Only `{:ok, value}` results are kept (a miss is read again), and only for the duration of the
  wrapped call. Nested `with_memo/1` calls share the outer memo. Outside one, `fetch/2` just reads.

  The configuration apply path doesn't use it (step 4, 11-15: a fleet apply now passes the
  catalog, projection and plans it read explicitly; a process-dictionary memo inside the apply
  transaction was the root cause). Keep it to read-only loads like the attention one.
  """

  @key :cadence_read_memo

  @spec with_memo((-> result)) :: result when result: term()
  def with_memo(fun) when is_function(fun, 0) do
    case Process.get(@key) do
      nil ->
        Process.put(@key, %{})

        try do
          fun.()
        after
          Process.delete(@key)
        end

      _already_memoizing ->
        fun.()
    end
  end

  @doc "The memoized `{:ok, value}` for `key`, or `loader.()` (kept when it's `{:ok, _}`)."
  @spec fetch(term(), (-> result)) :: result when result: term()
  def fetch(key, loader) when is_function(loader, 0) do
    case Process.get(@key) do
      nil ->
        loader.()

      %{^key => cached} ->
        cached

      memo ->
        case loader.() do
          {:ok, _value} = result ->
            Process.put(@key, Map.put(memo, key, result))
            result

          other ->
            other
        end
    end
  end
end
