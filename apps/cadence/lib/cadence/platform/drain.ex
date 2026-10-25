defmodule Cadence.Platform.Drain do
  @moduledoc "Bounded, irreversible process draining shared by release hooks and OTP shutdown."
  use GenServer
  require Logger

  @default_timeout_ms 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  # Reset only when the application starts, never when this worker restarts.
  def reset(server \\ __MODULE__), do: :persistent_term.erase({__MODULE__, server})

  def draining?(server \\ __MODULE__),
    do: :persistent_term.get({__MODULE__, server}, false)

  def run(opts \\ []), do: run(__MODULE__, opts)
  def run(server, opts), do: GenServer.call(server, {:drain, opts}, :infinity)
  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    name = Keyword.get(opts, :name, __MODULE__)
    result = if draining?(name), do: {:error, :drain_worker_restarted}

    {:ok,
     %{
       name: name,
       callback: Keyword.fetch!(opts, :callback),
       status: if(result, do: :failed, else: :active),
       result: result,
       worker: nil,
       timer: nil,
       waiters: [],
       started_at: nil,
       duration_ms: nil
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, Map.take(state, [:status, :result, :duration_ms]), state}
  end

  def handle_call({:drain, _opts}, _from, %{result: result} = state) when not is_nil(result),
    do: {:reply, result, state}

  def handle_call({:drain, _opts}, from, %{status: :draining} = state),
    do: {:noreply, %{state | waiters: [from | state.waiters]}}

  def handle_call({:drain, opts}, from, state) do
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    delay = Keyword.get(opts, :settle_ms, 0)

    if is_integer(timeout) and timeout > 0 and is_integer(delay) and delay >= 0 and
         delay < timeout do
      :persistent_term.put({__MODULE__, state.name}, true)
      parent = self()
      callback = state.callback

      worker =
        spawn_monitor(fn ->
          Process.sleep(delay)
          result = invoke(callback)
          send(parent, {:drain_result, self(), result})
        end)

      timer = Process.send_after(self(), {:drain_deadline, elem(worker, 1)}, timeout)
      Logger.info("Cadence drain started timeout_ms=#{timeout} settle_ms=#{delay}")

      {:noreply,
       %{
         state
         | status: :draining,
           worker: worker,
           timer: timer,
           waiters: [from],
           started_at: System.monotonic_time(:millisecond)
       }}
    else
      {:reply, {:error, :invalid_drain_deadline}, state}
    end
  end

  @impl true
  def handle_info({:drain_result, pid, result}, %{worker: {pid, ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish(state, result)}
  end

  def handle_info({:drain_deadline, ref}, %{worker: {pid, ref}} = state) do
    Process.exit(pid, :kill)
    Process.demonitor(ref, [:flush])
    {:noreply, finish(state, {:error, :drain_timeout})}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %{worker: {pid, ref}} = state),
    do: {:noreply, finish(state, {:error, {:drain_worker_exit, reason}})}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{worker: {pid, _ref}}), do: Process.exit(pid, :kill)
  def terminate(_reason, _state), do: :ok

  defp invoke(callback) do
    case callback.() do
      {:ok, _summary} = result -> result
      {:error, _reason} = result -> result
      other -> {:error, {:invalid_drain_result, other}}
    end
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp finish(state, result) do
    Process.cancel_timer(state.timer)
    duration = System.monotonic_time(:millisecond) - state.started_at
    status = if match?({:ok, _}, result), do: :drained, else: :failed

    Logger.log(
      if(status == :drained, do: :info, else: :error),
      "Cadence drain #{status} duration_ms=#{duration} result=#{inspect(result, limit: 30)}"
    )

    :telemetry.execute(
      [:cadence, :lifecycle, :drain],
      %{duration_ms: duration, count: 1},
      %{outcome: status}
    )

    Enum.each(state.waiters, &GenServer.reply(&1, result))

    %{
      state
      | status: status,
        result: result,
        worker: nil,
        timer: nil,
        waiters: [],
        duration_ms: duration
    }
  end
end
