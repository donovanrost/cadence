defmodule Cadence.Commanding.DispatchSupervisor do
  @moduledoc false

  use Supervisor

  alias Cadence.Commanding.{LaneDispatcher, ProcessNamespace}

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    process_namespace = process_namespace(opts)

    %{
      id: process_namespace.root_supervisor,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    process_namespace = process_namespace(opts)
    Supervisor.start_link(__MODULE__, opts, name: process_namespace.root_supervisor)
  end

  @spec ensure_lane_dispatcher_started(binary(), binary(), binary(), keyword()) ::
          :ok | {:error, term()}
  def ensure_lane_dispatcher_started(organization_id, mission_id, queue_lane_key),
    do:
      ensure_lane_dispatcher_started(
        ProcessNamespace.default(),
        organization_id,
        mission_id,
        queue_lane_key,
        []
      )

  def ensure_lane_dispatcher_started(organization_id, mission_id, queue_lane_key, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) and
             is_list(opts) do
    process_namespace =
      Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)

    ensure_lane_dispatcher_started(
      process_namespace,
      organization_id,
      mission_id,
      queue_lane_key,
      opts
    )
  end

  @spec ensure_lane_dispatcher_started(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          keyword()
        ) :: :ok | {:error, term()}
  def ensure_lane_dispatcher_started(
        %ProcessNamespace{} = process_namespace,
        organization_id,
        mission_id,
        queue_lane_key
      ),
      do:
        ensure_lane_dispatcher_started(
          process_namespace,
          organization_id,
          mission_id,
          queue_lane_key,
          []
        )

  def ensure_lane_dispatcher_started(
        %ProcessNamespace{} = process_namespace,
        organization_id,
        mission_id,
        queue_lane_key,
        opts
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) and
             is_list(opts) do
    if supervisor_dependencies_missing?(process_namespace) do
      :ok
    else
      start_lane_dispatcher_child(
        process_namespace,
        organization_id,
        mission_id,
        queue_lane_key,
        opts
      )
    end
  end

  @spec lane_dispatcher(binary(), binary(), binary()) :: {:ok, pid()} | :error
  def lane_dispatcher(organization_id, mission_id, queue_lane_key)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) do
    lane_dispatcher(ProcessNamespace.default(), organization_id, mission_id, queue_lane_key)
  end

  @spec lane_dispatcher(ProcessNamespace.t(), binary(), binary(), binary()) ::
          {:ok, pid()} | :error
  def lane_dispatcher(
        %ProcessNamespace{} = process_namespace,
        organization_id,
        mission_id,
        queue_lane_key
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) do
    if is_nil(Process.whereis(process_namespace.registry)) do
      :error
    else
      case Registry.lookup(
             process_namespace.registry,
             {organization_id, mission_id, queue_lane_key}
           ) do
        [{pid, _value}] -> {:ok, pid}
        [] -> :error
      end
    end
  end

  defp supervisor_dependencies_missing?(process_namespace) do
    is_nil(GenServer.whereis(process_namespace.lane_supervisor)) or
      is_nil(Process.whereis(process_namespace.registry))
  end

  defp start_lane_dispatcher_child(
         process_namespace,
         organization_id,
         mission_id,
         queue_lane_key,
         opts
       ) do
    child_spec =
      Supervisor.child_spec(
        {LaneDispatcher,
         Keyword.merge(opts,
           organization_id: organization_id,
           mission_id: mission_id,
           queue_lane_key: queue_lane_key,
           process_namespace: process_namespace
         )},
        id: {:command_lane_dispatcher, organization_id, mission_id, queue_lane_key},
        restart: :transient
      )

    normalize_start_child_result(
      DynamicSupervisor.start_child(process_namespace.lane_supervisor, child_spec)
    )
  end

  defp normalize_start_child_result({:ok, _pid}), do: :ok
  defp normalize_start_child_result({:error, {:already_started, _pid}}), do: :ok
  defp normalize_start_child_result({:error, {:already_present, _child_spec}}), do: :ok
  defp normalize_start_child_result({:error, reason}), do: {:error, reason}

  @impl true
  def init(opts) do
    process_namespace = process_namespace(opts)

    children = [
      {Registry, keys: :unique, name: process_namespace.registry},
      {DynamicSupervisor, strategy: :one_for_one, name: process_namespace.lane_supervisor},
      {Cadence.Commanding.Dispatcher,
       opts
       |> Keyword.put(:process_namespace, process_namespace)
       |> Keyword.put(:name, process_namespace.dispatcher)}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp process_namespace(opts) do
    Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0)
  end
end
