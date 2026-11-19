defmodule CadenceWeb.Console.SpacecraftChannel do
  @moduledoc """
  `spacecraft:<mission_id>:<spacecraft_id>` (M8): live values of the selected points of one
  spacecraft for Investigate B1. Contract: docs/apogee/api/realtime.md.

  The join payload (or a later `points:set`) selects up to 200 points. After each change to the
  mission's telemetry or limits (runtime invalidation), at most once a second, the channel
  re-reads the selected points' latest samples for this spacecraft and pushes `points` with only
  the ones that changed since the last push. The first push after a join or a `points:set`
  carries every selected point that has a sample. `seq` restarts at 1 per join.
  """

  use Phoenix.Channel

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Reads.SpacecraftLive
  alias CadenceWeb.Console.Access

  @throttle_ms 1_000
  @live_boundaries [
    :source_watermark_changed,
    :historical_data_changed,
    :telemetry_revision_state_changed,
    :limit_definition_changed
  ]

  @impl true
  def join("spacecraft:" <> rest, payload, socket) do
    with [mission_id, spacecraft_id] <- String.split(rest, ":", parts: 2),
         {:ok, scope, mission} <- authorize(socket, mission_id),
         {:ok, _spacecraft} <-
           spacecraft(scope.organization_id, mission.mission_id, spacecraft_id),
         {:ok, point_ids} <- point_ids(payload) do
      org = scope.organization_id
      :ok = RuntimeInvalidation.subscribe(%{organization_id: org, mission_id: mission.mission_id})
      send(self(), :push)

      {:ok,
       %{
         spacecraft_id: spacecraft_id,
         mission_id: mission.mission_id,
         points: SpacecraftLive.points(org, mission.mission_id, point_ids)
       },
       assign(socket,
         organization_id: org,
         mission_id: mission.mission_id,
         spacecraft_id: spacecraft_id,
         point_ids: point_ids,
         seq: 0,
         pushed: %{},
         pushed_at: nil,
         timer: nil
       )}
    else
      {:error, reason} when is_atom(reason) -> {:error, %{reason: Atom.to_string(reason)}}
      _other -> {:error, %{reason: "spacecraft_not_found"}}
    end
  end

  @impl true
  def handle_in("points:set", payload, socket) do
    case point_ids(payload) do
      {:ok, point_ids} ->
        send(self(), :push)

        points =
          SpacecraftLive.points(
            socket.assigns.organization_id,
            socket.assigns.mission_id,
            point_ids
          )

        {:reply, {:ok, %{points: points}}, assign(socket, point_ids: point_ids, pushed: %{})}

      {:error, reason} ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  @impl true
  def handle_info({:dashboard_runtime_invalidated, %{boundary: boundary}}, socket)
      when boundary in @live_boundaries,
      do: {:noreply, schedule(socket)}

  def handle_info({:dashboard_runtime_invalidated, _event}, socket), do: {:noreply, socket}

  def handle_info(:push, socket), do: {:noreply, push_changes(assign(socket, timer: nil))}

  def handle_info(_message, socket), do: {:noreply, socket}

  # At most one push a second: push now if the last was long enough ago, else once it is.
  defp schedule(%{assigns: %{timer: timer}} = socket) when timer != nil, do: socket

  defp schedule(socket) do
    wait =
      case socket.assigns.pushed_at do
        nil -> 0
        at -> max(@throttle_ms - (System.monotonic_time(:millisecond) - at), 0)
      end

    assign(socket, timer: Process.send_after(self(), :push, wait))
  end

  defp push_changes(%{assigns: assigns} = socket) do
    latest =
      SpacecraftLive.samples(
        assigns.organization_id,
        assigns.mission_id,
        assigns.spacecraft_id,
        assigns.point_ids
      )

    changed =
      latest
      |> Enum.reject(fn {point_id, sample} -> Map.get(assigns.pushed, point_id) == sample end)
      |> Enum.map(&elem(&1, 1))

    first? = assigns.seq == 0

    if changed == [] and not first? do
      socket
    else
      seq = assigns.seq + 1
      push(socket, "points", %{seq: seq, samples: changed})

      assign(socket,
        seq: seq,
        pushed: latest,
        pushed_at: System.monotonic_time(:millisecond)
      )
    end
  end

  defp authorize(socket, mission_id) do
    case Access.authorize_mission(socket.assigns.console_credentials, mission_id) do
      {:ok, scope, mission} -> {:ok, scope, mission}
      {:error, _reason} -> {:error, :mission_not_found}
    end
  end

  defp spacecraft(org, mission_id, spacecraft_id) do
    case Cadence.SpacecraftStore.fetch_spacecraft(org, mission_id, spacecraft_id) do
      {:ok, spacecraft} -> {:ok, spacecraft}
      _missing -> {:error, :spacecraft_not_found}
    end
  end

  defp point_ids(%{"point_ids" => ids}) when is_list(ids) do
    ids = ids |> Enum.filter(&is_binary/1) |> Enum.uniq()

    if length(ids) > SpacecraftLive.max_points(),
      do: {:error, :too_many_points},
      else: {:ok, ids}
  end

  defp point_ids(_payload), do: {:ok, []}
end
