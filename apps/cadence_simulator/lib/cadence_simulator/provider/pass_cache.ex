defmodule CadenceSimulator.Provider.PassCache do
  @moduledoc """
  Caches a run's computed passes per spacecraft, upload and UTC day (#893), so repeated
  opportunity searches and offer restores don't propagate again. The cache is derived data,
  never part of the store's snapshot; a restart recomputes. It is bounded: past 4,096 entries
  it is cleared before the next insert. Without the process (a bare unit test),
  `fetch/2` just computes.
  """

  use GenServer

  @table __MODULE__
  @max_entries 4_096
  @computed :computed

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The cached value for `key`, computing and storing it with `fun` on a miss."
  @spec fetch(term(), (-> term())) :: term()
  def fetch(key, fun) when is_function(fun, 0) do
    if :ets.whereis(@table) == :undefined do
      fun.()
    else
      case :ets.lookup(@table, {:entry, key}) do
        [{_key, value}] -> value
        [] -> compute(key, fun)
      end
    end
  end

  @doc "How many values have been computed since start (cache misses)."
  @spec computed() :: non_neg_integer()
  def computed do
    case :ets.whereis(@table) do
      :undefined -> 0
      _table -> :ets.lookup_element(@table, @computed, 2)
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ets.insert(@table, {@computed, 0})
    {:ok, %{}}
  end

  defp compute(key, fun) do
    value = fun.()
    :ets.update_counter(@table, @computed, 1)

    if :ets.info(@table, :size) > @max_entries do
      computed = :ets.lookup_element(@table, @computed, 2)
      :ets.delete_all_objects(@table)
      :ets.insert(@table, {@computed, computed})
    end

    :ets.insert(@table, {{:entry, key}, value})
    value
  end
end
