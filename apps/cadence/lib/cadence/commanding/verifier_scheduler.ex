defmodule Cadence.Commanding.VerifierScheduler do
  @moduledoc """
  Signal-driven scheduler and safety reconciler for command verifier timeouts.
  """

  use GenServer

  alias Cadence.Commanding
  alias Cadence.Commanding.CommandVerifierInstance

  @default_safety_poll_interval_ms 60_000
  @max_timer_ms 2_147_483_647
  @event_prefix [:cadence, :commanding, :verifier_scheduler]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec notify_verifier_instances_changed(
          CommandVerifierInstance.t()
          | [CommandVerifierInstance.t()]
        ) ::
          :ok
  def notify_verifier_instances_changed(verifier_instances, server \\ __MODULE__)

  def notify_verifier_instances_changed(%CommandVerifierInstance{} = verifier_instance, server) do
    notify_verifier_instances_changed([verifier_instance], server)
  end

  def notify_verifier_instances_changed(verifier_instances, server)
      when is_list(verifier_instances) do
    case server_pid(server) do
      nil ->
        :ok

      pid when is_pid(pid) ->
        GenServer.cast(pid, {:verifier_instances_changed, verifier_instances})
    end
  end

  @spec snapshot(GenServer.server()) :: map()
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  end

  @spec reconcile_now(GenServer.server(), DateTime.t()) ::
          {:ok, [Cadence.Commanding.CommandVerifierInstance.t()]} | {:error, term()}
  def reconcile_now(server \\ __MODULE__, %DateTime{} = reference_time) do
    GenServer.call(server, {:reconcile_now, reference_time}, :infinity)
  end

  @impl true
  def init(opts) do
    state = %{
      safety_poll_interval_ms:
        Keyword.get(opts, :safety_poll_interval_ms, @default_safety_poll_interval_ms),
      auto_schedule?: Keyword.get(opts, :auto_schedule?, true),
      run_on_boot?: Keyword.get(opts, :run_on_boot?, true),
      reference_time_fun: Keyword.get(opts, :reference_time_fun, &DateTime.utc_now/0),
      projection: empty_projection(),
      timeout_timer: nil,
      safety_timer: nil
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    state =
      state
      |> maybe_reconcile_on_boot()
      |> rebuild_projection()
      |> schedule_next_timeout()
      |> schedule_safety_reconcile()

    {:noreply, state}
  end

  @impl true
  def handle_call({:reconcile_now, %DateTime{} = reference_time}, _from, state) do
    {reply, measurements} =
      timed(fn -> Commanding.timeout_command_verifier_instances(reference_time) end)

    emit(:reconcile, state, measurements_for_reconcile(reply, measurements), %{reason: :manual})

    state =
      state
      |> apply_reconcile_result(reply)
      |> rebuild_projection()
      |> schedule_next_timeout()

    {:reply, reply, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot_from_state(state), state}
  end

  @impl true
  def handle_cast({:verifier_instances_changed, verifier_instances}, state)
      when is_list(verifier_instances) do
    emit(:notification, state, %{count: length(verifier_instances)}, %{})

    state =
      state
      |> project_verifier_instances(verifier_instances)
      |> schedule_next_timeout()

    {:noreply, state}
  end

  @impl true
  def handle_info({:timeout_wakeup, token}, state) do
    case state.timeout_timer do
      %{token: ^token} ->
        emit(:timer_fired, state, %{count: 1}, %{})

        state =
          state
          |> clear_timeout_timer()
          |> reconcile_due_timeouts(:timer)
          |> schedule_next_timeout()

        {:noreply, state}

      _stale_or_canceled_timer ->
        emit(:stale_timer, state, %{count: 1}, %{})
        {:noreply, state}
    end
  end

  def handle_info(:safety_reconcile, state) do
    state =
      state
      |> reconcile_due_timeouts(:safety)
      |> rebuild_projection()
      |> schedule_next_timeout()
      |> schedule_safety_reconcile()

    {:noreply, state}
  end

  defp maybe_reconcile_on_boot(%{run_on_boot?: true} = state) do
    reconcile_due_timeouts(state, :boot)
  end

  defp maybe_reconcile_on_boot(state), do: state

  defp reconcile_due_timeouts(state, reason) do
    {reply, measurements} =
      timed(fn ->
        Commanding.timeout_command_verifier_instances(resolve_reference_time(state))
      end)

    event = if reason == :safety, do: :safety_reconcile, else: :reconcile
    emit(event, state, measurements_for_reconcile(reply, measurements), %{reason: reason})

    apply_reconcile_result(state, reply)
  end

  defp apply_reconcile_result(state, {:ok, verifier_instances})
       when is_list(verifier_instances) do
    remove_projected_verifier_instances(state, verifier_instances)
  end

  defp apply_reconcile_result(state, _reply), do: state

  defp rebuild_projection(state) do
    {verifier_instances, measurements} =
      timed(fn -> Commanding.command_verifier_timeout_projection() end)

    projection = projection_from_instances(verifier_instances)

    emit(
      :projection_rebuild,
      state,
      Map.put(measurements, :projected_verifier_count, map_size(projection)),
      %{}
    )

    %{state | projection: projection}
  end

  defp schedule_next_timeout(%{auto_schedule?: false} = state), do: state

  defp schedule_next_timeout(state) do
    case next_projected_timeout(state) do
      nil ->
        cancel_timeout_timer(state)

      %CommandVerifierInstance{} = verifier_instance ->
        schedule_timeout_at(state, verifier_instance)
    end
  end

  defp schedule_timeout_at(
         state,
         %CommandVerifierInstance{timeout_at: %DateTime{} = timeout_at} = verifier_instance
       ) do
    state = cancel_timeout_timer(state)
    token = make_ref()
    delay_ms = delay_ms(timeout_at, resolve_reference_time(state))
    ref = Process.send_after(self(), {:timeout_wakeup, token}, delay_ms)

    emit(:timer_scheduled, state, %{count: 1, delay_ms: delay_ms}, %{
      command_verifier_instance_id: verifier_instance.command_verifier_instance_id,
      mission_id: verifier_instance.mission_id,
      timeout_at: timeout_at
    })

    %{state | timeout_timer: %{ref: ref, token: token, timeout_at: timeout_at}}
  end

  defp schedule_safety_reconcile(%{auto_schedule?: false} = state), do: state

  defp schedule_safety_reconcile(state) do
    state = cancel_safety_timer(state)
    ref = Process.send_after(self(), :safety_reconcile, state.safety_poll_interval_ms)
    %{state | safety_timer: ref}
  end

  defp cancel_timeout_timer(%{timeout_timer: nil} = state), do: state

  defp cancel_timeout_timer(%{timeout_timer: %{ref: ref}} = state) do
    _ = Process.cancel_timer(ref)
    %{state | timeout_timer: nil}
  end

  defp clear_timeout_timer(state), do: %{state | timeout_timer: nil}

  defp cancel_safety_timer(%{safety_timer: nil} = state), do: state

  defp cancel_safety_timer(%{safety_timer: ref} = state) do
    _ = Process.cancel_timer(ref)
    %{state | safety_timer: nil}
  end

  defp project_verifier_instances(state, verifier_instances) when is_list(verifier_instances) do
    Enum.reduce(verifier_instances, state, fn %CommandVerifierInstance{} = verifier_instance,
                                              acc ->
      project_verifier_instance(acc, verifier_instance)
    end)
  end

  defp project_verifier_instance(
         state,
         %CommandVerifierInstance{
           lifecycle_state: :pending,
           timeout_at: %DateTime{}
         } = verifier_instance
       ) do
    put_in(
      state.projection[verifier_instance.command_verifier_instance_id],
      verifier_instance
    )
  end

  defp project_verifier_instance(state, %CommandVerifierInstance{} = verifier_instance) do
    update_in(
      state.projection,
      &Map.delete(&1, verifier_instance.command_verifier_instance_id)
    )
  end

  defp remove_projected_verifier_instances(state, verifier_instances)
       when is_list(verifier_instances) do
    update_in(state.projection, fn projection ->
      Enum.reduce(verifier_instances, projection, fn %CommandVerifierInstance{} =
                                                       verifier_instance,
                                                     acc ->
        Map.delete(acc, verifier_instance.command_verifier_instance_id)
      end)
    end)
  end

  defp projection_from_instances(verifier_instances) when is_list(verifier_instances) do
    verifier_instances
    |> Enum.filter(&projectable_verifier_instance?/1)
    |> Map.new(fn %CommandVerifierInstance{} = verifier_instance ->
      {verifier_instance.command_verifier_instance_id, verifier_instance}
    end)
  end

  defp projectable_verifier_instance?(%CommandVerifierInstance{
         lifecycle_state: :pending,
         timeout_at: %DateTime{}
       }),
       do: true

  defp projectable_verifier_instance?(%CommandVerifierInstance{}), do: false

  defp next_projected_timeout(state) do
    case Map.values(state.projection) do
      [] -> nil
      verifier_instances -> Enum.min_by(verifier_instances, &timeout_sort_key/1)
    end
  end

  defp timeout_sort_key(%CommandVerifierInstance{
         timeout_at: %DateTime{} = timeout_at,
         command_verifier_instance_id: command_verifier_instance_id
       }) do
    {DateTime.to_unix(timeout_at, :microsecond), command_verifier_instance_id}
  end

  defp snapshot_from_state(state) do
    %{
      projected_verifier_instance_ids:
        state.projection
        |> Map.keys()
        |> Enum.sort(),
      projected_verifier_count: map_size(state.projection),
      timeout_timer_count: if(is_nil(state.timeout_timer), do: 0, else: 1)
    }
  end

  defp delay_ms(timeout_at, reference_time) do
    timeout_at
    |> DateTime.diff(reference_time, :millisecond)
    |> max(0)
    |> min(@max_timer_ms)
  end

  defp server_pid(server) when is_pid(server), do: server
  defp server_pid(server), do: GenServer.whereis(server)

  defp resolve_reference_time(state), do: state.reference_time_fun.()

  defp empty_projection, do: %{}

  defp timed(fun) when is_function(fun, 0) do
    started_at = System.monotonic_time()
    result = fun.()

    elapsed_us =
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :microsecond)

    {result, %{duration_us: elapsed_us}}
  end

  defp measurements_for_reconcile({:ok, verifier_instances}, measurements)
       when is_list(verifier_instances) do
    measurements
    |> Map.put(:timed_out_verifier_count, length(verifier_instances))
    |> Map.put(:error_count, 0)
  end

  defp measurements_for_reconcile({:error, _reason}, measurements) do
    measurements
    |> Map.put(:timed_out_verifier_count, 0)
    |> Map.put(:error_count, 1)
  end

  defp emit(event, state, measurements, metadata) when is_atom(event) do
    :telemetry.execute(
      @event_prefix ++ [event],
      measurements,
      state
      |> scheduler_metadata()
      |> Map.merge(metadata)
    )
  end

  defp scheduler_metadata(state) do
    %{
      projected_verifier_count: map_size(state.projection),
      timeout_timer_count: if(is_nil(state.timeout_timer), do: 0, else: 1)
    }
  end
end
