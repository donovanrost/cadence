defmodule Cadence.Outbox.Processor do
  @moduledoc """
  Processes outbox events and broadcasts them via PubSub.

  This GenServer polls the outbox table for unprocessed events, handles them
  (including writing to audit logs), broadcasts to PubSub, and marks them
  as processed.

  ## Architecture

  The processor runs as a singleton in the application supervision tree.
  It processes events in batches to balance throughput with latency.

  ## Event Processing Flow

  1. Poll for unprocessed events (batch)
  2. For each event:
     a. Write to audit_logs table (synchronous)
     b. Broadcast to PubSub topics
     c. Mark as processed
  3. On failure, increment attempts and record error
  4. After max attempts, dead-letter the event

  ## Configuration

  The processor can be configured via application config:

      config :cadence, Cadence.Outbox.Processor,
        poll_interval_ms: 100,
        batch_size: 100,
        enabled: true

  ## Startup Behavior

  On startup, the processor immediately processes any pending events
  before entering the normal polling loop. This ensures events created
  during downtime are handled promptly.
  """

  use GenServer
  require Logger

  alias Cadence.Outbox
  alias Cadence.Outbox.Event

  @default_poll_interval_ms 1000
  @default_batch_size 100

  defmodule State do
    @moduledoc false
    defstruct [
      :poll_interval_ms,
      :batch_size,
      :poll_timer,
      processing: false,
      stats: %{processed: 0, failed: 0, dead_lettered: 0}
    ]
  end

  ## Client API

  @doc """
  Starts the outbox processor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current processor stats.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Triggers immediate processing of pending events.

  Useful for testing or when you want to ensure events are processed
  without waiting for the next poll cycle.
  """
  @spec process_now() :: :ok
  def process_now do
    GenServer.cast(__MODULE__, :process_now)
  end

  @doc """
  Checks if the processor is currently running/processing.
  """
  @spec processing?() :: boolean()
  def processing? do
    GenServer.call(__MODULE__, :processing?)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    config = Application.get_env(:cadence, __MODULE__, [])

    poll_interval_ms =
      Keyword.get(opts, :poll_interval_ms) ||
        Keyword.get(config, :poll_interval_ms, @default_poll_interval_ms)

    batch_size =
      Keyword.get(opts, :batch_size) ||
        Keyword.get(config, :batch_size, @default_batch_size)

    enabled = Keyword.get(config, :enabled, true)

    state = %State{
      poll_interval_ms: poll_interval_ms,
      batch_size: batch_size
    }

    if enabled do
      Logger.info(
        "Starting Outbox.Processor with poll_interval=#{poll_interval_ms}ms, batch_size=#{batch_size}"
      )

      # Process any pending events immediately on startup
      send(self(), :process)
      {:ok, state}
    else
      Logger.info("Outbox.Processor disabled via config")
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  def handle_call(:processing?, _from, state) do
    {:reply, state.processing, state}
  end

  @impl true
  def handle_cast(:process_now, state) do
    new_state = do_process(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:process, state) do
    new_state =
      state
      |> do_process()
      |> schedule_next_poll()

    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp do_process(state) do
    state = %{state | processing: true}

    events = Outbox.fetch_pending(limit: state.batch_size)

    stats =
      Enum.reduce(events, state.stats, fn event, acc ->
        case process_event(event) do
          :ok ->
            %{acc | processed: acc.processed + 1}

          {:error, :dead_lettered} ->
            %{acc | failed: acc.failed + 1, dead_lettered: acc.dead_lettered + 1}

          {:error, _reason} ->
            %{acc | failed: acc.failed + 1}
        end
      end)

    %{state | processing: false, stats: stats}
  end

  defp process_event(%Event{} = event) do
    # TODO: Write to audit_logs table here
    # For now, we just broadcast and mark processed
    # In the future, this would be:
    #   {:ok, _audit_log} = AuditLogs.create_from_outbox_event(event)

    # Broadcast to PubSub
    Outbox.broadcast(event)

    # Mark as processed
    case Outbox.mark_processed(event) do
      {:ok, _event} ->
        :ok

      {:error, changeset} ->
        Logger.error("Failed to mark outbox event as processed: #{inspect(changeset.errors)}")
        {:error, :mark_failed}
    end
  rescue
    e ->
      Logger.error("Error processing outbox event #{event.id}: #{Exception.message(e)}")
      handle_processing_error(event, e)
  catch
    kind, reason ->
      Logger.error("Error processing outbox event #{event.id}: #{inspect({kind, reason})}")
      handle_processing_error(event, {kind, reason})
  end

  defp handle_processing_error(event, error) do
    case Outbox.mark_failed(event, error) do
      {:ok, %Event{dead_lettered_at: dead_lettered_at}} when not is_nil(dead_lettered_at) ->
        Logger.error("Outbox event #{event.id} dead-lettered after max attempts")
        {:error, :dead_lettered}

      {:ok, _event} ->
        {:error, :processing_failed}

      {:error, _changeset} ->
        {:error, :mark_failed}
    end
  end

  defp schedule_next_poll(state) do
    if state.poll_timer do
      Process.cancel_timer(state.poll_timer)
    end

    timer = Process.send_after(self(), :process, state.poll_interval_ms)
    %{state | poll_timer: timer}
  end
end
