defmodule CadenceWeb.Console.FleetPush do
  @moduledoc """
  The opt-in `fleet` push for `CadenceWeb.Console.MissionChannel`.

  After the client sends `fleet:subscribe`, the channel replies `ok` at once and then pushes one
  full snapshot (`full: true`, `seq: 1`), and then deltas with `seq` increasing by one per push.
  Rows are full `GET /fleet` rows and replace the client's row by `id`. Contract:
  `docs/apogee/api/realtime.md`.

  The fleet itself is read once per mission by `CadenceWeb.Console.FleetSource` (#797), not per
  socket. The source owns the timing: material changes (state, limits, worst point, profile,
  geometry, the `stale` flag) arrive within about a second of an `alarms`, `spacecraft`,
  `commanding`, `limits` or `contacts` change, and a tick every 10 s batches rows whose only
  change is `last_received_at` into the `heard` map. The tick always pushes, possibly with no
  rows, so it doubles as a heartbeat. This module keeps what is per socket: `seq`, the rows last
  pushed, the diff, and the viewer's command counts.

  The `:fleet` assign is `nil` (off); `:pending` (subscribed, the subscription to the source
  queued so the reply never waits on it); or a map with the source's monitor ref, `seq` and
  `rows`. `seq` is 0 while waiting for the source's first load, which becomes the snapshot.

  The viewer's command counts come with each load: the source reads the mission's commands once
  and builds each subscribed viewer's counts (#798), so a push never queries per socket.
  """

  alias CadenceWeb.Console.FleetSource
  alias Phoenix.{Channel, Socket}

  @material_resources ~w(alarms spacecraft commanding limits contacts)

  @type message ::
          :fleet_snapshot
          | {:fleet_loaded, map(), map(), boolean()}
          | {:DOWN, reference(), :process, pid(), term()}

  @spec join(Socket.t()) :: Socket.t()
  def join(socket), do: Socket.assign(socket, :fleet, nil)

  @doc """
  Starts the push: queues the subscription to the source (`:fleet_snapshot`, handled after the
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

  @spec unsubscribe(Socket.t()) :: Socket.t()
  def unsubscribe(%Socket{assigns: %{fleet: %{source: ref}}} = socket) do
    Process.demonitor(ref, [:flush])
    FleetSource.unsubscribe(socket.assigns.organization_id, socket.assigns.mission_id)
    Socket.assign(socket, :fleet, nil)
  end

  # A queued subscription is then dropped (handle/2 sees nil).
  def unsubscribe(%Socket{assigns: %{fleet: :pending}} = socket),
    do: Socket.assign(socket, :fleet, nil)

  def unsubscribe(socket), do: socket

  @doc "Tells the mission's source about a change when `resource` affects the fleet."
  @spec note(Socket.t(), binary()) :: Socket.t()
  def note(%Socket{assigns: %{fleet: %{}}} = socket, resource)
      when resource in @material_resources do
    FleetSource.note(socket.assigns.organization_id, socket.assigns.mission_id)
    socket
  end

  def note(socket, _resource), do: socket

  @doc """
  Handles the push's own messages: the queued subscription, the source's loads, and the source
  going down (then the channel subscribes again and carries on from its `seq`).
  """
  @spec handle(message(), Socket.t()) :: Socket.t()
  def handle(:fleet_snapshot, %Socket{assigns: %{fleet: :pending}} = socket),
    do: follow(socket, %{seq: 0, rows: %{}})

  # Unsubscribed before it ran, or already following: nothing to do.
  def handle(:fleet_snapshot, socket), do: socket

  def handle(
        {:fleet_loaded, shared, commands, _heard_due?},
        %Socket{assigns: %{fleet: %{seq: 0}}} = socket
      ),
      do: start(socket, shared, commands)

  def handle(
        {:fleet_loaded, shared, commands, heard_due?},
        %Socket{assigns: %{fleet: %{}}} = socket
      ),
      do: refresh(socket, shared, commands, heard_due?)

  def handle(
        {:DOWN, ref, :process, _pid, _reason},
        %Socket{assigns: %{fleet: %{source: ref}}} = socket
      ),
      do: follow(socket, Map.take(socket.assigns.fleet, [:seq, :rows]))

  # A load that was already on its way when the socket unsubscribed.
  def handle(_message, socket), do: socket

  # Subscribes to the mission's source and starts at once when it has a fresh load to share.
  defp follow(socket, position) do
    {source, latest} =
      FleetSource.subscribe(
        socket.assigns.organization_id,
        socket.assigns.mission_id,
        viewer(socket)
      )

    socket = Socket.assign(socket, :fleet, Map.put(position, :source, Process.monitor(source)))

    case {latest, position.seq} do
      {nil, _seq} -> socket
      {{shared, commands}, 0} -> start(socket, shared, commands)
      {{shared, commands}, _seq} -> refresh(socket, shared, commands, false)
    end
  end

  # The full snapshot (seq 1).
  defp start(socket, shared, commands) do
    snapshot = Map.put(shared, :commands, commands)

    Channel.push(
      socket,
      "fleet",
      Map.merge(snapshot, %{seq: 1, full: true, heard: %{}, removed: []})
    )

    update_fleet(
      socket,
      &%{&1 | seq: 1, rows: Map.new(snapshot.spacecraft, fn row -> {row.id, row} end)}
    )
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

  defp refresh(%Socket{assigns: %{fleet: fleet}} = socket, shared, commands, heard_due?) do
    {changed, heard, removed, rows} = diff(fleet.rows, shared.spacecraft, heard_due?)

    if changed == [] and heard == %{} and removed == [] and not heard_due? do
      socket
    else
      seq = fleet.seq + 1

      payload =
        shared
        |> Map.put(:commands, commands)
        |> Map.merge(%{
          seq: seq,
          full: false,
          spacecraft: changed,
          heard: heard,
          removed: removed
        })

      Channel.push(socket, "fleet", payload)
      update_fleet(socket, &%{&1 | seq: seq, rows: rows})
    end
  end

  # The viewer whose command counts this socket shows (`awaiting_viewer` leaves out their own).
  defp viewer(%Socket{assigns: %{scope: scope}}), do: scope.user && scope.user.user_id

  defp update_fleet(socket, fun), do: Socket.assign(socket, :fleet, fun.(socket.assigns.fleet))
end
