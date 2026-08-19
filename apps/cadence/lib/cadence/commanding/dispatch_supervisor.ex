defmodule Cadence.Commanding.DispatchSupervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.Commanding.LaneDispatcher

  @registry Cadence.Commanding.DispatchRegistry
  @lane_supervisor Cadence.Commanding.LaneDispatcherSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec ensure_lane_dispatcher_started(binary(), binary(), binary(), keyword()) ::
          :ok | {:error, term()}
  def ensure_lane_dispatcher_started(organization_id, mission_id, queue_lane_key, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) and
             is_list(opts) do
    if supervisor_dependencies_missing?() do
      :ok
    else
      start_lane_dispatcher_child(organization_id, mission_id, queue_lane_key, opts)
    end
  end

  @spec lane_dispatcher(binary(), binary(), binary()) :: {:ok, pid()} | :error
  def lane_dispatcher(organization_id, mission_id, queue_lane_key)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) do
    if is_nil(Process.whereis(@registry)) do
      :error
    else
      case Registry.lookup(@registry, {organization_id, mission_id, queue_lane_key}) do
        [{pid, _value}] -> {:ok, pid}
        [] -> :error
      end
    end
  end

  defp supervisor_dependencies_missing? do
    is_nil(Process.whereis(@lane_supervisor)) or is_nil(Process.whereis(@registry))
  end

  defp start_lane_dispatcher_child(organization_id, mission_id, queue_lane_key, opts) do
    child_spec =
      Supervisor.child_spec(
        {LaneDispatcher,
         Keyword.merge(opts,
           organization_id: organization_id,
           mission_id: mission_id,
           queue_lane_key: queue_lane_key
         )},
        id: {:command_lane_dispatcher, organization_id, mission_id, queue_lane_key},
        restart: :transient
      )

    normalize_start_child_result(DynamicSupervisor.start_child(@lane_supervisor, child_spec))
  end

  defp normalize_start_child_result({:ok, _pid}), do: :ok
  defp normalize_start_child_result({:error, {:already_started, _pid}}), do: :ok
  defp normalize_start_child_result({:error, {:already_present, _child_spec}}), do: :ok
  defp normalize_start_child_result({:error, reason}), do: {:error, reason}

  @impl true
  def init(opts) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {DynamicSupervisor, strategy: :one_for_one, name: @lane_supervisor},
      {Cadence.Commanding.Dispatcher, opts}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
