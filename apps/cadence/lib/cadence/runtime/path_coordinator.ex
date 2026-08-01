defmodule Cadence.Runtime.PathCoordinator do
  @moduledoc """
  Path-local runtime coordinator that owns transport extensions for one realized
  contact path.
  """

  use GenServer

  alias Cadence.Capabilities.Descriptor
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.ProviderAdapters

  alias Cadence.Runtime.{
    ActivationContext,
    CapabilityRegistry,
    ContactPathSpec,
    IngressArchiveConsumer,
    IngressJournalConsumer,
    IngressPersistenceProjector,
    MissionRuntime,
    PartitionKey,
    ProviderBindingSpec,
    ProviderIngressExecutor,
    TransportBindingSpec
  }

  alias Cadence.Runtime.TransportRuntime

  @type state :: %{
          organization_id: binary() | nil,
          mission_id: binary(),
          realized_contact_id: binary(),
          path: ContactPathSpec.t(),
          activation_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          clock_mode: :live | :replay,
          initial_time: DateTime.t(),
          provider_bindings: %{required(binary()) => ProviderBindingSpec.t()},
          transport_bindings: %{required(binary()) => TransportBindingSpec.t()}
        }

  def start_link(opts) when is_list(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    realized_contact_id = Keyword.fetch!(opts, :realized_contact_id)
    %ContactPathSpec{} = path = Keyword.fetch!(opts, :path)

    GenServer.start_link(
      __MODULE__,
      opts,
      name: MissionRuntime.path_coordinator_name(mission_id, realized_contact_id, path.path_id)
    )
  end

  @spec snapshot(pid()) :: {:ok, map()} | {:error, term()}
  def snapshot(path_runtime) do
    GenServer.call(path_runtime, :snapshot)
  end

  @spec handle_transport_event(pid(), binary(), term(), keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def handle_transport_event(path_runtime, transport_binding_id, event, opts \\ [])
      when is_binary(transport_binding_id) and is_list(opts) do
    GenServer.call(
      path_runtime,
      {:handle_transport_event, transport_binding_id, event, opts},
      Keyword.get(opts, :call_timeout, 5_000)
    )
  end

  @spec handle_control_input(pid(), binary(), term(), keyword()) ::
          {:ok, [term()]} | {:error, term()}
  def handle_control_input(path_runtime, transport_binding_id, control_input, opts \\ [])
      when is_binary(transport_binding_id) and is_list(opts) do
    GenServer.call(
      path_runtime,
      {:handle_control_input, transport_binding_id, control_input, opts}
    )
  end

  @spec advance_time(pid(), DateTime.t()) :: :ok | {:error, term()}
  def advance_time(path_runtime, %DateTime{} = target_time) do
    GenServer.call(path_runtime, {:advance_time, target_time})
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    realized_contact_id = Keyword.fetch!(opts, :realized_contact_id)
    %ContactPathSpec{} = path = Keyword.fetch!(opts, :path)
    clock_mode = Keyword.get(opts, :clock_mode, :live)
    initial_time = Keyword.get(opts, :initial_time, DateTime.utc_now())

    state = %{
      organization_id: Keyword.get(opts, :organization_id),
      mission_id: mission_id,
      realized_contact_id: realized_contact_id,
      path: path,
      activation_id: "realized_contact:" <> realized_contact_id,
      binding_set_id: "realized_contact:" <> realized_contact_id,
      binding_set_version: 1,
      clock_mode: clock_mode,
      initial_time: initial_time,
      provider_bindings: Map.new(path.provider_bindings, &{&1.provider_binding_id, &1}),
      transport_bindings: Map.new(path.transport_bindings, &{&1.transport_binding_id, &1})
    }

    case start_provider_runtimes(state) do
      :ok ->
        case start_transport_runtimes(state) do
          :ok -> {:ok, state}
          {:error, reason} -> {:stop, reason}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    with {:ok, provider_runtime_snapshots} <- collect_provider_runtime_snapshots(state),
         {:ok, transport_runtime_snapshots} <- collect_transport_runtime_snapshots(state) do
      snapshot = %{
        realized_contact_id: state.realized_contact_id,
        mission_id: state.mission_id,
        path_id: state.path.path_id,
        direction: state.path.direction,
        selection_role: state.path.selection_role,
        source_endpoint_ref: state.path.source_endpoint_ref,
        provider_path_ref: state.path.provider_path_ref,
        metadata: state.path.metadata,
        provider_runtime_count: length(provider_runtime_snapshots),
        provider_runtimes: provider_runtime_snapshots,
        transport_runtime_count: length(transport_runtime_snapshots),
        transport_runtimes: transport_runtime_snapshots
      }

      {:reply, {:ok, snapshot}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:handle_transport_event, transport_binding_id, event, opts}, _from, state) do
    reply =
      with {:ok, transport_runtime} <- transport_runtime(state, transport_binding_id) do
        TransportRuntime.handle_transport_event(transport_runtime, event, opts)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:handle_control_input, transport_binding_id, control_input, opts},
        _from,
        state
      ) do
    reply =
      with {:ok, transport_runtime} <- transport_runtime(state, transport_binding_id) do
        TransportRuntime.handle_control_input(transport_runtime, control_input, opts)
      end

    {:reply, reply, state}
  end

  def handle_call({:advance_time, %DateTime{} = target_time}, _from, state) do
    reply =
      Enum.reduce_while(state.path.transport_bindings, :ok, fn transport_binding, :ok ->
        with {:ok, transport_runtime} <-
               transport_runtime(state, transport_binding.transport_binding_id),
             :ok <- TransportRuntime.advance_time(transport_runtime, target_time) do
          {:cont, :ok}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    {:reply, reply, state}
  end

  defp start_provider_runtimes(state) do
    Enum.reduce_while(state.path.provider_bindings, :ok, fn %ProviderBindingSpec{} =
                                                              provider_binding,
                                                            :ok ->
      with {:ok, _journal} <- maybe_start_provider_ingress_journal(state, provider_binding),
           {:ok, _projector} <- start_provider_persistence_projector(state, provider_binding),
           {:ok, _executor} <- start_provider_ingress_executor(state, provider_binding),
           {:ok, _consumer} <-
             maybe_start_provider_ingress_journal_consumer(state, provider_binding),
           {:ok, _archive_consumer} <-
             maybe_start_provider_ingress_archive_consumer(state, provider_binding),
           {:ok, provider_module} <-
             Cadence.ProviderAdapters.Registry.fetch_module(provider_binding.adapter_key),
           {:ok, _provider_runtime} <-
             start_provider_runtime(state, provider_binding, provider_module) do
        {:cont, :ok}
      else
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_start_provider_ingress_journal(state, %ProviderBindingSpec{} = provider_binding) do
    if journaled_provider?(state, provider_binding) do
      child_spec =
        {IngressJournal,
         name:
           MissionRuntime.provider_ingress_journal_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id,
             provider_binding.provider_binding_id
           ),
         mission_id: state.mission_id,
         realized_contact_id: state.realized_contact_id,
         path_id: state.path.path_id,
         provider_binding_id: provider_binding.provider_binding_id}

      start_provider_child(state, child_spec)
    else
      {:ok, nil}
    end
  end

  defp maybe_start_provider_ingress_journal_consumer(
         state,
         %ProviderBindingSpec{} = provider_binding
       ) do
    if journaled_provider?(state, provider_binding) do
      child_spec =
        {IngressJournalConsumer,
         name:
           MissionRuntime.provider_ingress_journal_consumer_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id,
             provider_binding.provider_binding_id
           ),
         mission_id: state.mission_id,
         realized_contact_id: state.realized_contact_id,
         path_id: state.path.path_id,
         provider_binding_id: provider_binding.provider_binding_id,
         journal_name:
           MissionRuntime.provider_ingress_journal_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id,
             provider_binding.provider_binding_id
           ),
         executor_name:
           MissionRuntime.provider_ingress_executor_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id,
             provider_binding.provider_binding_id
           )}

      start_provider_child(state, child_spec)
    else
      {:ok, nil}
    end
  end

  defp maybe_start_provider_ingress_archive_consumer(
         state,
         %ProviderBindingSpec{} = provider_binding
       ) do
    if journaled_provider?(state, provider_binding) do
      child_spec =
        {IngressArchiveConsumer,
         name:
           MissionRuntime.provider_ingress_archive_consumer_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id,
             provider_binding.provider_binding_id
           ),
         mission_id: state.mission_id,
         realized_contact_id: state.realized_contact_id,
         path_id: state.path.path_id,
         provider_binding_id: provider_binding.provider_binding_id,
         journal_name:
           MissionRuntime.provider_ingress_journal_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id,
             provider_binding.provider_binding_id
           )}

      start_provider_child(state, child_spec)
    else
      {:ok, nil}
    end
  end

  defp start_provider_persistence_projector(state, %ProviderBindingSpec{} = provider_binding) do
    child_spec =
      {IngressPersistenceProjector,
       name:
         MissionRuntime.provider_persistence_projector_name(
           state.mission_id,
           state.realized_contact_id,
           state.path.path_id,
           provider_binding.provider_binding_id
         ),
       organization_id: state.organization_id,
       mission_id: state.mission_id,
       realized_contact_id: state.realized_contact_id,
       path_id: state.path.path_id,
       provider_binding_id: provider_binding.provider_binding_id}

    case DynamicSupervisor.start_child(
           MissionRuntime.provider_supervisor_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id
           ),
           child_spec
         ) do
      {:ok, projector} -> {:ok, projector}
      {:error, {:already_started, projector}} -> {:ok, projector}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_provider_ingress_executor(state, %ProviderBindingSpec{} = provider_binding) do
    child_spec =
      {ProviderIngressExecutor,
       name:
         MissionRuntime.provider_ingress_executor_name(
           state.mission_id,
           state.realized_contact_id,
           state.path.path_id,
           provider_binding.provider_binding_id
         ),
       organization_id: state.organization_id,
       mission_id: state.mission_id,
       realized_contact_id: state.realized_contact_id,
       path_id: state.path.path_id,
       provider_binding_id: provider_binding.provider_binding_id,
       persistence_projector_name:
         MissionRuntime.provider_persistence_projector_name(
           state.mission_id,
           state.realized_contact_id,
           state.path.path_id,
           provider_binding.provider_binding_id
         )}

    case DynamicSupervisor.start_child(
           MissionRuntime.provider_supervisor_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id
           ),
           child_spec
         ) do
      {:ok, executor} -> {:ok, executor}
      {:error, {:already_started, executor}} -> {:ok, executor}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_provider_runtime(state, %ProviderBindingSpec{} = provider_binding, provider_module) do
    provider_opts =
      [
        name:
          MissionRuntime.provider_runtime_name(
            state.mission_id,
            state.realized_contact_id,
            state.path.path_id,
            provider_binding.provider_binding_id
          ),
        mission_id: state.mission_id,
        realized_contact_id: state.realized_contact_id,
        path_id: state.path.path_id,
        provider_binding_id: provider_binding.provider_binding_id,
        source_endpoint_ref: state.path.source_endpoint_ref,
        source_endpoint_spacecraft_id: state.path.source_endpoint_spacecraft_id,
        direction: state.path.direction,
        ingress_executor_name:
          MissionRuntime.provider_ingress_executor_name(
            state.mission_id,
            state.realized_contact_id,
            state.path.path_id,
            provider_binding.provider_binding_id
          ),
        configuration: provider_binding.configuration
      ]
      |> maybe_put_ingress_journal_name(state, provider_binding)

    child_spec = provider_module.child_spec(provider_opts)

    case DynamicSupervisor.start_child(
           MissionRuntime.provider_supervisor_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id
           ),
           child_spec
         ) do
      {:ok, provider_runtime} -> {:ok, provider_runtime}
      {:error, {:already_started, provider_runtime}} -> {:ok, provider_runtime}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_ingress_journal_name(opts, state, provider_binding) do
    if journaled_provider?(state, provider_binding) do
      Keyword.put(
        opts,
        :ingress_journal_name,
        MissionRuntime.provider_ingress_journal_name(
          state.mission_id,
          state.realized_contact_id,
          state.path.path_id,
          provider_binding.provider_binding_id
        )
      )
    else
      opts
    end
  end

  defp start_provider_child(state, child_spec) do
    case DynamicSupervisor.start_child(
           MissionRuntime.provider_supervisor_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id
           ),
           child_spec
         ) do
      {:ok, child} -> {:ok, child}
      {:error, {:already_started, child}} -> {:ok, child}
      {:error, reason} -> {:error, reason}
    end
  end

  defp journaled_provider?(state, %ProviderBindingSpec{} = provider_binding) do
    ingress_journal_enabled?() and state.path.direction == :downlink and
      provider_binding.adapter_key == :tcp_socket and
      provider_protocol_family(provider_binding.configuration) in [:tm, :tm_transfer_frame]
  end

  defp ingress_journal_enabled? do
    :cadence
    |> Application.get_env(:ingress_journal, [])
    |> Keyword.get(:enabled?, false)
  end

  defp provider_protocol_family(configuration) when is_map(configuration) do
    case Map.get(
           configuration,
           :ingress_protocol_family,
           Map.get(configuration, "ingress_protocol_family")
         ) do
      "tm" -> :tm
      "tm_transfer_frame" -> :tm_transfer_frame
      value -> value
    end
  end

  defp start_transport_runtimes(state) do
    Enum.reduce_while(state.path.transport_bindings, :ok, fn %TransportBindingSpec{} =
                                                               transport_binding,
                                                             :ok ->
      with {:ok, %Descriptor{kind: :transport_extension}} <-
             CapabilityRegistry.fetch_descriptor(transport_binding.family_key),
           {:ok, built_configuration} <- build_transport_configuration(state, transport_binding),
           {:ok, _transport_runtime} <-
             start_transport_runtime(state, transport_binding, built_configuration) do
        {:cont, :ok}
      else
        {:ok, %Descriptor{} = descriptor} ->
          {:halt, {:error, {:invalid_transport_extension_descriptor, descriptor.kind}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp build_transport_configuration(state, %TransportBindingSpec{} = transport_binding) do
    CapabilityRegistry.build_instance(
      transport_binding.family_key,
      transport_binding.configuration,
      ActivationContext.new(%{
        mission_id: state.mission_id,
        activation_id: state.activation_id,
        binding_set_id: state.binding_set_id,
        binding_set_version: state.binding_set_version,
        partition_key: transport_partition_key(state.path, transport_binding),
        metadata: %{
          "realized_contact_id" => state.realized_contact_id,
          "path_id" => state.path.path_id,
          "transport_binding_id" => transport_binding.transport_binding_id
        }
      })
    )
  end

  defp start_transport_runtime(state, %TransportBindingSpec{} = transport_binding, configuration) do
    child_spec =
      {TransportRuntime,
       mission_id: state.mission_id,
       realized_contact_id: state.realized_contact_id,
       path_id: state.path.path_id,
       activation_id: state.activation_id,
       binding_set_id: state.binding_set_id,
       binding_set_version: state.binding_set_version,
       capability_instance_id: transport_binding.transport_binding_id,
       family_key: transport_binding.family_key,
       configuration: configuration,
       scope_ref: transport_scope_ref(state.path, transport_binding),
       partition_key: transport_partition_key(state.path, transport_binding),
       clock_mode: state.clock_mode,
       initial_time: state.initial_time}

    case DynamicSupervisor.start_child(
           MissionRuntime.transport_supervisor_name(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id
           ),
           child_spec
         ) do
      {:ok, transport_runtime} -> {:ok, transport_runtime}
      {:error, {:already_started, transport_runtime}} -> {:ok, transport_runtime}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_transport_runtime_snapshots(state) do
    Enum.reduce_while(state.path.transport_bindings, {:ok, []}, fn transport_binding,
                                                                   {:ok, acc} ->
      with {:ok, transport_runtime} <-
             transport_runtime(state, transport_binding.transport_binding_id),
           {:ok, snapshot} <- TransportRuntime.snapshot(transport_runtime) do
        {:cont, {:ok, acc ++ [snapshot]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp collect_provider_runtime_snapshots(state) do
    Enum.reduce_while(state.path.provider_bindings, {:ok, []}, fn provider_binding, {:ok, acc} ->
      case ProviderAdapters.snapshot(
             state.mission_id,
             state.realized_contact_id,
             state.path.path_id,
             provider_binding.provider_binding_id,
             provider_binding.adapter_key
           ) do
        {:ok, snapshot} ->
          {:cont, {:ok, acc ++ [snapshot]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp transport_runtime(state, transport_binding_id) do
    case Registry.lookup(
           Cadence.Runtime.Registry,
           {:transport_runtime, state.mission_id, state.realized_contact_id, state.path.path_id,
            transport_binding_id}
         ) do
      [{transport_runtime, _value}] -> {:ok, transport_runtime}
      [] -> {:error, {:transport_runtime_not_running, transport_binding_id}}
    end
  end

  defp transport_scope_ref(%ContactPathSpec{} = path, %TransportBindingSpec{target_scope: :path}),
    do: path.path_id

  defp transport_scope_ref(
         %ContactPathSpec{},
         %TransportBindingSpec{
           target_scope: :transport,
           transport_binding_id: transport_binding_id
         }
       ),
       do: transport_binding_id

  defp transport_partition_key(
         %ContactPathSpec{} = path,
         %TransportBindingSpec{target_scope: :path}
       ) do
    PartitionKey.new(%{affinity: :path, value: path.path_id})
  end

  defp transport_partition_key(
         %ContactPathSpec{},
         %TransportBindingSpec{
           target_scope: :transport,
           transport_binding_id: transport_binding_id
         }
       ) do
    PartitionKey.new(%{affinity: :transport, value: transport_binding_id})
  end
end
