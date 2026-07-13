defmodule CadenceSimulator.Provider.Orchestrator do
  @moduledoc """
  Advances provider reservation lifecycles and owns active telemetry workers.

  Reconciliation is deliberately idempotent so restart recovery and manual
  test clocks exercise the same path as the periodic runtime tick.
  """

  use GenServer

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Providers.DatabaseDynamics

  @tick_ms 100
  @acquisition_lead_seconds 2

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec reconcile(DateTime.t()) :: :ok
  def reconcile(now \\ DateTime.utc_now()) do
    GenServer.call(__MODULE__, {:reconcile, now}, :infinity)
  end

  @spec active_stream_count() :: non_neg_integer()
  def active_stream_count do
    GenServer.call(__MODULE__, :active_stream_count)
  end

  @impl true
  def init(opts) do
    tick_ms = Keyword.get(opts, :tick_ms, @tick_ms)
    schedule_tick(tick_ms)
    {:ok, %{tick_ms: tick_ms, streams: %{}}}
  end

  @impl true
  def handle_call({:reconcile, now}, _from, state) do
    {:reply, :ok, reconcile_reservations(state, now)}
  end

  def handle_call(:active_stream_count, _from, state) do
    {:reply, map_size(state.streams), state}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick(state.tick_ms)
    {:noreply, reconcile_reservations(state, DateTime.utc_now())}
  end

  def handle_info({:DOWN, reference, :process, pid, reason}, state) do
    case Enum.find(state.streams, fn {_id, stream} ->
           stream.pid == pid and stream.reference == reference
         end) do
      {reservation_id, _stream} ->
        maybe_fail_active_reservation(reservation_id, reason)
        {:noreply, %{state | streams: Map.delete(state.streams, reservation_id)}}

      nil ->
        {:noreply, state}
    end
  end

  defp reconcile_reservations(state, now) do
    Provider.list_reservations()
    |> Enum.reduce(state, fn reservation, acc ->
      reconcile_reservation_for_run(acc, reservation, now)
    end)
    |> stop_orphaned_streams()
  end

  defp reconcile_reservation_for_run(state, reservation, now) do
    with false <- Provider.terminal_reservation_status?(reservation["status"]),
         {:ok, %{"state" => "completed"}} <- Provider.fetch_run(reservation["run_id"]) do
      state = stop_stream(state, reservation["id"])
      status = if reservation["status"] == "active", do: "terminated_early", else: "canceled"

      {:ok, _updated} =
        Provider.update_reservation_status(reservation, status, "simulation_run_stopped")

      state
    else
      _other -> reconcile_reservation(state, reservation, now)
    end
  end

  defp reconcile_reservation(state, %{"status" => "pending"} = reservation, _now) do
    {:ok, _updated} = Provider.update_reservation_status(reservation, "scheduled")
    state
  end

  defp reconcile_reservation(state, %{"status" => "scheduled"} = reservation, now) do
    with {:ok, run} <- Provider.fetch_run(reservation["run_id"]),
         true <- run["state"] == "running",
         {:ok, starts_at} <- parse_time(reservation["starts_at"]),
         effective_now = effective_now(run, now),
         true <-
           DateTime.compare(effective_now, DateTime.add(starts_at, -@acquisition_lead_seconds)) !=
             :lt do
      if fault?(run, reservation, "acquisition_failure_rate", :acquisition) do
        {:ok, _updated} =
          Provider.update_reservation_status(
            reservation,
            "failed",
            "simulated_acquisition_failure"
          )

        state
      else
        {:ok, _updated} = Provider.update_reservation_status(reservation, "acquiring")
        state
      end
    else
      _other -> state
    end
  end

  defp reconcile_reservation(state, %{"status" => "acquiring"} = reservation, now) do
    with {:ok, run} <- Provider.fetch_run(reservation["run_id"]),
         true <- run["state"] == "running",
         {:ok, starts_at} <- parse_time(reservation["starts_at"]),
         true <- DateTime.compare(effective_now(run, now), starts_at) != :lt,
         {:ok, state} <- start_stream(state, reservation, run) do
      {:ok, _updated} = Provider.update_reservation_status(reservation, "active")
      state
    else
      {:error, reason} ->
        {:ok, _updated} =
          Provider.update_reservation_status(
            reservation,
            "failed",
            "data_plane_start_failed:#{inspect(reason)}"
          )

        state

      _other ->
        state
    end
  end

  defp reconcile_reservation(state, %{"status" => "active"} = reservation, now) do
    {:ok, run} = Provider.fetch_run(reservation["run_id"])
    {:ok, starts_at} = parse_time(reservation["starts_at"])
    {:ok, ends_at} = parse_time(reservation["ends_at"])
    now = effective_now(run, now)
    midpoint = DateTime.add(starts_at, div(DateTime.diff(ends_at, starts_at), 2))

    cond do
      run["state"] != "running" ->
        state

      DateTime.compare(now, ends_at) != :lt ->
        state = stop_stream(state, reservation["id"])
        {:ok, _updated} = Provider.update_reservation_status(reservation, "completed")
        state

      DateTime.compare(now, midpoint) != :lt and
          fault?(run, reservation, "early_termination_rate", :early_termination) ->
        state = stop_stream(state, reservation["id"])

        {:ok, _updated} =
          Provider.update_reservation_status(
            reservation,
            "terminated_early",
            "simulated_link_termination"
          )

        state

      true ->
        state
    end
  end

  defp reconcile_reservation(state, reservation, _now) do
    if Provider.terminal_reservation_status?(reservation["status"]),
      do: stop_stream(state, reservation["id"]),
      else: state
  end

  defp start_stream(state, reservation, run) do
    case Map.get(state.streams, reservation["id"]) do
      %{pid: pid} when is_pid(pid) ->
        {:ok, state}

      nil ->
        maybe_start_stream(state, reservation, run, reservation["data_plane"] || %{})
    end
  end

  defp maybe_start_stream(state, _reservation, _run, %{} = data_plane)
       when map_size(data_plane) == 0,
       do: {:ok, state}

  defp maybe_start_stream(state, reservation, run, data_plane) do
    with {:ok, opts} <- stream_options(data_plane, reservation, run),
         {:ok, pid} <- CadenceSimulator.start_simulator(opts) do
      reference = Process.monitor(pid)
      stream = %{pid: pid, reference: reference}
      {:ok, %{state | streams: Map.put(state.streams, reservation["id"], stream)}}
    end
  end

  defp stream_options(data_plane, reservation, run) do
    telemetry_profile = run["scenario_snapshot"]["telemetry_profile"]
    definitions_path = resolve_definitions_path(data_plane, telemetry_profile)

    with definitions_path when is_binary(definitions_path) <- definitions_path,
         host when is_binary(host) <- data_plane["host"],
         port when is_integer(port) and port > 0 <- data_plane["port"] do
      frame_size = Map.get(data_plane, "tm_frame_size", 1115)
      fault_profile = run["scenario_snapshot"]["fault_profile"]

      {:ok,
       [
         target_id: Map.get(data_plane, "target_id", reservation["spacecraft_id"]),
         definitions_path: definitions_path,
         provider: DatabaseDynamics,
         provider_opts: [noise_amplitude: Map.get(telemetry_profile, "noise_amplitude", 1.0)],
         output: {:tcp, host, port},
         rate_hz: Map.get(telemetry_profile, "rate_hz", 1.0),
         frame: %{
           format: :tm,
           frame_size: frame_size,
           scid: Map.get(data_plane, "scid", 0),
           vcid: Map.get(data_plane, "vcid", 0)
         },
         parallel_mode: :parallel,
         generator_count: Map.get(data_plane, "generator_count", 1),
         fault_profile: fault_profile
       ]}
    else
      _other -> {:error, :invalid_data_plane_configuration}
    end
  end

  defp resolve_definitions_path(data_plane, telemetry_profile) do
    data_plane["definitions_path"] ||
      telemetry_profile["definitions_path"] ||
      Application.get_env(:cadence_simulator, :provider_defaults, [])
      |> Keyword.get(:definitions_path)
  end

  defp stop_stream(state, reservation_id) do
    case Map.pop(state.streams, reservation_id) do
      {nil, _streams} ->
        state

      {%{pid: pid, reference: reference}, streams} ->
        Process.demonitor(reference, [:flush])
        if Process.alive?(pid), do: CadenceSimulator.stop_simulator(pid)
        %{state | streams: streams}
    end
  end

  defp stop_orphaned_streams(state) do
    active_ids =
      Provider.list_reservations(%{"status" => "active"})
      |> MapSet.new(& &1["id"])

    Enum.reduce(Map.keys(state.streams), state, fn reservation_id, acc ->
      if MapSet.member?(active_ids, reservation_id),
        do: acc,
        else: stop_stream(acc, reservation_id)
    end)
  end

  defp maybe_fail_active_reservation(reservation_id, reason) do
    with {:ok, reservation} <- Provider.fetch_reservation(reservation_id),
         "active" <- reservation["status"] do
      Provider.update_reservation_status(
        reservation,
        "failed",
        "telemetry_stream_stopped:#{inspect(reason)}"
      )
    else
      _other -> :ok
    end
  end

  defp fault?(run, reservation, key, kind) do
    rate = run["scenario_snapshot"]["fault_profile"][key]
    roll = :erlang.phash2({run["seed"], reservation["id"], kind}, 1_000_000) / 1_000_000
    rate > 0 and roll < rate
  end

  defp parse_time(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> {:error, :invalid_time}
    end
  end

  defp effective_now(run, now) do
    DateTime.add(now, -Map.get(run, "paused_duration_seconds", 0))
  end

  defp schedule_tick(tick_ms), do: Process.send_after(self(), :tick, tick_ms)
end
