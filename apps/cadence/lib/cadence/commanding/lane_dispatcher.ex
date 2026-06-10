defmodule Cadence.Commanding.LaneDispatcher do
  @moduledoc false

  use GenServer

  alias Cadence.Commanding

  @default_safety_poll_interval_ms 60_000
  @event_prefix [:cadence, :commanding, :lane_dispatcher]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    organization_id = Keyword.fetch!(opts, :organization_id)
    mission_id = Keyword.fetch!(opts, :mission_id)
    queue_lane_key = Keyword.fetch!(opts, :queue_lane_key)

    name =
      Keyword.get(
        opts,
        :name,
        {:via, Registry,
         {Cadence.Commanding.DispatchRegistry, {organization_id, mission_id, queue_lane_key}}}
      )

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec dispatch_now(GenServer.server()) :: :ok | {:error, term()}
  def dispatch_now(server) do
    GenServer.call(server, :dispatch_now, :infinity)
  catch
    :exit, {:noproc, _details} -> {:error, :noproc}
  end

  @impl true
  def init(opts) do
    state = %{
      organization_id: Keyword.fetch!(opts, :organization_id),
      mission_id: Keyword.fetch!(opts, :mission_id),
      queue_lane_key: Keyword.fetch!(opts, :queue_lane_key),
      safety_poll_interval_ms:
        Keyword.get(
          opts,
          :safety_poll_interval_ms,
          Keyword.get(opts, :poll_interval_ms, @default_safety_poll_interval_ms)
        ),
      reference_time_fun: Keyword.get(opts, :reference_time_fun, &DateTime.utc_now/0),
      dispatch_timer: nil,
      released_by:
        Keyword.get_lazy(opts, :released_by, fn ->
          %{
            "service" => "command_dispatcher",
            "organization_id" => Keyword.fetch!(opts, :organization_id),
            "mission_id" => Keyword.fetch!(opts, :mission_id),
            "queue_lane_key" => Keyword.fetch!(opts, :queue_lane_key)
          }
        end)
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    {:noreply, schedule_dispatch(state, 0, :bootstrap)}
  end

  @impl true
  def handle_call(:dispatch_now, _from, state) do
    state = cancel_dispatch_timer(state)

    case dispatch_once(state, :notification) do
      {:stop, reason, reply, state} ->
        {:stop, reason, reply, state}

      {:continue, reply, state} ->
        {:reply, reply, state}
    end
  end

  @impl true
  def handle_info(:dispatch, state) do
    state = cancel_dispatch_timer(state)

    case dispatch_once(state, :notification) do
      {:stop, reason, _reply, state} ->
        {:stop, reason, state}

      {:continue, _reply, state} ->
        {:noreply, state}
    end
  end

  def handle_info({:dispatch, token}, state) do
    case state.dispatch_timer do
      %{token: ^token} ->
        state = clear_dispatch_timer(state)

        case dispatch_once(state, :timer) do
          {:stop, reason, _reply, state} ->
            {:stop, reason, state}

          {:continue, _reply, state} ->
            {:noreply, state}
        end

      _stale_or_canceled_timer ->
        emit(:stale_timer, state, %{count: 1}, %{})
        {:noreply, state}
    end
  end

  defp dispatch_once(state, reason) do
    attempted_at = state.reference_time_fun.()

    emit(:dispatch_attempt, state, %{count: 1}, %{reason: reason})

    case Commanding.dispatch_queue_lane(
           state.organization_id,
           state.mission_id,
           state.queue_lane_key,
           state.released_by,
           attempted_at: attempted_at
         ) do
      {:ok, _release_result} = result ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :released})
        {:continue, result, schedule_dispatch(state, 0, :released)}

      {:error, :command_queue_lane_empty} = result ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :empty})
        {:stop, :normal, result, state}

      {:error, {:command_queue_lane_waiting_for_not_before, _, %DateTime{} = next_not_before}} =
          result ->
        delay_ms = max(datetime_diff_ms(next_not_before, attempted_at), 0)

        emit(:dispatch_result, state, %{count: 1}, %{
          result: :waiting_for_not_before,
          next_not_before: next_not_before
        })

        {:continue, result, schedule_dispatch(state, delay_ms, :not_before)}

      {:error, {:command_queue_lane_no_release_target, _source_endpoint_ref, _mission_id}} =
          result ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :no_release_target})
        {:continue, result, schedule_dispatch(state, state.safety_poll_interval_ms, :safety)}

      {:error, _reason} = result ->
        emit(:dispatch_result, state, %{count: 1}, %{result: :error})
        {:continue, result, schedule_dispatch(state, state.safety_poll_interval_ms, :safety)}
    end
  end

  defp schedule_dispatch(state, delay_ms, reason) when is_integer(delay_ms) and delay_ms >= 0 do
    state = cancel_dispatch_timer(state)
    token = make_ref()
    ref = Process.send_after(self(), {:dispatch, token}, delay_ms)

    emit(:timer_scheduled, state, %{count: 1, delay_ms: delay_ms}, %{reason: reason})

    %{state | dispatch_timer: %{ref: ref, token: token}}
  end

  defp cancel_dispatch_timer(%{dispatch_timer: nil} = state), do: state

  defp cancel_dispatch_timer(%{dispatch_timer: %{ref: ref}} = state) do
    _ = Process.cancel_timer(ref)
    %{state | dispatch_timer: nil}
  end

  defp clear_dispatch_timer(state), do: %{state | dispatch_timer: nil}

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
      organization_id: state.organization_id,
      mission_id: state.mission_id,
      queue_lane_key: state.queue_lane_key,
      timer_count: if(is_nil(state.dispatch_timer), do: 0, else: 1)
    }
  end

  defp datetime_diff_ms(%DateTime{} = target_time, %DateTime{} = current_time) do
    DateTime.diff(target_time, current_time, :millisecond)
  end
end
