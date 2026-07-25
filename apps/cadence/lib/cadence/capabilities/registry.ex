defmodule Cadence.Capabilities.Registry do
  @moduledoc """
  Registry of first-party capability families available to the Cadence runtime.
  """

  alias Cadence.ApplicationDispatch.{BindingRule, CapabilityInstance}
  alias Cadence.Capabilities.{DefinitionRegistry, Descriptor, ValidationContext}
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
    DefinitionRegistry.fetch_descriptor(registry, family_key)
  end

  @spec validate_binding_rule(t(), BindingRule.t(), ValidationContext.t()) ::
          :ok | {:error, term()}
  def validate_binding_rule(
        registry,
        %BindingRule{handler_key: family_key} = binding_rule,
        %ValidationContext{} = validation_context
      )
      when is_map(registry) and is_atom(family_key) do
    DefinitionRegistry.validate_binding_rule(registry, binding_rule, validation_context)
  end

  @spec validate_capability_instance(t(), CapabilityInstance.t(), ValidationContext.t()) ::
          :ok | {:error, term()}
  def validate_capability_instance(
        registry,
        %CapabilityInstance{family_key: family_key} = capability_instance,
        %ValidationContext{} = validation_context
      )
      when is_map(registry) and is_atom(family_key) do
    DefinitionRegistry.validate_capability_instance(
      registry,
      capability_instance,
      validation_context
    )
  end
end
