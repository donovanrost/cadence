defmodule Cadence.Commanding.LaneDispatcher do
  @moduledoc false

  use GenServer

  alias Cadence.Commanding

  @default_poll_interval_ms 250

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
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms),
      reference_time_fun: Keyword.get(opts, :reference_time_fun, &DateTime.utc_now/0),
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
    send(self(), :dispatch)
    {:noreply, state}
  end

  @impl true
  def handle_call(:dispatch_now, _from, state) do
    case dispatch_once(state) do
      {:stop, reason, reply} ->
        {:stop, reason, reply, state}

      {:continue, reply} ->
        {:reply, reply, state}
    end
  end

  @impl true
  def handle_info(:dispatch, state) do
    case dispatch_once(state) do
      {:stop, reason, _reply} ->
        {:stop, reason, state}

      {:continue, _reply} ->
        {:noreply, state}
    end
  end

  defp dispatch_once(state) do
    attempted_at = state.reference_time_fun.()

    case Commanding.dispatch_queue_lane(
           state.organization_id,
           state.mission_id,
           state.queue_lane_key,
           state.released_by,
           attempted_at: attempted_at
         ) do
      {:ok, _release_result} = result ->
        send(self(), :dispatch)
        {:continue, result}

      {:error, :command_queue_lane_empty} = result ->
        {:stop, :normal, result}

      {:error, {:command_queue_lane_waiting_for_not_before, _, %DateTime{} = next_not_before}} =
          result ->
        schedule_dispatch(max(datetime_diff_ms(next_not_before, attempted_at), 0))
        {:continue, result}

      {:error, _reason} = result ->
        schedule_dispatch(state.poll_interval_ms)
        {:continue, result}
    end
  end

  defp schedule_dispatch(delay_ms) when is_integer(delay_ms) and delay_ms >= 0 do
    Process.send_after(self(), :dispatch, delay_ms)
  end

  defp datetime_diff_ms(%DateTime{} = target_time, %DateTime{} = current_time) do
    DateTime.diff(target_time, current_time, :millisecond)
  end
end
