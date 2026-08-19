defmodule CadenceSimulator.Provider.Orchestrator do
  @moduledoc """
  Advances legacy reservations and Provider Contract v1 Contact lifecycles.

  Reconciliation is deliberately idempotent so restart recovery and manual
  test clocks exercise the same path as the periodic runtime tick.
  """

  use GenServer

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{ContactLifecycle, ContactResults, Contacts}
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

    {:ok,
     %{
       tick_ms: tick_ms,
       streams: %{},
       provider_defaults: Keyword.get(opts, :provider_defaults, [])
     }}
  end

  @impl true
  def handle_call({:reconcile, now}, _from, state) do
    {:reply, :ok, reconcile_all(state, now)}
  end

  def handle_call(:active_stream_count, _from, state) do
    {:reply, map_size(state.streams), state}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick(state.tick_ms)
    {:noreply, reconcile_all(state, DateTime.utc_now())}
  end

  def handle_info({:DOWN, reference, :process, pid, reason}, state) do
    case Enum.find(state.streams, fn {_id, stream} ->
           stream.pid == pid and stream.reference == reference
         end) do
      {resource_id, %{resource_type: :contact}} ->
        maybe_fail_contact_delivery(resource_id, reason)
        {:noreply, %{state | streams: Map.delete(state.streams, resource_id)}}

      {resource_id, _stream} ->
        maybe_fail_active_reservation(resource_id, reason)
        {:noreply, %{state | streams: Map.delete(state.streams, resource_id)}}

      nil ->
        {:noreply, state}
    end
  end

  defp reconcile_all(state, now) do
    state
    |> reconcile_reservations(now)
    |> reconcile_contacts(now)
    |> stop_orphaned_streams()
  end

  defp reconcile_reservations(state, now) do
    Provider.list_reservations()
    |> Enum.reduce(state, fn reservation, acc ->
      reconcile_reservation_for_run(acc, reservation, now)
    end)
  end

  defp reconcile_contacts(state, now) do
    Contacts.list_internal()
    |> Enum.reduce(state, fn contact, acc -> reconcile_contact_for_run(acc, contact, now) end)
  end

  defp reconcile_contact_for_run(state, contact, now) do
    with false <- Contacts.terminal_status?(contact["status"]),
         {:ok, %{"state" => "completed"}} <- Provider.fetch_run(contact["run_id"]) do
      {state, stats} = stop_stream_with_stats(state, contact["id"])
      ended_at = DateTime.to_iso8601(now)

      changes = %{
        "status" => "canceled",
        "status_reason" => "simulation_run_stopped",
        "pass_phase" => "closed",
        "actual_loss_at" => ended_at,
        "delivery" => end_delivery(contact["delivery"]),
        "result" =>
          ContactResults.build(
            Map.merge(contact, %{"actual_loss_at" => ended_at}),
            stats,
            "canceled"
          )
      }

      {:ok, _updated} = ContactLifecycle.update(contact, changes)
      state
    else
      _other -> reconcile_contact(state, contact, now)
    end
  end

  defp reconcile_contact(state, %{"status" => "pending"} = contact, _now) do
    with {:ok, %{"state" => "running"}} <- Provider.fetch_run(contact["run_id"]) do
      {:ok, _updated} = ContactLifecycle.update(contact, %{"status" => "confirmed"})
    end

    state
  end

  defp reconcile_contact(state, %{"status" => "confirmed"} = contact, now) do
    case confirmed_contact_context(contact, now) do
      {:ok, run, starts_at, current} ->
        reconcile_confirmed_contact(state, contact, run, starts_at, current)

      :wait ->
        state
    end
  end

  defp reconcile_contact(state, %{"status" => "active"} = contact, now) do
    case active_contact_context(contact, now) do
      {:ok, run, starts_at, ends_at, current} ->
        reconcile_active_contact(state, contact, run, starts_at, ends_at, current)

      :wait ->
        state
    end
  end

  defp reconcile_contact(state, contact, _now) do
    if Contacts.terminal_status?(contact["status"]),
      do: stop_stream(state, contact["id"]),
      else: state
  end

  defp confirmed_contact_context(contact, now) do
    with {:ok, run} <- Provider.fetch_run(contact["run_id"]),
         true <- run["state"] == "running",
         {:ok, starts_at} <- parse_time(contact["starts_at"]) do
      {:ok, run, starts_at, effective_now(run, now)}
    else
      _other -> :wait
    end
  end

  defp reconcile_confirmed_contact(state, contact, run, starts_at, current) do
    prepass_at = DateTime.add(starts_at, -@acquisition_lead_seconds)

    cond do
      contact["pass_phase"] == "scheduled" and DateTime.compare(current, prepass_at) != :lt ->
        delivery = acquisition_delivery(run, contact)

        {:ok, _updated} =
          ContactLifecycle.update(contact, %{"pass_phase" => "prepass", "delivery" => delivery})

        state

      contact["pass_phase"] == "prepass" and DateTime.compare(current, starts_at) != :lt ->
        activate_contact(state, contact, run, current)

      true ->
        state
    end
  end

  defp acquisition_delivery(run, contact) do
    if fault?(run, contact, "acquisition_failure_rate", :acquisition) do
      contact["delivery"]
      |> Map.put("status", "failed")
      |> Map.put("reason", "simulated_acquisition_failure")
    else
      Map.put(contact["delivery"], "status", "ready")
    end
  end

  defp active_contact_context(contact, now) do
    with {:ok, run} <- Provider.fetch_run(contact["run_id"]),
         {:ok, starts_at} <- parse_time(contact["starts_at"]),
         {:ok, ends_at} <- parse_time(contact["ends_at"]) do
      {:ok, run, starts_at, ends_at, effective_now(run, now)}
    else
      _other -> :wait
    end
  end

  defp reconcile_active_contact(state, contact, run, starts_at, ends_at, current) do
    midpoint = DateTime.add(starts_at, div(DateTime.diff(ends_at, starts_at), 2))
    postpass_at = DateTime.add(ends_at, -1)

    cond do
      run["state"] != "running" ->
        state

      DateTime.compare(current, ends_at) != :lt ->
        complete_contact(state, contact, current)

      postpass?(contact, current, postpass_at) ->
        {:ok, _updated} = ContactLifecycle.update(contact, %{"pass_phase" => "postpass"})
        state

      delivery_connecting?(contact) ->
        delivery = Map.put(contact["delivery"], "status", "flowing")
        {:ok, _updated} = ContactLifecycle.update(contact, %{"delivery" => delivery})
        state

      early_termination?(run, contact, current, midpoint) ->
        fail_active_delivery(state, contact)

      true ->
        state
    end
  end

  defp postpass?(contact, current, postpass_at) do
    contact["pass_phase"] == "pass" and DateTime.compare(current, postpass_at) != :lt
  end

  defp delivery_connecting?(contact) do
    get_in(contact, ["delivery", "status"]) in ["connected", "ready"]
  end

  defp early_termination?(run, contact, current, midpoint) do
    DateTime.compare(current, midpoint) != :lt and
      get_in(contact, ["delivery", "status"]) not in ["failed", "ended"] and
      fault?(run, contact, "early_termination_rate", :early_termination)
  end

  defp fail_active_delivery(state, contact) do
    {state, _stats} = stop_stream_with_stats(state, contact["id"])

    delivery =
      contact["delivery"]
      |> Map.put("status", "failed")
      |> Map.put("reason", "simulated_link_termination")

    {:ok, _updated} = ContactLifecycle.update(contact, %{"delivery" => delivery})
    state
  end

  defp activate_contact(state, contact, run, current) do
    base_changes = %{
      "status" => "active",
      "pass_phase" => "pass",
      "actual_acquisition_at" => DateTime.to_iso8601(current)
    }

    if get_in(contact, ["delivery", "status"]) == "failed" do
      {:ok, _updated} = ContactLifecycle.update(contact, base_changes)
      state
    else
      case start_contact_stream(state, contact, run) do
        {:ok, state} ->
          delivery = Map.put(contact["delivery"], "status", "connected")

          {:ok, _updated} =
            ContactLifecycle.update(contact, Map.put(base_changes, "delivery", delivery))

          state

        {:error, reason} ->
          delivery =
            contact["delivery"]
            |> Map.put("status", "failed")
            |> Map.put("reason", "data_plane_start_failed:#{inspect(reason)}")

          {:ok, _updated} =
            ContactLifecycle.update(contact, Map.put(base_changes, "delivery", delivery))

          state
      end
    end
  end

  defp complete_contact(state, contact, current) do
    {state, stats} = stop_stream_with_stats(state, contact["id"])
    ended_at = DateTime.to_iso8601(current)
    contact_with_loss = Map.put(contact, "actual_loss_at", ended_at)

    changes = %{
      "status" => "completed",
      "pass_phase" => "closed",
      "actual_loss_at" => ended_at,
      "delivery" => end_delivery(contact["delivery"]),
      "result" => ContactResults.build(contact_with_loss, stats, "completed")
    }

    {:ok, _updated} = ContactLifecycle.update(contact, changes)
    state
  end

  defp start_contact_stream(state, contact, run) do
    case Map.get(state.streams, contact["id"]) do
      %{pid: pid} when is_pid(pid) ->
        {:ok, state}

      nil ->
        profile = contact["delivery_profile_snapshot"]
        target = profile["target"] || %{}
        framing = profile["framing"] || %{}

        data_plane = %{
          "host" => target["host"],
          "port" => target["port"],
          "tm_frame_size" => framing["frame_bytes"],
          "target_id" => contact["spacecraft_ref"]
        }

        maybe_start_stream(state, contact, run, data_plane, :contact)
    end
  end

  defp end_delivery(%{"status" => "failed"} = delivery), do: delivery
  defp end_delivery(delivery), do: Map.put(delivery, "status", "ended")

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
        maybe_start_stream(
          state,
          reservation,
          run,
          reservation["data_plane"] || %{},
          :reservation
        )
    end
  end

  defp maybe_start_stream(state, _reservation, _run, %{} = data_plane, _resource_type)
       when map_size(data_plane) == 0,
       do: {:ok, state}

  defp maybe_start_stream(state, reservation, run, data_plane, resource_type) do
    with {:ok, opts} <-
           stream_options(data_plane, reservation, run, state.provider_defaults),
         {:ok, pid} <- CadenceSimulator.start_simulator(opts) do
      reference = Process.monitor(pid)
      stream = %{pid: pid, reference: reference, resource_type: resource_type}
      {:ok, %{state | streams: Map.put(state.streams, reservation["id"], stream)}}
    end
  end

  defp stream_options(data_plane, reservation, run, provider_defaults) do
    telemetry_profile = run["scenario_snapshot"]["telemetry_profile"]
    definitions_path = resolve_definitions_path(data_plane, telemetry_profile, provider_defaults)

    with definitions_path when is_binary(definitions_path) <- definitions_path,
         host when is_binary(host) <- data_plane["host"],
         port when is_integer(port) and port > 0 <- data_plane["port"] do
      frame_size = Map.get(data_plane, "tm_frame_size", 1115)
      fault_profile = run["scenario_snapshot"]["fault_profile"]

      {:ok,
       [
         target_id:
           Map.get(
             data_plane,
             "target_id",
             reservation["spacecraft_id"] || reservation["spacecraft_ref"]
           ),
         definitions_path: definitions_path,
         provider: DatabaseDynamics,
         provider_opts: [noise_amplitude: Map.get(telemetry_profile, "noise_amplitude", 1.0)],
         output: {:tcp, host, port},
         rate_hz: Map.get(telemetry_profile, "rate_hz", 1.0),
         frame: %{
           format: :tm,
           frame_size: frame_size,
           scid: Map.get(data_plane, "scid", 0),
           vcid: Map.get(data_plane, "vcid", 0),
           fecf: Map.get(data_plane, "fecf", false)
         },
         parallel_mode: :parallel,
         generator_count: Map.get(data_plane, "generator_count", 1),
         fault_profile: fault_profile
       ]}
    else
      _other -> {:error, :invalid_data_plane_configuration}
    end
  end

  defp resolve_definitions_path(data_plane, telemetry_profile, provider_defaults) do
    data_plane["definitions_path"] ||
      telemetry_profile["definitions_path"] ||
      Keyword.get(provider_defaults, :definitions_path)
  end

  defp stop_stream(state, reservation_id) do
    {state, _stats} = stop_stream_with_stats(state, reservation_id)
    state
  end

  defp stop_stream_with_stats(state, reservation_id) do
    case Map.pop(state.streams, reservation_id) do
      {nil, _streams} ->
        {state, %{}}

      {%{pid: pid, reference: reference}, streams} ->
        stats = if Process.alive?(pid), do: CadenceSimulator.simulator_stats(pid), else: %{}
        Process.demonitor(reference, [:flush])
        if Process.alive?(pid), do: CadenceSimulator.stop_simulator(pid)
        {%{state | streams: streams}, stats}
    end
  end

  defp stop_orphaned_streams(state) do
    active_reservation_ids =
      Provider.list_reservations(%{"status" => "active"})
      |> Enum.map(& &1["id"])

    active_contact_ids =
      Contacts.list_internal(%{"status" => "active"})
      |> Enum.map(& &1["id"])

    active_ids = MapSet.new(active_reservation_ids ++ active_contact_ids)

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

  defp maybe_fail_contact_delivery(contact_id, reason) do
    case Contacts.fetch_internal(contact_id) do
      {:ok, %{"status" => "active"} = contact} ->
        delivery =
          contact["delivery"]
          |> Map.put("status", "failed")
          |> Map.put("reason", "telemetry_stream_stopped:#{inspect(reason)}")

        ContactLifecycle.update(contact, %{"delivery" => delivery})

      _other ->
        :ok
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
