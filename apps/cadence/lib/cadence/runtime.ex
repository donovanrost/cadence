defmodule Cadence.Runtime do
  @moduledoc """
  Supervised data-plane boundary for mission and partition execution.
  """

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.ContactCoordinator
  alias Cadence.Runtime.MissionCoordinator
  alias Cadence.Runtime.MissionRuntime
  alias Cadence.Runtime.PartitionKey
  alias Cadence.Runtime.ProcessNamespace
  alias Cadence.Runtime.RealizedContactRuntime
  alias Cadence.Runtime.RealizedContactRuntimeSpec

  @spec ensure_mission_started(binary()) :: {:ok, pid()} | {:error, term()}
  def ensure_mission_started(mission_id) when is_binary(mission_id),
    do: ensure_mission_started(ProcessNamespace.default(), mission_id)

  @spec ensure_mission_started(ProcessNamespace.t(), binary()) :: {:ok, pid()} | {:error, term()}
  def ensure_mission_started(%ProcessNamespace{} = process_namespace, mission_id)
      when is_binary(mission_id) do
    child_spec =
      Supervisor.child_spec({MissionRuntime, mission_id}, id: {:mission_runtime, mission_id})

    case DynamicSupervisor.start_child(process_namespace.mission_supervisor, child_spec) do
      {:ok, mission_runtime} ->
        {:ok, mission_runtime}

      {:error, {:already_started, mission_runtime}} ->
        {:ok, mission_runtime}

      {:error, {:already_present, _child_spec}} ->
        case runtime_pid(process_namespace, mission_id) do
          nil -> {:error, :mission_runtime_not_running}
          mission_runtime -> {:ok, mission_runtime}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec stop_mission(binary()) :: :ok | {:error, term()}
  def stop_mission(mission_id) when is_binary(mission_id),
    do: stop_mission(ProcessNamespace.default(), mission_id)

  @spec stop_mission(ProcessNamespace.t(), binary()) :: :ok | {:error, term()}
  def stop_mission(%ProcessNamespace{} = process_namespace, mission_id)
      when is_binary(mission_id) do
    case runtime_pid(process_namespace, mission_id) do
      nil ->
        :ok

      mission_runtime ->
        with :ok <- quiesce_realized_contacts(process_namespace, mission_id) do
          stop_mission_runtime(process_namespace, mission_id, mission_runtime)
        end
    end
  end

  @spec running_mission_ids() :: [binary()]
  def running_mission_ids, do: running_mission_ids(ProcessNamespace.default())

  @spec running_mission_ids(ProcessNamespace.t()) :: [binary()]
  def running_mission_ids(%ProcessNamespace{} = process_namespace) do
    case Process.whereis(process_namespace.registry) do
      registry when is_pid(registry) ->
        process_namespace.registry
        |> Registry.select([
          {{{:mission_runtime, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
        ])
        |> Enum.filter(fn {_mission_id, mission_runtime} -> Process.alive?(mission_runtime) end)
        |> Enum.map(fn {mission_id, _mission_runtime} -> mission_id end)
        |> Enum.uniq()
        |> Enum.sort()

      nil ->
        []
    end
  rescue
    ArgumentError -> []
  catch
    :exit, _reason -> []
  end

  @spec stop_all_missions() :: :ok
  def stop_all_missions, do: stop_all_missions(ProcessNamespace.default())

  @spec stop_all_missions(ProcessNamespace.t()) :: :ok
  def stop_all_missions(%ProcessNamespace{} = process_namespace) do
    Enum.each(running_mission_ids(process_namespace), &stop_mission(process_namespace, &1))

    terminate_unregistered_mission_runtimes(process_namespace)

    :ok
  end

  @spec binding_set_for_evidence(RawEvidence.t()) :: {:ok, BindingSet.t()} | {:error, term()}
  def binding_set_for_evidence(%RawEvidence{} = raw_evidence) do
    binding_set_for_evidence(ProcessNamespace.default(), raw_evidence)
  end

  @spec binding_set_for_evidence(ProcessNamespace.t(), RawEvidence.t()) ::
          {:ok, BindingSet.t()} | {:error, term()}
  def binding_set_for_evidence(
        %ProcessNamespace{} = process_namespace,
        %RawEvidence{} = raw_evidence
      ) do
    partition_key = PartitionKey.from_raw_evidence(raw_evidence)

    with {:ok, _mission_runtime} <-
           ensure_mission_started(process_namespace, raw_evidence.mission_id) do
      MissionCoordinator.binding_set_for_partition(
        process_namespace,
        raw_evidence.mission_id,
        partition_key
      )
    end
  end

  @spec process_telemetry_ingress(RawEvidence.t()) ::
          {:ok, Cadence.processing_result()} | {:error, term()}
  def process_telemetry_ingress(%RawEvidence{} = raw_evidence) do
    process_telemetry_ingress(ProcessNamespace.default(), raw_evidence)
  end

  @spec process_telemetry_ingress(ProcessNamespace.t(), RawEvidence.t()) ::
          {:ok, Cadence.processing_result()} | {:error, term()}
  def process_telemetry_ingress(
        %ProcessNamespace{} = process_namespace,
        %RawEvidence{} = raw_evidence
      ) do
    with {:ok, _mission_runtime} <-
           ensure_mission_started(process_namespace, raw_evidence.mission_id) do
      MissionCoordinator.process_telemetry_ingress(
        process_namespace,
        raw_evidence.mission_id,
        raw_evidence
      )
    end
  end

  @spec partition_snapshot(binary(), PartitionKey.t() | binary()) ::
          {:ok, map()} | {:error, term()}
  def partition_snapshot(mission_id, %PartitionKey{} = partition_key)
      when is_binary(mission_id) do
    partition_snapshot(ProcessNamespace.default(), mission_id, partition_key)
  end

  def partition_snapshot(mission_id, partition_value)
      when is_binary(mission_id) and is_binary(partition_value) do
    partition_snapshot(
      ProcessNamespace.default(),
      mission_id,
      PartitionKey.new(%{affinity: :source_endpoint, value: partition_value})
    )
  end

  @spec partition_snapshot(ProcessNamespace.t(), binary(), PartitionKey.t() | binary()) ::
          {:ok, map()} | {:error, term()}
  def partition_snapshot(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        %PartitionKey{} = partition_key
      )
      when is_binary(mission_id) do
    with {:ok, _mission_runtime} <- ensure_mission_started(process_namespace, mission_id) do
      MissionCoordinator.partition_snapshot(process_namespace, mission_id, partition_key)
    end
  end

  def partition_snapshot(process_namespace, mission_id, partition_value)
      when is_struct(process_namespace, ProcessNamespace) and is_binary(mission_id) and
             is_binary(partition_value) do
    partition_snapshot(
      process_namespace,
      mission_id,
      PartitionKey.new(%{affinity: :source_endpoint, value: partition_value})
    )
  end

  @doc false
  @spec start_realized_contact(RealizedContactRuntimeSpec.t()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(%RealizedContactRuntimeSpec{} = realized_contact) do
    start_realized_contact(ProcessNamespace.default(), realized_contact)
  end

  @doc false
  @spec start_realized_contact(ProcessNamespace.t(), RealizedContactRuntimeSpec.t()) ::
          {:ok, pid()} | {:error, term()}
  def start_realized_contact(
        %ProcessNamespace{} = process_namespace,
        %RealizedContactRuntimeSpec{} = realized_contact
      ) do
    with {:ok, _mission_runtime} <-
           ensure_mission_started(process_namespace, realized_contact.mission_id) do
      child_spec =
        Supervisor.child_spec(
          {RealizedContactRuntime, realized_contact},
          id: {:realized_contact_runtime, realized_contact.realized_contact_id}
        )

      case DynamicSupervisor.start_child(
             MissionRuntime.realized_contact_supervisor_name(
               process_namespace,
               realized_contact.mission_id
             ),
             child_spec
           ) do
        {:ok, realized_contact_runtime} ->
          {:ok, realized_contact_runtime}

        {:error, {:already_started, realized_contact_runtime}} ->
          {:ok, realized_contact_runtime}

        {:error, {:already_present, _child_spec}} ->
          realized_contact_runtime(
            process_namespace,
            realized_contact.mission_id,
            realized_contact.realized_contact_id
          )

        {:error,
         {:shutdown, {:failed_to_start_child, Cadence.Runtime.ContactCoordinator, reason}}} ->
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec stop_realized_contact(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    stop_realized_contact_sync(ProcessNamespace.default(), mission_id, realized_contact_id)
  end

  @spec stop_realized_contact(ProcessNamespace.t(), binary(), binary()) ::
          :ok | {:error, term()}
  def stop_realized_contact(process_namespace, mission_id, realized_contact_id)
      when is_struct(process_namespace, ProcessNamespace) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    stop_realized_contact_sync(process_namespace, mission_id, realized_contact_id)
  end

  @spec stop_realized_contact_sync(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact_sync(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    stop_realized_contact_sync(ProcessNamespace.default(), mission_id, realized_contact_id)
  end

  @spec stop_realized_contact_sync(ProcessNamespace.t(), binary(), binary()) ::
          :ok | {:error, term()}
  def stop_realized_contact_sync(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    case realized_contact_runtime(process_namespace, mission_id, realized_contact_id) do
      {:ok, realized_contact_runtime} ->
        stop_realized_contact_runtime(
          process_namespace,
          mission_id,
          realized_contact_id,
          realized_contact_runtime
        )

      {:error, :realized_contact_runtime_not_running} ->
        :ok
    end
  end

  @spec realized_contact_snapshot(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def realized_contact_snapshot(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    realized_contact_snapshot(ProcessNamespace.default(), mission_id, realized_contact_id)
  end

  @spec realized_contact_snapshot(ProcessNamespace.t(), binary(), binary()) ::
          {:ok, map()} | {:error, term()}
  def realized_contact_snapshot(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    with {:ok, _mission_runtime} <- ensure_mission_started(process_namespace, mission_id),
         {:ok, realized_contact_runtime} <-
           realized_contact_coordinator(process_namespace, mission_id, realized_contact_id) do
      ContactCoordinator.snapshot(realized_contact_runtime)
    end
  end

  @spec path_runtime_snapshot(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def path_runtime_snapshot(mission_id, realized_contact_id, path_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) do
    path_runtime_snapshot(ProcessNamespace.default(), mission_id, realized_contact_id, path_id)
  end

  @spec path_runtime_snapshot(ProcessNamespace.t(), binary(), binary(), binary()) ::
          {:ok, map()} | {:error, term()}
  def path_runtime_snapshot(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id,
        path_id
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) do
    with {:ok, _mission_runtime} <- ensure_mission_started(process_namespace, mission_id),
         {:ok, realized_contact_runtime} <-
           realized_contact_coordinator(process_namespace, mission_id, realized_contact_id) do
      ContactCoordinator.path_snapshot(realized_contact_runtime, path_id)
    end
  end

  @spec handle_path_transport_event(binary(), binary(), binary(), binary(), term(), keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def handle_path_transport_event(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        event,
        opts \\ []
      )

  def handle_path_transport_event(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        event,
        opts
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    handle_path_transport_event(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      transport_binding_id,
      event,
      opts
    )
  end

  @spec handle_path_transport_event(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          binary(),
          term()
        ) :: {:ok, [term()]} | {:error, term()}
  def handle_path_transport_event(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        event
      ) do
    handle_path_transport_event(
      process_namespace,
      mission_id,
      realized_contact_id,
      path_id,
      transport_binding_id,
      event,
      []
    )
  end

  @spec handle_path_transport_event(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          binary(),
          term(),
          keyword()
        ) :: {:ok, [term()]} | {:error, term()}
  def handle_path_transport_event(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        event,
        opts
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    with {:ok, _mission_runtime} <- ensure_mission_started(process_namespace, mission_id),
         {:ok, realized_contact_runtime} <-
           realized_contact_coordinator(process_namespace, mission_id, realized_contact_id) do
      ContactCoordinator.handle_transport_event(
        realized_contact_runtime,
        path_id,
        transport_binding_id,
        event,
        opts
      )
    end
  end

  @spec handle_path_control_input(binary(), binary(), binary(), binary(), term(), keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def handle_path_control_input(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        control_input,
        opts \\ []
      )

  def handle_path_control_input(
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        control_input,
        opts
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    handle_path_control_input(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      path_id,
      transport_binding_id,
      control_input,
      opts
    )
  end

  @spec handle_path_control_input(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          binary(),
          term()
        ) :: {:ok, [term()]} | {:error, term()}
  def handle_path_control_input(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        control_input
      ) do
    handle_path_control_input(
      process_namespace,
      mission_id,
      realized_contact_id,
      path_id,
      transport_binding_id,
      control_input,
      []
    )
  end

  @spec handle_path_control_input(
          ProcessNamespace.t(),
          binary(),
          binary(),
          binary(),
          binary(),
          term(),
          keyword()
        ) :: {:ok, [term()]} | {:error, term()}
  def handle_path_control_input(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id,
        path_id,
        transport_binding_id,
        control_input,
        opts
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_binary(path_id) and
             is_binary(transport_binding_id) and is_list(opts) do
    with {:ok, _mission_runtime} <- ensure_mission_started(process_namespace, mission_id),
         {:ok, realized_contact_runtime} <-
           realized_contact_coordinator(process_namespace, mission_id, realized_contact_id) do
      ContactCoordinator.handle_control_input(
        realized_contact_runtime,
        path_id,
        transport_binding_id,
        control_input,
        opts
      )
    end
  end

  @spec advance_realized_contact_time(binary(), binary(), DateTime.t()) :: :ok | {:error, term()}
  def advance_realized_contact_time(mission_id, realized_contact_id, %DateTime{} = target_time)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    advance_realized_contact_time(
      ProcessNamespace.default(),
      mission_id,
      realized_contact_id,
      target_time
    )
  end

  @spec advance_realized_contact_time(ProcessNamespace.t(), binary(), binary(), DateTime.t()) ::
          :ok | {:error, term()}
  def advance_realized_contact_time(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id,
        %DateTime{} = target_time
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    with {:ok, _mission_runtime} <- ensure_mission_started(process_namespace, mission_id),
         {:ok, realized_contact_runtime} <-
           realized_contact_coordinator(process_namespace, mission_id, realized_contact_id) do
      ContactCoordinator.advance_time(realized_contact_runtime, target_time)
    end
  end

  @spec realized_contact_running?(binary(), binary()) :: boolean()
  def realized_contact_running?(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    realized_contact_running?(ProcessNamespace.default(), mission_id, realized_contact_id)
  end

  @spec realized_contact_running?(ProcessNamespace.t(), binary(), binary()) :: boolean()
  def realized_contact_running?(
        %ProcessNamespace{} = process_namespace,
        mission_id,
        realized_contact_id
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    match?(
      {:ok, _realized_contact_runtime},
      realized_contact_runtime(process_namespace, mission_id, realized_contact_id)
    )
  end

  defp runtime_pid(process_namespace, mission_id) do
    case Registry.lookup(process_namespace.registry, {:mission_runtime, mission_id}) do
      [{mission_runtime, _value}] when is_pid(mission_runtime) ->
        if Process.alive?(mission_runtime), do: mission_runtime, else: nil

      [] ->
        nil
    end
  end

  defp stop_mission_runtime(process_namespace, mission_id, mission_runtime) do
    stop_registered_child(
      process_namespace.mission_supervisor,
      mission_runtime,
      fn ->
        Registry.lookup(process_namespace.registry, {:mission_runtime, mission_id}) != []
      end,
      :mission_runtime_stop_timeout
    )
  end

  defp realized_contact_runtime(process_namespace, mission_id, realized_contact_id) do
    case Registry.lookup(
           process_namespace.registry,
           {:realized_contact_runtime, mission_id, realized_contact_id}
         ) do
      [{realized_contact_runtime, _value}] -> {:ok, realized_contact_runtime}
      [] -> {:error, :realized_contact_runtime_not_running}
    end
  end

  defp stop_realized_contact_runtime(
         process_namespace,
         mission_id,
         realized_contact_id,
         realized_contact_runtime
       ) do
    with :ok <- quiesce_realized_contact(process_namespace, mission_id, realized_contact_id) do
      stop_registered_child(
        MissionRuntime.realized_contact_supervisor_name(process_namespace, mission_id),
        realized_contact_runtime,
        fn ->
          match?(
            {:ok, _pid},
            realized_contact_runtime(process_namespace, mission_id, realized_contact_id)
          )
        end,
        :realized_contact_stop_timeout
      )
    end
  end

  defp quiesce_realized_contacts(process_namespace, mission_id) do
    mission_id
    |> realized_contact_coordinators(process_namespace)
    |> Enum.reduce_while(:ok, fn {_realized_contact_id, coordinator}, :ok ->
      case ContactCoordinator.quiesce(coordinator) do
        {:ok, _settlement} -> {:cont, :ok}
        {:error, :noproc} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp quiesce_realized_contact(process_namespace, mission_id, realized_contact_id) do
    case realized_contact_coordinator(process_namespace, mission_id, realized_contact_id) do
      {:ok, coordinator} ->
        case ContactCoordinator.quiesce(coordinator) do
          {:ok, _settlement} -> :ok
          {:error, :noproc} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :realized_contact_runtime_not_running} ->
        :ok
    end
  end

  defp realized_contact_coordinators(mission_id, process_namespace) do
    process_namespace.registry
    |> Registry.select([
      {{{:realized_contact_coordinator, mission_id, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.filter(fn {_realized_contact_id, coordinator} -> Process.alive?(coordinator) end)
  rescue
    ArgumentError -> []
  catch
    :exit, _reason -> []
  end

  defp terminate_unregistered_mission_runtimes(process_namespace) do
    case Process.whereis(process_namespace.mission_supervisor) do
      nil ->
        :ok

      mission_supervisor ->
        mission_supervisor
        |> safe_which_children()
        |> Enum.each(fn
          {_child_id, mission_runtime, :supervisor, _modules} when is_pid(mission_runtime) ->
            safe_terminate_child(mission_supervisor, mission_runtime)

          _other_child ->
            :ok
        end)
    end
  end

  defp stop_registered_child(supervisor, runtime, registered?, timeout_reason) do
    monitor_ref = Process.monitor(runtime)
    result = DynamicSupervisor.terminate_child(supervisor, runtime)

    case result do
      :ok ->
        with :ok <- await_runtime_down(monitor_ref, timeout_reason) do
          await_runtime_unregistered(registered?, 500, timeout_reason)
        end

      {:error, _reason} = error ->
        Process.demonitor(monitor_ref, [:flush])
        error
    end
  end

  defp await_runtime_down(monitor_ref, timeout_reason) do
    receive do
      {:DOWN, ^monitor_ref, :process, _pid, _reason} -> :ok
    after
      5_000 ->
        Process.demonitor(monitor_ref, [:flush])
        {:error, timeout_reason}
    end
  end

  defp await_runtime_unregistered(_registered?, 0, timeout_reason) do
    {:error, timeout_reason}
  end

  defp await_runtime_unregistered(registered?, attempts_left, timeout_reason) do
    if registered?.() do
      Process.sleep(10)
      await_runtime_unregistered(registered?, attempts_left - 1, timeout_reason)
    else
      :ok
    end
  end

  defp realized_contact_coordinator(process_namespace, mission_id, realized_contact_id) do
    case Registry.lookup(
           process_namespace.registry,
           {:realized_contact_coordinator, mission_id, realized_contact_id}
         ) do
      [{realized_contact_runtime, _value}] -> {:ok, realized_contact_runtime}
      [] -> {:error, :realized_contact_runtime_not_running}
    end
  end

  defp safe_which_children(mission_supervisor) do
    DynamicSupervisor.which_children(mission_supervisor)
  catch
    :exit, _reason -> []
  end

  defp safe_terminate_child(mission_supervisor, mission_runtime) do
    DynamicSupervisor.terminate_child(mission_supervisor, mission_runtime)
  catch
    :exit, _reason -> :ok
  end
end
