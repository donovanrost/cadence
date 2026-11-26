defmodule Cadence.Runtime.PartitionOwner.CurrentValueSeed do
  @moduledoc """
  Seeds the ETS current-value store from the durable history when a partition starts (DECISIONS #96,
  #831). After a node restart the store is empty until each spacecraft's next frame, and at 500+
  craft most are not in contact. A starting owner asks QuestDB, in one statement, for the newest
  value of every (spacecraft, point) its source endpoint has written
  (`LATEST ON observed_at PARTITION BY spacecraft_id, point_id`) and records them
  (`Storage.seed_current_values/3`): each with its OWN generation and receipt time, so the
  staleness rules still say stale; under the stored source identity, so a live value replaces it;
  never over a newer value already there.

  Every point the endpoint ever wrote is covered, not only the parameters a semantic plan
  evaluates; it needs no semantic state, so a partition with no plan seeds too. Measured in CI
  (`docs/apogee/domain/recovery-from-archive.md`): about 4-9 ms per spacecraft at 200 points, flat
  from 50,000 to 400,000 rows, a spacecraft last heard days ago included.

  The read runs in a task, after a random delay of up to `spread_ms` (2 s: 500 partitions starting
  at once do not ask QuestDB at the same instant), so a slow or unreachable QuestDB never delays a
  partition's start; a failure is logged and the store simply fills from ingest, as it always did.
  It runs only when the current-value store is ETS and the history store is QuestDB.
  """

  require Logger

  alias Cadence.Runtime.PartitionKey
  alias Cadence.Telemetry.{CurrentValueStore, HistoryStore, Storage}

  @default_spread_ms 2_000

  @doc """
  Starts the seed for `state`'s partition when it applies. Options: `:history_store_policy`,
  `:spread_ms` (tests pass 0), `:notify` (a pid told `{:current_values_seeded, count}`).
  """
  @spec start(map(), keyword()) :: :ok
  def start(state, opts \\ []) do
    history = Keyword.get_lazy(opts, :history_store_policy, &HistoryStore.configured_policy/0)

    if applies?(state, history), do: spawn_seed(job(state, history), opts)
    :ok
  end

  defp spawn_seed(job, opts) do
    spread = Keyword.get(opts, :spread_ms, @default_spread_ms)
    notify = Keyword.get(opts, :notify)

    {:ok, _pid} =
      Task.start(fn ->
        if spread > 0, do: Process.sleep(:rand.uniform(spread))
        result = seed(job)
        if notify, do: send(notify, {:current_values_seeded, result})
      end)
  end

  defp applies?(
         %{persist_runtime_records?: true, partition_key: %PartitionKey{} = key} = state,
         history
       ) do
    key.affinity == :source_endpoint and is_binary(key.value) and
      match?(%{backend: HistoryStore.QuestDB}, history) and
      match?(
        %{current_value_store_policy: %{backend: CurrentValueStore.ETS}},
        state.persistence_policy.telemetry_storage
      )
  end

  defp applies?(_state, _history), do: false

  defp job(state, history) do
    %{
      mission_id: state.mission_id,
      organization_id: state.active_activation.organization_id,
      source_endpoint_id: state.partition_key.value,
      partition_id: PartitionKey.identifier(state.partition_key),
      storage_policy: state.persistence_policy.telemetry_storage,
      history: history
    }
  end

  @doc false
  @spec seed(map()) :: {:ok, non_neg_integer()} | {:error, term()}
  def seed(job) do
    started = System.monotonic_time()

    with {:ok, samples} <-
           HistoryStore.latest_for_source_endpoint(
             job.history,
             job.mission_id,
             job.source_endpoint_id,
             organization_id: job.organization_id
           ),
         :ok <-
           Storage.seed_current_values(job.storage_policy, samples,
             organization_id: job.organization_id,
             source_endpoint_id: job.source_endpoint_id
           ) do
      :telemetry.execute(
        [:cadence, :runtime, :partition, :current_values_seeded],
        %{
          seeded: length(samples),
          duration_ms:
            System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
        },
        %{mission_id: job.mission_id, partition_id: job.partition_id}
      )

      {:ok, length(samples)}
    else
      {:error, reason} = error ->
        Logger.warning("Current values not seeded from the history store: #{inspect(reason)}",
          mission_id: job.mission_id,
          partition_id: job.partition_id
        )

        error
    end
  rescue
    error ->
      Logger.warning(
        "Current values not seeded from the history store: #{Exception.message(error)}",
        mission_id: job.mission_id,
        partition_id: job.partition_id
      )

      {:error, error}
  end
end
