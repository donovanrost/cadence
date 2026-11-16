defmodule CadenceWeb.Console.FleetPush do
  @moduledoc """
  The opt-in `fleet` push for `CadenceWeb.Console.MissionChannel`.

  After the client sends `fleet:subscribe`, the channel replies `ok` at once and
  then pushes one full snapshot (`full: true`, `seq: 1`), built from a message
  it queues to itself (so the reply never waits on the fleet read), and then
  deltas with `seq` increasing by one per push. The `:fleet` assign is `nil`
  (off), `:pending` (subscribed, snapshot queued) or the push state (a map). Rows are full `GET /fleet` rows and replace the client's row by
  `id`. Material changes (state, limits, worst point, profile, geometry, the
  `stale` flag) are pushed within about a second of an `alarms`,
  `spacecraft`, `commanding` or `limits` change. Rows whose only change is
  `last_received_at` are batched into the `heard` map on the periodic tick
  (every 10 s), which also catches spacecraft going stale without any event
  and doubles as a heartbeat (a tick always pushes, possibly with no rows). Contract: `docs/apogee/api/realtime.md`.
  """

  alias Cadence.Reads.{CommandCounts, FleetStatus}
  alias CadenceWeb.Console.FleetJSON
  alias Phoenix.{Channel, Socket}

  @material_ms 1_000
  @tick_ms 10_000
  @material_resources ~w(alarms spacecraft commanding limits contacts)

  @spec join(Socket.t()) :: Socket.t()
  def join(socket), do: Socket.assign(socket, :fleet, nil)

  @doc """
  Starts the push: queues the full snapshot (`:fleet_snapshot`, handled after the
  reply) and marks the socket `:pending`. Subscribing again is a no-op.
  """
  @spec subscribe(Socket.t()) :: Socket.t()
  def subscribe(%Socket{assigns: %{fleet: fleet}} = socket)
      when fleet == :pending or is_map(fleet),
      do: socket

  def subscribe(socket) do
    send(self(), :fleet_snapshot)
    Socket.assign(socket, :fleet, :pending)
  end

  # The full snapshot (seq 1) and the start of the tick. Anything the channel heard while pending
  # is already in it: the snapshot is read after those messages were handled.
  defp start(socket) do
    snapshot = load(socket)
    rows = snapshot.spacecraft

    Channel.push(
      socket,
      "fleet",
      Map.merge(snapshot, %{seq: 1, full: true, heard: %{}, removed: []})
    )

    Socket.assign(socket, :fleet, %{
      seq: 1,
      rows: Map.new(rows, &{&1.id, &1}),
      pushed_at: now_ms(),
      refresh_timer: nil,
      tick_timer: Process.send_after(self(), :fleet_tick, @tick_ms)
    })
  end

  @spec unsubscribe(Socket.t()) :: Socket.t()
  def unsubscribe(%Socket{assigns: %{fleet: %{} = fleet}} = socket) do
    Enum.each([fleet.refresh_timer, fleet.tick_timer], &(&1 && Process.cancel_timer(&1)))
    Socket.assign(socket, :fleet, nil)
  end

  # A queued snapshot is then dropped (handle/2 sees nil).
  def unsubscribe(%Socket{assigns: %{fleet: :pending}} = socket),
    do: Socket.assign(socket, :fleet, nil)

  def unsubscribe(socket), do: socket

  @doc "Schedules a material refresh (throttled to one per second) when `resource` affects the fleet."
  @spec note(Socket.t(), binary()) :: Socket.t()
  def note(%Socket{assigns: %{fleet: %{refresh_timer: nil} = fleet}} = socket, resource)
      when resource in @material_resources do
    delay = max(0, fleet.pushed_at + @material_ms - now_ms())
    timer = Process.send_after(self(), :fleet_refresh, delay)
    Socket.assign(socket, :fleet, %{fleet | refresh_timer: timer})
  end

  def note(socket, _resource), do: socket

  @doc "Handles the push's own messages: the queued snapshot and its timers."
  @spec handle(:fleet_snapshot | :fleet_refresh | :fleet_tick, Socket.t()) :: Socket.t()
  def handle(:fleet_snapshot, %Socket{assigns: %{fleet: :pending}} = socket), do: start(socket)
  # Unsubscribed before it ran, or already started: nothing to send.
  def handle(:fleet_snapshot, socket), do: socket

  def handle(_message, %Socket{assigns: %{fleet: fleet}} = socket) when not is_map(fleet),
    do: socket

  def handle(:fleet_refresh, socket) do
    socket
    |> update_fleet(&%{&1 | refresh_timer: nil})
    |> refresh(false)
  end

  def handle(:fleet_tick, socket) do
    socket
    |> update_fleet(&%{&1 | tick_timer: Process.send_after(self(), :fleet_tick, @tick_ms)})
    |> refresh(true)
  end

  @doc """
  Diffs wire rows against the last pushed rows. Returns `{changed_rows,
  heard, removed_ids, baseline}`. A row whose only change is
  `last_received_at` goes into `heard` only when `heard_due?`; otherwise the
  baseline keeps its old row so the change is reported on the next tick.
  """
  @spec diff(%{binary() => map()}, [map()], boolean()) ::
          {[map()], %{binary() => DateTime.t() | nil}, [binary()], %{binary() => map()}}
  def diff(baseline, rows, heard_due?) do
    {changed, heard, next} =
      Enum.reduce(rows, {[], %{}, %{}}, fn row, {changed, heard, next} ->
        case classify(Map.get(baseline, row.id), row, heard_due?) do
          {:same, kept} ->
            {changed, heard, Map.put(next, row.id, kept)}

          :heard ->
            {changed, Map.put(heard, row.id, row.last_received_at), Map.put(next, row.id, row)}

          :changed ->
            {[row | changed], heard, Map.put(next, row.id, row)}
        end
      end)

    removed = baseline |> Map.keys() |> Enum.reject(&Map.has_key?(next, &1)) |> Enum.sort()
    {Enum.reverse(changed), heard, removed, next}
  end

  defp classify(nil, _row, _heard_due?), do: :changed
  defp classify(row, row, _heard_due?), do: {:same, row}

  defp classify(old, row, heard_due?) do
    cond do
      not heard_only?(old, row) -> :changed
      heard_due? -> :heard
      true -> {:same, old}
    end
  end

  defp heard_only?(old, row),
    do: Map.delete(old, :last_received_at) == Map.delete(row, :last_received_at)

  defp refresh(%Socket{assigns: %{fleet: fleet}} = socket, heard_due?) do
    snapshot = load(socket)
    {changed, heard, removed, rows} = diff(fleet.rows, snapshot.spacecraft, heard_due?)

    if changed == [] and heard == %{} and removed == [] and not heard_due? do
      socket
    else
      seq = fleet.seq + 1

      payload =
        Map.merge(snapshot, %{
          seq: seq,
          full: false,
          spacecraft: changed,
          heard: heard,
          removed: removed
        })

      Channel.push(socket, "fleet", payload)
      update_fleet(socket, &%{&1 | seq: seq, rows: rows, pushed_at: now_ms()})
    end
  end

  defp load(%Socket{assigns: %{scope: scope, mission_id: mission_id}}) do
    fleet = FleetStatus.load(scope.organization_id, mission_id)
    commands = CommandCounts.load(scope.organization_id, mission_id, scope.user.user_id)
    limits_configured? = Cadence.Limits.list_limit_definitions(mission_id) != []

    FleetJSON.fleet(fleet, commands, limits_configured?)
  end

  defp update_fleet(socket, fun), do: Socket.assign(socket, :fleet, fun.(socket.assigns.fleet))

  defp now_ms, do: System.monotonic_time(:millisecond)
end
