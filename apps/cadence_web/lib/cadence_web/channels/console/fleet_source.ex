defmodule CadenceWeb.Console.FleetSource do
  @moduledoc """
  One fleet read per mission for the live `fleet` push (#797).

  Each subscribed `mission:<id>` channel used to read the whole fleet itself, on its own tick and
  on each material change, so the push cost sockets × fleet size. Now one source per
  `{organization_id, mission_id}` reads it (`FleetStatus.load/2` and whether limits are
  configured, built with `FleetJSON.mission/2`) and sends the result to every subscribed channel
  process as `{:fleet_loaded, shared, heard_due?}`. Each channel adds its viewer's command
  counts, diffs against what it last pushed and pushes its own delta, so `seq`, rows and the
  contract in `docs/apogee/api/realtime.md` stay per socket.

  - **Tick:** every 10 s while anyone is subscribed, a load with `heard_due?` set: the
    heartbeat, and the batch of rows whose only change is `last_received_at`.
  - **Material change:** `note/2` from any subscribed channel. At most one load per second,
    shared by every channel that noted it.
  - **Snapshot:** a new subscriber gets the latest load when it is under a second old.
    Otherwise it waits for the next load, which the source starts at once.

  The rows are mission-wide; each channel was authorized for the mission at join. If rows ever
  differ by viewer, the channel filters the shared rows by its scope before diffing.

  The source stops when its last subscriber leaves or exits. It is `:temporary`: if a load
  crashes it, its channels see it go down and subscribe again, which starts a fresh one. Sources
  are per node, so a mission watched from two nodes is read once per node per tick.

  Each load is a `:telemetry` span, `[:cadence_web, :console, :fleet_source, :load]`, with the
  mission id as metadata.
  """

  use GenServer, restart: :temporary

  alias Cadence.Reads.FleetStatus
  alias CadenceWeb.Console.FleetJSON

  @registry CadenceWeb.Console.FleetSources
  @supervisor CadenceWeb.Console.FleetSourceSupervisor
  @material_ms 1_000
  @tick_ms 10_000

  @type key :: {organization_id :: binary(), mission_id :: binary()}

  @spec start_link(key()) :: GenServer.on_start()
  def start_link(key),
    do: GenServer.start_link(__MODULE__, key, name: {:via, Registry, {@registry, key}})

  @doc """
  Subscribes the calling process. Returns the source's pid (to monitor) and the latest load when
  it is fresh enough to be the caller's snapshot, or `nil`: then the next `{:fleet_loaded, ...}`
  message is.
  """
  @spec subscribe(binary(), binary()) :: {pid(), map() | nil}
  def subscribe(organization_id, mission_id), do: subscribe_to({organization_id, mission_id}, 5)

  @doc "Unsubscribes the calling process."
  @spec unsubscribe(binary(), binary()) :: :ok
  def unsubscribe(organization_id, mission_id),
    do: cast_if_running({organization_id, mission_id}, {:unsubscribe, self()})

  @doc "A material change (alarms, spacecraft, commanding, limits, contacts): a load within a second."
  @spec note(binary(), binary()) :: :ok
  def note(organization_id, mission_id), do: cast_if_running({organization_id, mission_id}, :note)

  # A source can stop between the lookup and the call (its last subscriber had just left, or a
  # load crashed it): then start a fresh one. Registry drops a dead source's name a moment after
  # it exits, and until then both lookup and start return the dead pid, so wait a little first.
  defp subscribe_to(key, retries) do
    pid = running(key) || start(key)
    {pid, GenServer.call(pid, {:subscribe, self()})}
  catch
    :exit, {reason, _call}
    when reason in [:noproc, :normal, :killed, :shutdown] and retries > 0 ->
      Process.sleep(10)
      subscribe_to(key, retries - 1)
  end

  defp running(key) do
    case Registry.lookup(@registry, key) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  defp start(key) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, key}) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  defp cast_if_running(key, message) do
    case running(key) do
      nil -> :ok
      pid -> GenServer.cast(pid, message)
    end
  end

  @impl true
  def init(key) do
    {:ok,
     %{
       key: key,
       subscribers: %{},
       latest: nil,
       loaded_at: nil,
       load_timer: nil,
       tick_timer: Process.send_after(self(), :tick, @tick_ms)
     }}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    state = watch(state, pid)

    if fresh?(state),
      do: {:reply, state.latest, state},
      else: {:reply, nil, schedule_load(state, 0)}
  end

  @impl true
  def handle_cast(:note, state) do
    delay = if state.loaded_at, do: max(0, state.loaded_at + @material_ms - now_ms()), else: 0
    {:noreply, schedule_load(state, delay)}
  end

  def handle_cast({:unsubscribe, pid}, state) do
    case Map.pop(state.subscribers, pid) do
      {nil, _subscribers} ->
        {:noreply, state}

      {ref, subscribers} ->
        Process.demonitor(ref, [:flush])
        stop_when_empty(%{state | subscribers: subscribers})
    end
  end

  @impl true
  def handle_info(:load, state), do: {:noreply, load(%{state | load_timer: nil}, false)}

  def handle_info(:tick, %{subscribers: subscribers} = state) when map_size(subscribers) == 0,
    do: {:stop, :normal, state}

  def handle_info(:tick, state) do
    state = load(state, true)
    {:noreply, %{state | tick_timer: Process.send_after(self(), :tick, @tick_ms)}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: stop_when_empty(%{state | subscribers: Map.delete(state.subscribers, pid)})

  defp watch(%{subscribers: subscribers} = state, pid) when is_map_key(subscribers, pid),
    do: state

  defp watch(state, pid),
    do: %{state | subscribers: Map.put(state.subscribers, pid, Process.monitor(pid))}

  defp stop_when_empty(%{subscribers: subscribers} = state) when map_size(subscribers) == 0,
    do: {:stop, :normal, state}

  defp stop_when_empty(state), do: {:noreply, state}

  defp fresh?(%{loaded_at: nil}), do: false
  defp fresh?(state), do: now_ms() - state.loaded_at < @material_ms

  defp schedule_load(%{load_timer: nil} = state, delay),
    do: %{state | load_timer: Process.send_after(self(), :load, delay)}

  defp schedule_load(state, _delay), do: state

  # Any load also answers a material change that was waiting for its throttle window.
  defp load(%{key: {organization_id, mission_id}} = state, heard_due?) do
    if state.load_timer, do: Process.cancel_timer(state.load_timer)

    shared =
      :telemetry.span(
        [:cadence_web, :console, :fleet_source, :load],
        %{mission_id: mission_id},
        fn ->
          fleet = FleetStatus.load(organization_id, mission_id)
          limits_configured? = Cadence.Limits.list_limit_definitions(mission_id) != []
          {FleetJSON.mission(fleet, limits_configured?), %{mission_id: mission_id}}
        end
      )

    Enum.each(Map.keys(state.subscribers), &send(&1, {:fleet_loaded, shared, heard_due?}))
    %{state | latest: shared, loaded_at: now_ms(), load_timer: nil}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
