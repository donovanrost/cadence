defmodule Cadence.Platform.ReadMemo do
  @moduledoc """
  A process-scoped memo for reads of IMMUTABLE rows by id (catalog revisions and their telemetry
  projection, mission-model revisions and runtime plans), around one fleet-wide operation.

  Step 4 (11-15): a catalog move for 499 spacecraft re-read and re-decoded the same catalog
  revision, telemetry projection, mission-model revision and runtime plans once per spacecraft
  inside the apply transaction, about 2,000 reads of large JSONB. The transaction then idled past
  its 120 s timeout and rolled back. Inside `with_memo/1` each is read once.

  Only `{:ok, value}` results are kept (a miss is read again), and only for the duration of the
  wrapped call. Nested `with_memo/1` calls share the outer memo. Outside one, `fetch/2` just reads.
  Like `SpacecraftTypeStore.with_version_memo/1`.

  `Reads.Attention` also wraps each load in one (U61, 11-16): `plan_coverage` keeps its day read
  there, so a load's items, resolutions and counts share one snapshot. Nothing in a load writes.

  One field isn't immutable: a mission-model revision's `status` (approved or rejected through
  `MissionModels.RevisionDecisions`). A status decision must not run inside `with_memo/1`, or a
  later `MissionModels.fetch_revision/3` in the same memo returns the old status (api-ops). Nothing
  does today.
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
