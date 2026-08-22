defmodule Cadence.GroundNetworks.ProviderEventProcessor do
  @moduledoc "Bounded durable inbox processor that triggers authoritative reservation reads."

  use GenServer

  alias Cadence.Control.Contacts.ProviderEvents
  alias Cadence.GroundNetworks.{ProviderEventInbox, ProviderEventInboxEntry}

  @default_process_interval_ms 1_000
  @default_max_concurrency 4
  @default_claim_limit 50

  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec process_now(GenServer.server()) :: {:ok, map()}
  def process_now(server \\ __MODULE__), do: GenServer.call(server, :process_now, :infinity)

  @spec process_once(keyword()) :: {:ok, map()} | {:error, term()}
  def process_once(opts \\ []) do
    worker_ref = Keyword.get(opts, :worker_ref, default_worker_ref())

    with {:ok, entries} <-
           ProviderEventInbox.claim(worker_ref,
             limit: Keyword.get(opts, :limit, @default_claim_limit),
             now: now(opts),
             processing_timeout_ms: Keyword.get(opts, :processing_timeout_ms, 60_000)
           ) do
      results =
        entries
        |> Task.async_stream(
          &process_entry(&1, opts),
          max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
          ordered: false,
          timeout: :infinity
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> {:error, {:provider_event_process_task_exit, reason}}
        end)

      {:ok, summarize(results)}
    end
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :process_interval_ms, @default_process_interval_ms)
    schedule_process(interval)
    {:ok, %{interval: interval, process_opts: Keyword.delete(opts, :name)}}
  end

  @impl true
  def handle_call(:process_now, _from, state) do
    result = process_once(state.process_opts)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:process, state) do
    _result = process_once(state.process_opts)
    schedule_process(state.interval)
    {:noreply, state}
  end

  defp process_entry(%ProviderEventInboxEntry{resource_type: resource_type} = entry, opts)
       when resource_type in ["contact", "delivery"] do
    with {:ok, resolution} <- ProviderEvents.reconcile_provider_event(entry, opts),
         {:ok, processed} <-
           ProviderEventInbox.complete(entry, resolution, now: now(opts)) do
      {:ok, processed}
    else
      {:quarantine, reason} ->
        quarantine(entry, reason, opts)

      {:retry, reason} ->
        retry(entry, reason, opts)

      {:error, :injected_after_domain_commit} = injected ->
        injected

      {:error, reason} ->
        retry(entry, reason, opts)
    end
  end

  defp process_entry(%ProviderEventInboxEntry{} = entry, opts) do
    case ProviderEventInbox.complete(entry, %{}, now: now(opts)) do
      {:ok, processed} -> {:ok, processed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp retry(entry, reason, opts) do
    case ProviderEventInbox.retry(entry, reason, now: now(opts)) do
      {:ok, retried} -> {:retry, retried, reason}
      {:error, persistence_reason} -> {:error, {reason, persistence_reason}}
    end
  end

  defp quarantine(entry, reason, opts) do
    case ProviderEventInbox.quarantine(entry, reason, now: now(opts)) do
      {:ok, quarantined} -> {:quarantined, quarantined, reason}
      {:error, persistence_reason} -> {:error, {reason, persistence_reason}}
    end
  end

  defp summarize(results) do
    Enum.reduce(
      results,
      %{
        claimed: length(results),
        processed: 0,
        retried: 0,
        quarantined: 0,
        errors: 0,
        results: results
      },
      fn
        {:ok, _entry}, acc -> %{acc | processed: acc.processed + 1}
        {:retry, _entry, _reason}, acc -> %{acc | retried: acc.retried + 1}
        {:quarantined, _entry, _reason}, acc -> %{acc | quarantined: acc.quarantined + 1}
        {:error, _reason}, acc -> %{acc | errors: acc.errors + 1}
      end
    )
  end

  defp default_worker_ref,
    do: "provider-event-processor:#{System.unique_integer([:positive])}"

  defp schedule_process(interval), do: Process.send_after(self(), :process, interval)

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
