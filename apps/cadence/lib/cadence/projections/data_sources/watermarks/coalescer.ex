defmodule Cadence.Projections.DataSources.Watermarks.Coalescer do
  @moduledoc """
  Coalesces source-watermark observations in memory and writes them in bulk.

  A watermark status row is one per (mission, data source, binding, realm, replay run), so every
  batch from every path in a mission used to take the same row, insert an event row and an
  operational event, and serialize all of them. Now a batch only merges into one ETS entry per row
  key (`observe/1`: no database, no process call), and the pending entries are written as one
  `Watermarks.record_source_watermarks/2` batch:

    * every `:interval_ms` (default 5 s) by this process,
    * before a watermark read for the mission (`flush_mission/1`), so a read on this node sees what
      this node has observed,
    * at the end of a pass (`ContactSettler`), and on shutdown.

  A window merges as: earliest `retention_starts_at`, latest `complete_through` and
  `latest_receipt_time`, summed `sample_count`, latest `observed_at`, and a payload whose
  `first_sample_id` is the window's first and `last_sample_id` its last, with the observation
  count summed. One event row therefore covers a window instead of one batch.

  Flushes are serialized across the cluster by a database advisory lock, and the pending entries are
  taken only after it is held, so windows commit in the order they were taken. A failed flush puts
  its entries back.
  """

  use GenServer

  require Logger

  alias Cadence.DataSources.SourceWatermarkEvent
  alias Cadence.Projections.DataSources.Watermarks
  alias Cadence.Repo

  @table __MODULE__
  @lock_key 6_907_001
  @default_interval_ms 5_000

  @type entry :: {binary(), non_neg_integer(), binary() | nil, map()}

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Merges one batch's watermark attributes into its row's pending entry. The `:event_bus` and
  `:publish_facts?` options ride with the entry, which is only merged with entries that share
  them, so a flush publishes to the bus its batches named.
  """
  @spec observe(map(), keyword()) :: :ok
  def observe(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    row_key = SourceWatermarkEvent.new(attrs).source_watermark_key
    key = {row_key, Keyword.get(opts, :event_bus), Keyword.get(opts, :publish_facts?, false)}
    merge_into(key, attrs.mission_id, attrs)
  end

  @doc "Writes every pending entry."
  @spec flush() :: :ok | {:error, term()}
  def flush, do: flush(:all)

  @doc "Writes the pending entries of one mission, so a read after it sees them."
  @spec flush_mission(binary() | nil) :: :ok | {:error, term()}
  def flush_mission(nil), do: flush()
  def flush_mission(mission_id) when is_binary(mission_id), do: flush({:mission, mission_id})

  @doc "Writes the pending entry of one status row."
  @spec flush_key(binary()) :: :ok | {:error, term()}
  def flush_key(key) when is_binary(key), do: flush({:key, key})

  @doc "Merges a later window's attributes into an earlier one's."
  @spec merge(map(), map()) :: map()
  def merge(earlier, later) do
    Map.merge(later, %{
      retention_starts_at: earliest(earlier.retention_starts_at, later.retention_starts_at),
      complete_through: latest(earlier.complete_through, later.complete_through),
      latest_receipt_time: latest(earlier.latest_receipt_time, later.latest_receipt_time),
      observed_at: latest(earlier.observed_at, later.observed_at),
      sample_count: earlier.sample_count + later.sample_count,
      payload: merge_payload(earlier.payload, later.payload)
    })
  end

  @impl true
  def init(opts) do
    # Flushes on shutdown, so a stop does not lose the window.
    Process.flag(:trap_exit, true)
    :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])
    interval = Keyword.get(opts, :interval_ms, configured_interval())
    {:ok, schedule(%{interval: interval})}
  end

  @impl true
  def handle_info(:flush, state) do
    log_failure(flush())
    {:noreply, schedule(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state) do
    log_failure(flush())
    :ok
  end

  defp schedule(%{interval: interval} = state) when is_integer(interval) do
    Process.send_after(self(), :flush, interval)
    state
  end

  defp schedule(state), do: state

  defp configured_interval do
    :cadence
    |> Application.get_env(:source_watermark_coalescing, [])
    |> Keyword.get(:interval_ms, @default_interval_ms)
  end

  defp log_failure(:ok), do: :ok

  defp log_failure({:error, reason}),
    do: Logger.error("source watermark flush failed, entries kept: #{inspect(reason)}")

  # Lock-free merge: a compare-and-swap on the entry's version, so concurrent writers to one row
  # lose nothing. A flush takes the entry, which fails the swap and recreates it on the retry.
  defp merge_into(key, mission_id, attrs) do
    case :ets.lookup(@table, key) do
      [{^key, version, _mission_id, current}] ->
        next = merge(current, attrs)

        swapped =
          :ets.select_replace(@table, [
            {{:"$1", version, :"$2", :"$3"}, [{:==, :"$1", {:const, key}}],
             [{{:"$1", version + 1, :"$2", {:const, next}}}]}
          ])

        if swapped == 1, do: :ok, else: merge_into(key, mission_id, attrs)

      [] ->
        if :ets.insert_new(@table, {key, 0, mission_id, attrs}),
          do: :ok,
          else: merge_into(key, mission_id, attrs)
    end
  end

  defp flush(scope) do
    if :ets.whereis(@table) == :undefined do
      :ok
    else
      case locked_write(scope) do
        {:ok, :ok} -> :ok
        {:ok, {:error, reason}} -> {:error, reason}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp locked_write(scope) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_key])
      entries = take(scope)
      write(entries)
    end)
  end

  defp write([]), do: :ok

  defp write(entries) do
    entries
    |> Enum.group_by(fn {{_row_key, bus, publish?}, _version, _mission_id, _attrs} ->
      {bus, publish?}
    end)
    |> Enum.reduce_while(:ok, fn {{bus, publish?}, group}, :ok ->
      case record(group, bus, publish?) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          Enum.each(group, &restore/1)
          {:halt, {:error, reason}}
      end
    end)
  end

  defp record(group, bus, publish?) do
    opts = [publish_facts?: publish?] ++ if(bus, do: [event_bus: bus], else: [])
    attributes = Enum.map(group, fn {_key, _version, _mission_id, attrs} -> attrs end)

    case Watermarks.record_source_watermarks(attributes, opts) do
      {:ok, _results} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # A window taken for a failed write is merged back before anything newer, keeping its order.
  defp restore({key, _version, mission_id, attrs}) do
    case :ets.lookup(@table, key) do
      [{^key, _v, _m, newer}] ->
        :ets.delete(@table, key)
        merge_into(key, mission_id, merge(attrs, newer))

      [] ->
        merge_into(key, mission_id, attrs)
    end
  end

  defp take(:all), do: take_keys(:ets.select(@table, [{{:"$1", :_, :_, :_}, [], [:"$1"]}]))

  defp take({:key, row_key}) do
    take_keys(
      :ets.select(@table, [
        {{:"$1", :_, :_, :_}, [{:==, {:element, 1, :"$1"}, row_key}], [:"$1"]}
      ])
    )
  end

  defp take({:mission, mission_id}),
    do: take_keys(:ets.select(@table, [{{:"$1", :_, mission_id, :_}, [], [:"$1"]}]))

  defp take_keys(keys), do: Enum.flat_map(keys, &:ets.take(@table, &1))

  defp merge_payload(earlier, later) do
    earlier = earlier || %{}
    later = later || %{}

    Map.merge(later, %{
      kind: later[:kind] || earlier[:kind],
      replay_run_id: later[:replay_run_id] || earlier[:replay_run_id],
      first_sample_id: earlier[:first_sample_id] || later[:first_sample_id],
      last_sample_id: later[:last_sample_id] || earlier[:last_sample_id],
      observation_count: (earlier[:observation_count] || 0) + (later[:observation_count] || 0)
    })
  end

  defp earliest(nil, other), do: other
  defp earliest(other, nil), do: other
  defp earliest(a, b), do: if(DateTime.compare(a, b) == :gt, do: b, else: a)

  defp latest(nil, other), do: other
  defp latest(other, nil), do: other
  defp latest(a, b), do: if(DateTime.compare(a, b) == :lt, do: b, else: a)
end
