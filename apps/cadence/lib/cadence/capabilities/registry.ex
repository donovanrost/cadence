defmodule Cadence.Capabilities.Registry do
  @moduledoc """
  Registry of first-party capability families available to the Cadence runtime.
  """

  alias Cadence.ApplicationDispatch.{BindingRule, CapabilityInstance}
  alias Cadence.Capabilities.{Descriptor, ValidationContext}
  alias Cadence.Capabilities.ManagedApplications.PacketCounter
  alias Cadence.Capabilities.TransportExtensions.{HeartbeatMonitor, UplinkGateway}
  alias Cadence.Telemetry.Handlers.DefinitionBoundTelemetryHandler

  @type t :: %{required(atom()) => module()}

  @spec default() :: t()
  def default do
    %{
      definition_bound_telemetry: DefinitionBoundTelemetryHandler,
      packet_counter: PacketCounter,
      heartbeat_monitor: HeartbeatMonitor,
      uplink_gateway: UplinkGateway
    }
  end

  @spec fetch(t(), atom()) :: {:ok, module()} | :error
  def fetch(registry, family_key) when is_map(registry) and is_atom(family_key) do
    Map.fetch(registry, family_key)
  end

  @spec fetch_descriptor(t(), atom()) :: {:ok, Descriptor.t()} | {:error, term()}
  def fetch_descriptor(registry, family_key) when is_map(registry) and is_atom(family_key) do
    with {:ok, family_module} <- fetch_or_error(registry, family_key),
         %Descriptor{} = descriptor <- family_module.descriptor(),
         true <- descriptor.family_key == family_key do
      {:ok, descriptor}
    else
      false ->
        {:error, {:invalid_capability_descriptor, family_key}}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, {:invalid_capability_descriptor, family_key}}
    end
  end

  @spec validate_binding_rule(t(), BindingRule.t(), ValidationContext.t()) ::
          :ok | {:error, term()}
  def validate_binding_rule(
        registry,
        %BindingRule{handler_key: family_key, handler_configuration: handler_configuration},
        %ValidationContext{} = validation_context
      )
      when is_map(registry) and is_atom(family_key) do
    with {:ok, family_module} <- fetch_or_error(registry, family_key),
         {:ok, descriptor} <- fetch_descriptor(registry, family_key),
         :ok <- validate_scope(descriptor, validation_context.target_scope),
         :ok <- validate_input_stage(descriptor, validation_context.input_stage),
         :ok <- family_module.validate_config(handler_configuration, validation_context) do
      :ok
    end
  end

  @spec validate_capability_instance(t(), CapabilityInstance.t(), ValidationContext.t()) ::
          :ok | {:error, term()}
  def validate_capability_instance(
        registry,
        %CapabilityInstance{family_key: family_key, runtime_configuration: runtime_configuration},
        %ValidationContext{} = validation_context
      )
      when is_map(registry) and is_atom(family_key) do
    with {:ok, family_module} <- fetch_or_error(registry, family_key),
         {:ok, descriptor} <- fetch_descriptor(registry, family_key),
         :ok <- validate_scope(descriptor, validation_context.target_scope),
         :ok <- family_module.validate_config(runtime_configuration, validation_context) do
      :ok
    end
  end

  defp fetch_or_error(registry, family_key) do
    case fetch(registry, family_key) do
      {:ok, family_module} -> {:ok, family_module}
      :error -> {:error, {:unknown_capability_family, family_key}}
    end
  end

  defp validate_scope(
         %Descriptor{family_key: family_key, supported_scopes: supported_scopes},
         scope
       ) do
    if scope in supported_scopes do
      :ok
    else
      {:error, {:unsupported_capability_scope, family_key, scope}}
    end
  end

  defp validate_input_stage(%Descriptor{input_stages: []}, _input_stage),
    do: :ok

  defp validate_input_stage(%Descriptor{family_key: family_key}, nil) do
    {:error, {:missing_capability_input_stage, family_key}}
  end

  defp validate_input_stage(
         %Descriptor{family_key: family_key, input_stages: input_stages},
         input_stage
       ) do
    if input_stage in input_stages do
      :ok
    else
      {:error, {:unsupported_capability_input_stage, family_key, input_stage}}
    end
  end
end
