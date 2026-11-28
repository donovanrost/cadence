defmodule CadenceWeb.Console.DashboardChannel do
  @moduledoc """
  `dashboard:<mission_id>:<dashboard_id>` (dashboards C1): live pushes for one dashboard.
  Contract: docs/apogee/api/realtime.md §dashboard, docs/apogee/plans/dashboards-live.md.

  - Join `{}`: authorized like D5 (`operate_mission`; the dashboard must be active). Reply
    `{dashboard_id, current_version}`. Joined alone, only `version` events arrive.
  - `view:subscribe` / `view:set` `{runtime: {from, to, spacecraft_id}, refresh_ms}` (1000–60000
    or null for Off) reply `{seq: 0}` and push a `full` view (`seq: 1`, the D5 snapshot). With a
    sliding range and a refresh, the dashboard is re-resolved every `refresh_ms` after the
    previous resolve (as the LiveView's tick does; the cache is invalidated independently), and a
    `view` delta carries only the placements whose DTO changed, the ids that went away and the new
    context. Frozen ranges and Off push nothing more.
  - `view:unsubscribe {}` stops data pushes and stays joined (the editor).
  - `version {current_version, saved_by, saved_at, archived}` goes to every joined client when the
    dashboard is saved, restored or archived elsewhere; a subscriber then gets a `full` view, and
    an archived dashboard stops pushing.
  """

  use Phoenix.Channel

  alias Cadence.Dashboards.{Documents, RuntimeInvalidation}
  alias Cadence.Reads.Dashboards.{Authors, DashboardPage}
  alias CadenceWeb.Console.{Access, ChannelAccess, DashboardRuntime}

  @coalesce_ms 250

  @impl true
  def join("dashboard:" <> rest, _payload, socket) do
    with [mission_id, dashboard_id] <- String.split(rest, ":", parts: 2),
         {:ok, scope, mission} <-
           Access.authorize_mission(socket.assigns.console_credentials, mission_id),
         {:ok, summary} <- active(scope.organization_id, mission.mission_id, dashboard_id) do
      :ok =
        RuntimeInvalidation.subscribe(%{
          organization_id: scope.organization_id,
          mission_id: mission.mission_id,
          dashboard_id: dashboard_id
        })

      {:ok, %{dashboard_id: dashboard_id, current_version: version(summary)},
       assign(socket,
         scope: scope,
         mission_id: mission.mission_id,
         dashboard_id: dashboard_id,
         version: version(summary),
         subscription: nil,
         seq: 0,
         placements: %{},
         tick: nil,
         pending: nil
       )
       |> ChannelAccess.watch()}
    else
      {:error, reason} when reason in [:dashboard_archived, :dashboard_not_found] ->
        {:error, %{reason: Atom.to_string(reason)}}

      {:error, reason} when is_atom(reason) ->
        {:error, %{reason: Atom.to_string(reason)}}

      _other ->
        {:error, %{reason: "dashboard_not_found"}}
    end
  end

  @impl true
  def handle_in(event, %{} = payload, socket) when event in ["view:subscribe", "view:set"] do
    with {:ok, runtime} <- DashboardRuntime.admit(Map.get(payload, "runtime") || %{}),
         {:ok, refresh_ms} <- refresh_ms(Map.get(payload, "refresh_ms")),
         {:ok, view} <- load(socket.assigns, runtime) do
      # Resolved here so a foreign spacecraft is an error reply; the first full view follows.
      send(self(), {:full, view.snapshot})

      socket =
        socket
        |> cancel_tick()
        |> assign(subscription: %{runtime: runtime, refresh_ms: refresh_ms})

      {:reply, {:ok, %{seq: 0}}, socket}
    else
      {:error, :invalid_range} -> invalid(socket, "range")
      {:error, :invalid_scope} -> invalid(socket, "spacecraft_id")
      {:error, :invalid_refresh} -> invalid(socket, "refresh_ms")
      {:error, _unavailable} -> {:reply, {:error, %{reason: "dashboard_unavailable"}}, socket}
    end
  end

  def handle_in("view:unsubscribe", _payload, socket),
    do:
      {:reply, {:ok, %{}}, socket |> cancel_tick() |> assign(subscription: nil, placements: %{})}

  def handle_in(_event, _payload, socket),
    do: {:reply, {:error, %{reason: "unknown_event"}}, socket}

  @impl true
  # The person's access changed (#1153): re-check, and close if it no longer passes.
  def handle_info({:access_changed, _user_id} = message, socket),
    do: ChannelAccess.handle_changed(socket, message)

  def handle_info(:admin_mode_expired, socket),
    do: ChannelAccess.handle_changed(socket, :admin_mode_expired)

  def handle_info({:full, snapshot}, %{assigns: %{subscription: %{}}} = socket),
    do: {:noreply, socket |> push_view(:full, snapshot) |> schedule(snapshot)}

  def handle_info({:full, _snapshot}, socket), do: {:noreply, socket}

  def handle_info(:tick, socket), do: {:noreply, resolve(assign(socket, :tick, nil), :delta)}

  def handle_info({:dashboard_runtime_invalidated, event}, %{assigns: %{pending: nil}} = socket) do
    if relevant?(event, socket.assigns),
      do:
        {:noreply,
         assign(socket, :pending, Process.send_after(self(), :check_version, @coalesce_ms))},
      else: {:noreply, socket}
  end

  def handle_info({:dashboard_runtime_invalidated, _event}, socket), do: {:noreply, socket}

  def handle_info(:check_version, socket),
    do: {:noreply, check_version(assign(socket, :pending, nil))}

  def handle_info(_other, socket), do: {:noreply, socket}

  # Data: a full view (seq 1) or the placements that changed since the last push.
  defp resolve(%{assigns: %{subscription: nil}} = socket, _kind), do: socket

  defp resolve(%{assigns: %{subscription: subscription} = assigns} = socket, kind) do
    case load(assigns, subscription.runtime) do
      {:ok, %{snapshot: snapshot}} -> socket |> push_view(kind, snapshot) |> schedule(snapshot)
      {:error, _reason} -> schedule(socket, nil)
    end
  end

  defp push_view(socket, :full, snapshot) do
    push(socket, "view", %{
      seq: 1,
      full: true,
      version: socket.assigns.version,
      resolved_at: DateTime.utc_now(),
      context: snapshot && snapshot.context,
      snapshot: snapshot,
      placements: [],
      removed: []
    })

    assign(socket, seq: 1, placements: digests(snapshot))
  end

  defp push_view(socket, :delta, nil), do: socket

  defp push_view(socket, :delta, snapshot) do
    current = digests(snapshot)
    previous = socket.assigns.placements

    changed =
      Enum.filter(snapshot.placements, &(Map.get(previous, &1.id) != Map.fetch!(current, &1.id)))

    removed = previous |> Map.keys() |> Enum.reject(&Map.has_key?(current, &1))

    if changed == [] and removed == [] do
      socket
    else
      seq = socket.assigns.seq + 1

      push(socket, "view", %{
        seq: seq,
        full: false,
        version: socket.assigns.version,
        resolved_at: DateTime.utc_now(),
        context: snapshot.context,
        snapshot: nil,
        placements: changed,
        removed: removed
      })

      assign(socket, seq: seq, placements: current)
    end
  end

  # Only a sliding range with a refresh keeps ticking; the next tick follows this resolve.
  defp schedule(%{assigns: %{subscription: %{refresh_ms: ms}}} = socket, snapshot)
       when is_integer(ms) do
    if live?(snapshot),
      do: assign(socket, :tick, Process.send_after(self(), :tick, ms)),
      else: socket
  end

  defp schedule(socket, _snapshot), do: socket

  defp live?(%{context: %{time_mode: "live"}}), do: true
  defp live?(_snapshot), do: false

  # A save, restore or archive elsewhere: tell every joined client, then re-send a full view.
  defp check_version(%{assigns: assigns} = socket) do
    case Documents.fetch_summary(
           assigns.scope.organization_id,
           assigns.mission_id,
           assigns.dashboard_id
         ) do
      {:ok, summary} -> changed(socket, summary, summary.lifecycle_state == "archived")
      {:error, _gone} -> socket
    end
  end

  defp changed(socket, summary, false = _archived) do
    if version(summary) == socket.assigns.version,
      do: socket,
      else: socket |> announce(summary, false) |> cancel_tick() |> resolve(:full)
  end

  defp changed(socket, summary, true = _archived) do
    socket
    |> announce(summary, true)
    |> cancel_tick()
    |> assign(subscription: nil, placements: %{})
  end

  defp announce(socket, summary, archived) do
    push(socket, "version", version_event(summary, archived))
    assign(socket, :version, version(summary))
  end

  defp version_event(summary, archived) do
    saver = summary.published_by

    %{
      current_version: version(summary),
      saved_by:
        saver &&
          summary.organization_id
          |> Authors.members([saver])
          |> Authors.person(saver)
          |> Map.put(:kind, "user"),
      saved_at: summary.published_at || summary.updated_at,
      archived: archived
    }
  end

  defp load(assigns, runtime),
    do: DashboardPage.load(assigns.scope, assigns.mission_id, assigns.dashboard_id, runtime)

  defp active(org, mission, id) do
    case Documents.fetch_summary(org, mission, id) do
      {:ok, %{lifecycle_state: "active"} = summary} -> {:ok, summary}
      {:ok, _archived} -> {:error, :dashboard_archived}
      _missing -> {:error, :dashboard_not_found}
    end
  end

  defp version(summary), do: summary.published_version || summary.latest_version

  defp digests(nil), do: %{}
  defp digests(snapshot), do: Map.new(snapshot.placements, &{&1.id, :erlang.phash2(&1)})

  defp refresh_ms(nil), do: {:ok, nil}
  defp refresh_ms(ms) when is_integer(ms) and ms in 1_000..60_000, do: {:ok, ms}
  defp refresh_ms(_invalid), do: {:error, :invalid_refresh}

  defp invalid(socket, field),
    do: {:reply, {:error, %{reason: "invalid_params", field: field}}, socket}

  defp cancel_tick(%{assigns: %{tick: nil}} = socket), do: socket

  defp cancel_tick(socket) do
    Process.cancel_timer(socket.assigns.tick)
    assign(socket, :tick, nil)
  end

  # Organization- and mission-wide events still apply; another dashboard's don't.
  defp relevant?(%{filters: filters}, assigns) when is_map(filters),
    do: Map.get(filters, :dashboard_id) in [nil, assigns.dashboard_id]

  defp relevant?(_event, _assigns), do: true
end
