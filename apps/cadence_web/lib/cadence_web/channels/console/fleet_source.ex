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

  - **Tick:** every 10 s while anyone is subscribed, a read with `heard_due?` set: the
    heartbeat, and the batch of rows whose only change is `last_received_at`.
  - **Material change:** `note/2` from any subscribed channel. At most one read per second,
    shared by every channel that noted it.
  - **Snapshot:** a new subscriber gets the latest read when it is under a second old.
    Otherwise it waits for the next read, which the source starts at once.
  - **A failing read** (a raise or an exit, e.g. a database error) doesn't crash the source: it
    keeps its subscribers and the last good read, logs once per streak of failures, and tries
    again at the next tick or material change, throttled like any read. Nothing is pushed
    meanwhile, ticks included, so a client sees no heartbeat until reads succeed again.

  The rows are mission-wide; each channel was authorized for the mission at join. If rows ever
  differ by viewer, the channel filters the shared rows by its scope before diffing. The one
  read that stays per socket is `CommandCounts.load/3` (the viewer's `awaiting_viewer`): one
  small query per socket per push, independent of fleet size, and not part of this read's cost.

  The source stops when its last subscriber leaves or exits. It is `:temporary`: should it
  crash anyway, its channels see it go down and subscribe again, which starts a fresh one.
  Sources are per node, so a mission watched from two nodes is read once per node per tick.

  Each read is a `:telemetry` span, `[:cadence_web, :console, :fleet_source, :load]`, with the
  mission id as metadata (`:exception` on a failing read).
  """

  use GenServer, restart: :temporary

  require Logger

  alias Cadence.Reads.FleetStatus
  alias CadenceWeb.Console.FleetJSON

  @registry CadenceWeb.Console.FleetSources
  @supervisor CadenceWeb.Console.FleetSourceSupervisor
  @material_ms 1_000
  @tick_ms 10_000

  @type key :: {organization_id :: binary(), mission_id :: binary()}

  @doc """
  Starts the source for `key: {organization_id, mission_id}`, registered under that key.
  `load` reads the shared fleet (default: `FleetStatus.load/2` and the limits, as wire rows).
  """
  @spec start_link(key: key(), load: (binary(), binary() -> map())) :: GenServer.on_start()
  def start_link(opts) do
    key = Keyword.fetch!(opts, :key)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {@registry, key}})
  end

  @doc """
  Subscribes the calling process. Returns the source's pid (to monitor) and the latest read when
  it is fresh enough to be the caller's snapshot, or `nil`: then the next `{:fleet_loaded, ...}`
  message is.
  """
  @spec subscribe(binary(), binary()) :: {pid(), map() | nil}
  def subscribe(organization_id, mission_id), do: subscribe_to({organization_id, mission_id}, 5)

  @doc "Unsubscribes the calling process."
  @spec unsubscribe(binary(), binary()) :: :ok
  def unsubscribe(organization_id, mission_id),
    do: cast_if_running({organization_id, mission_id}, {:unsubscribe, self()})

  @doc "A material change (alarms, spacecraft, commanding, limits, contacts): a read within a second."
  @spec note(binary(), binary()) :: :ok
  def note(organization_id, mission_id), do: cast_if_running({organization_id, mission_id}, :note)

  # A source can stop between the lookup and the call (its last subscriber had just left): then
  # start a fresh one. Registry drops a dead source's name a moment after it exits, and until
  # then both lookup and start return the dead pid, so wait a little first. A source busy with a
  # read slower than the call's 5 s still adds the caller, so a timeout just means "wait for the
  # next read".
  defp subscribe_to(key, retries) do
    pid = running(key) || start(key)

    try do
      {pid, GenServer.call(pid, {:subscribe, self()})}
    catch
      :exit, {:timeout, _call} ->
        {pid, nil}

      :exit, {reason, _call}
      when reason in [:noproc, :normal, :killed, :shutdown] and retries > 0 ->
        Process.sleep(10)
        subscribe_to(key, retries - 1)
    end
  end

  defp running(key) do
    case Registry.lookup(@registry, key) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  defp start(key) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, key: key}) do
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
  def init(opts) do
    {:ok,
     %{
       key: Keyword.fetch!(opts, :key),
       load: Keyword.get(opts, :load, &read/2),
       subscribers: %{},
       latest: nil,
       loaded_at: nil,
       attempted_at: nil,
       failures: 0,
       load_timer: nil,
       tick_timer: Process.send_after(self(), :tick, @tick_ms)
     }}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    state = watch(state, pid)

    cond do
      fresh?(state) -> {:reply, state.latest, state}
      # While reads fail, a new subscriber waits for the next tick or change like everyone else.
      state.failures > 0 -> {:reply, nil, state}
      true -> {:reply, nil, schedule_load(state, 0)}
    end
  end

  @impl true
  def handle_cast(:note, state), do: {:noreply, schedule_load(state, throttle(state))}

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

  # Material reads, failed ones included, are at least a second apart.
  defp throttle(%{attempted_at: nil}), do: 0
  defp throttle(state), do: max(0, state.attempted_at + @material_ms - now_ms())

  defp schedule_load(%{load_timer: nil} = state, delay),
    do: %{state | load_timer: Process.send_after(self(), :load, delay)}

  defp schedule_load(state, _delay), do: state

  # Any read also answers a material change that was waiting for its throttle window.
  defp load(%{key: {organization_id, mission_id}} = state, heard_due?) do
    if state.load_timer, do: Process.cancel_timer(state.load_timer)
    state = %{state | load_timer: nil, attempted_at: now_ms()}

    case attempt(state.load, organization_id, mission_id) do
      {:ok, shared} ->
        if state.failures > 0,
          do:
            Logger.info("Fleet push for #{mission_id} reads again after #{state.failures} failed")

        Enum.each(Map.keys(state.subscribers), &send(&1, {:fleet_loaded, shared, heard_due?}))
        %{state | latest: shared, loaded_at: now_ms(), failures: 0}

      {:error, reason} ->
        if state.failures == 0,
          do:
            Logger.warning(
              "Fleet push for #{mission_id} couldn't read the fleet; trying again at the next tick or change: #{reason}"
            )

        %{state | failures: state.failures + 1}
    end
  end

  defp attempt(load, organization_id, mission_id) do
    meta = %{mission_id: mission_id}

    shared =
      :telemetry.span([:cadence_web, :console, :fleet_source, :load], meta, fn ->
        {load.(organization_id, mission_id), meta}
      end)

    {:ok, shared}
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, Exception.format_exit(reason)}
  end

  defp read(organization_id, mission_id) do
    fleet = FleetStatus.load(organization_id, mission_id)
    limits_configured? = Cadence.Limits.list_limit_definitions(mission_id) != []
    FleetJSON.mission(fleet, limits_configured?)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
