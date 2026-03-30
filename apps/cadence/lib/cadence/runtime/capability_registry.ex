defmodule Cadence.Runtime.CapabilityRegistry do
  @moduledoc """
  Supervised runtime service boundary around the registered first-party
  capability families.
  """

  use GenServer

  alias Cadence.Capabilities.{Descriptor, ExecutionContext, ExecutionResult}
  alias Cadence.Capabilities.Registry, as: StaticRegistry
  alias Cadence.Runtime.ActivationContext

  @type state :: %{
          families: StaticRegistry.t(),
          descriptors: %{required(atom()) => Descriptor.t()}
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec fetch_family(atom()) :: {:ok, module()} | {:error, term()}
  def fetch_family(family_key) when is_atom(family_key) do
    GenServer.call(__MODULE__, {:fetch_family, family_key})
  end

  @spec fetch_descriptor(atom()) :: {:ok, Descriptor.t()} | {:error, term()}
  def fetch_descriptor(family_key) when is_atom(family_key) do
    GenServer.call(__MODULE__, {:fetch_descriptor, family_key})
  end

  @spec build_instance(atom(), term(), ActivationContext.t()) :: {:ok, term()} | {:error, term()}
  def build_instance(family_key, configuration, %ActivationContext{} = activation_context)
      when is_atom(family_key) do
    GenServer.call(__MODULE__, {:build_instance, family_key, configuration, activation_context})
  end

  @spec init_managed_application(atom(), term(), ExecutionContext.t()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def init_managed_application(family_key, configuration, %ExecutionContext{} = execution_context)
      when is_atom(family_key) do
    GenServer.call(
      __MODULE__,
      {:init_managed_application, family_key, configuration, execution_context}
    )
  end

  @spec handle_managed_record(atom(), term(), term(), ExecutionContext.t()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def handle_managed_record(
        family_key,
        record,
        application_state,
        %ExecutionContext{} = execution_context
      )
      when is_atom(family_key) do
    GenServer.call(
      __MODULE__,
      {:handle_managed_record, family_key, record, application_state, execution_context}
    )
  end

  @spec handle_managed_timer(atom(), binary(), term(), ExecutionContext.t()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def handle_managed_timer(
        family_key,
        timer_key,
        application_state,
        %ExecutionContext{} = execution_context
      )
      when is_atom(family_key) and is_binary(timer_key) do
    GenServer.call(
      __MODULE__,
      {:handle_managed_timer, family_key, timer_key, application_state, execution_context}
    )
  end

  @spec snapshot_managed_state(atom(), term(), ExecutionContext.t()) ::
          {:ok, term()} | {:error, term()}
  def snapshot_managed_state(
        family_key,
        application_state,
        %ExecutionContext{} = execution_context
      )
      when is_atom(family_key) do
    GenServer.call(
      __MODULE__,
      {:snapshot_managed_state, family_key, application_state, execution_context}
    )
  end

  @spec init_transport_extension(atom(), term(), ExecutionContext.t()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def init_transport_extension(family_key, configuration, %ExecutionContext{} = execution_context)
      when is_atom(family_key) do
    GenServer.call(
      __MODULE__,
      {:init_transport_extension, family_key, configuration, execution_context}
    )
  end

  @spec handle_transport_event(atom(), term(), term(), ExecutionContext.t()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def handle_transport_event(
        family_key,
        event,
        transport_state,
        %ExecutionContext{} = execution_context
      )
      when is_atom(family_key) do
    GenServer.call(
      __MODULE__,
      {:handle_transport_event, family_key, event, transport_state, execution_context}
    )
  end

  @spec handle_transport_control_input(atom(), term(), term(), ExecutionContext.t()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def handle_transport_control_input(
        family_key,
        control_input,
        transport_state,
        %ExecutionContext{} = execution_context
      )
      when is_atom(family_key) do
    GenServer.call(
      __MODULE__,
      {:handle_transport_control_input, family_key, control_input, transport_state,
       execution_context}
    )
  end

  @spec handle_transport_timer(atom(), binary(), term(), ExecutionContext.t()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  def handle_transport_timer(
        family_key,
        timer_key,
        transport_state,
        %ExecutionContext{} = execution_context
      )
      when is_atom(family_key) and is_binary(timer_key) do
    GenServer.call(
      __MODULE__,
      {:handle_transport_timer, family_key, timer_key, transport_state, execution_context}
    )
  end

  @spec snapshot_transport_state(atom(), term(), ExecutionContext.t()) ::
          {:ok, term()} | {:error, term()}
  def snapshot_transport_state(
        family_key,
        transport_state,
        %ExecutionContext{} = execution_context
      )
      when is_atom(family_key) do
    GenServer.call(
      __MODULE__,
      {:snapshot_transport_state, family_key, transport_state, execution_context}
    )
  end

  @impl true
  def init(_opts) do
    families = StaticRegistry.default()

    descriptors =
      Enum.reduce_while(families, {:ok, %{}}, fn {family_key, _family_module}, {:ok, acc} ->
        case StaticRegistry.fetch_descriptor(families, family_key) do
          {:ok, %Descriptor{} = descriptor} ->
            {:cont, {:ok, Map.put(acc, family_key, descriptor)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case descriptors do
      {:ok, descriptor_map} ->
        {:ok, %{families: families, descriptors: descriptor_map}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:fetch_family, family_key}, _from, %{families: families} = state) do
    reply =
      case Map.fetch(families, family_key) do
        {:ok, family_module} -> {:ok, family_module}
        :error -> {:error, {:unknown_capability_family, family_key}}
      end

    {:reply, reply, state}
  end

  def handle_call({:fetch_descriptor, family_key}, _from, %{descriptors: descriptors} = state) do
    reply =
      case Map.fetch(descriptors, family_key) do
        {:ok, descriptor} -> {:ok, descriptor}
        :error -> {:error, {:unknown_capability_family, family_key}}
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:build_instance, family_key, configuration, %ActivationContext{} = activation_context},
        _from,
        state
      ) do
    reply =
      with {:ok, family_module} <- fetch_family_reply(state, family_key) do
        family_module.build_instance(configuration, activation_context)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:init_managed_application, family_key, configuration,
         %ExecutionContext{} = execution_context},
        _from,
        state
      ) do
    reply =
      with {:ok, family_module} <- fetch_family_reply(state, family_key),
           :ok <- validate_managed_application_family(family_module) do
        family_module.init_instance(configuration, execution_context)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:handle_managed_record, family_key, record, application_state,
         %ExecutionContext{} = execution_context},
        _from,
        state
      ) do
    reply =
      with {:ok, family_module} <- fetch_family_reply(state, family_key),
           :ok <- validate_managed_application_family(family_module) do
        family_module.handle_record(record, application_state, execution_context)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:handle_managed_timer, family_key, timer_key, application_state,
         %ExecutionContext{} = execution_context},
        _from,
        state
      ) do
    reply =
      with {:ok, family_module} <- fetch_family_reply(state, family_key),
           :ok <- validate_managed_application_family(family_module) do
        family_module.handle_timer(timer_key, application_state, execution_context)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:snapshot_managed_state, family_key, application_state,
         %ExecutionContext{} = execution_context},
        _from,
        state
      ) do
    reply =
      with {:ok, family_module} <- fetch_family_reply(state, family_key),
           :ok <- validate_managed_application_family(family_module) do
        family_module.snapshot_state(application_state, execution_context)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:init_transport_extension, family_key, configuration,
         %ExecutionContext{} = execution_context},
        _from,
        state
      ) do
    reply =
      with {:ok, family_module} <- fetch_family_reply(state, family_key),
           :ok <- validate_transport_extension_family(family_module) do
        family_module.init_transport(configuration, execution_context)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:handle_transport_event, family_key, event, transport_state,
         %ExecutionContext{} = execution_context},
        _from,
        state
      ) do
    reply =
      with {:ok, family_module} <- fetch_family_reply(state, family_key),
           :ok <- validate_transport_extension_family(family_module) do
        family_module.handle_transport_event(event, transport_state, execution_context)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:handle_transport_control_input, family_key, control_input, transport_state,
         %ExecutionContext{} = execution_context},
        _from,
        state
      ) do
    reply =
      with {:ok, family_module} <- fetch_family_reply(state, family_key),
           :ok <- validate_transport_extension_family(family_module) do
        family_module.handle_control_input(control_input, transport_state, execution_context)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:handle_transport_timer, family_key, timer_key, transport_state,
         %ExecutionContext{} = execution_context},
        _from,
        state
      ) do
    reply =
      with {:ok, family_module} <- fetch_family_reply(state, family_key),
           :ok <- validate_transport_extension_family(family_module) do
        family_module.handle_timer(timer_key, transport_state, execution_context)
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:snapshot_transport_state, family_key, transport_state,
         %ExecutionContext{} = execution_context},
        _from,
        state
      ) do
    reply =
      with {:ok, family_module} <- fetch_family_reply(state, family_key),
           :ok <- validate_transport_extension_family(family_module) do
        family_module.snapshot_state(transport_state, execution_context)
      end

    {:reply, reply, state}
  end

  defp fetch_family_reply(%{families: families}, family_key) do
    case Map.fetch(families, family_key) do
      {:ok, family_module} -> {:ok, family_module}
      :error -> {:error, {:unknown_capability_family, family_key}}
    end
  end

  defp validate_managed_application_family(family_module) do
    if function_exported?(family_module, :init_instance, 2) and
         function_exported?(family_module, :handle_record, 3) and
         function_exported?(family_module, :handle_timer, 3) and
         function_exported?(family_module, :snapshot_state, 2) do
      :ok
    else
      {:error, {:not_a_managed_application_family, family_module}}
    end
  end

  defp validate_transport_extension_family(family_module) do
    if function_exported?(family_module, :init_transport, 2) and
         function_exported?(family_module, :handle_transport_event, 3) and
         function_exported?(family_module, :handle_control_input, 3) and
         function_exported?(family_module, :handle_timer, 3) and
         function_exported?(family_module, :snapshot_state, 2) do
      :ok
    else
      {:error, {:not_a_transport_extension_family, family_module}}
    end
  end
end
