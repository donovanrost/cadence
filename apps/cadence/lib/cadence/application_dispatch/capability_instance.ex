defmodule Cadence.ApplicationDispatch.CapabilityInstance do
  @moduledoc """
  Governed capability instance referenced by selector bindings.
  """

  alias Cadence.ApplicationDispatch.CapabilityConfig
  alias Cadence.Ids
  alias Cadence.Telemetry.PacketDefinition

  @type target_scope :: :mission | :source_endpoint
  @type lifecycle_state :: :active | :disabled

  @type t :: %__MODULE__{
          capability_instance_id: binary(),
          family_key: atom() | nil,
          target_scope: target_scope(),
          source_endpoint_ref: binary() | nil,
          capability_config: CapabilityConfig.t() | nil,
          lifecycle_state: lifecycle_state(),
          runtime_configuration: term()
        }

  defstruct [
    :capability_instance_id,
    :family_key,
    :target_scope,
    :source_endpoint_ref,
    :capability_config,
    :runtime_configuration,
    lifecycle_state: :active
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    family_key = Map.get(attrs, :family_key, Map.get(attrs, "family_key"))

    %__MODULE__{
      capability_instance_id:
        Map.get(
          attrs,
          :capability_instance_id,
          Map.get(attrs, "capability_instance_id", Ids.new("capability_instance"))
        ),
      family_key: normalize_family_key(family_key),
      target_scope:
        Map.get(attrs, :target_scope, Map.get(attrs, "target_scope", :mission))
        |> normalize_target_scope(),
      source_endpoint_ref:
        Map.get(attrs, :source_endpoint_ref, Map.get(attrs, "source_endpoint_ref")),
      capability_config: build_capability_config(attrs),
      lifecycle_state:
        Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_lifecycle_state(),
      runtime_configuration:
        Map.get(attrs, :runtime_configuration, Map.get(attrs, "runtime_configuration")) ||
          Map.get(attrs, :handler_configuration, Map.get(attrs, "handler_configuration"))
    }
  end

  @spec capability_config(t()) :: CapabilityConfig.t() | nil
  def capability_config(%__MODULE__{capability_config: %CapabilityConfig{} = capability_config}),
    do: capability_config

  def capability_config(%__MODULE__{runtime_configuration: nil}), do: CapabilityConfig.none()

  def capability_config(%__MODULE__{
        runtime_configuration: %PacketDefinition{} = packet_definition
      }) do
    CapabilityConfig.reference_packet_definition(packet_definition)
  end

  def capability_config(%__MODULE__{runtime_configuration: runtime_configuration})
      when is_map(runtime_configuration) and not is_struct(runtime_configuration) do
    CapabilityConfig.inline(runtime_configuration)
  end

  def capability_config(%__MODULE__{}), do: nil

  @spec configuration(t()) :: term()
  def configuration(%__MODULE__{runtime_configuration: runtime_configuration}),
    do: runtime_configuration

  defp build_capability_config(%{capability_config: %CapabilityConfig{} = capability_config}),
    do: capability_config

  defp build_capability_config(%{"capability_config" => %CapabilityConfig{} = capability_config}),
    do: capability_config

  defp build_capability_config(%{capability_config: capability_config_attrs})
       when is_map(capability_config_attrs),
       do: CapabilityConfig.new(capability_config_attrs)

  defp build_capability_config(%{"capability_config" => capability_config_attrs})
       when is_map(capability_config_attrs),
       do: CapabilityConfig.new(capability_config_attrs)

  defp build_capability_config(%{runtime_configuration: nil}), do: CapabilityConfig.none()
  defp build_capability_config(%{"runtime_configuration" => nil}), do: CapabilityConfig.none()
  defp build_capability_config(%{handler_configuration: nil}), do: CapabilityConfig.none()
  defp build_capability_config(%{"handler_configuration" => nil}), do: CapabilityConfig.none()

  defp build_capability_config(%{runtime_configuration: %PacketDefinition{} = packet_definition}) do
    CapabilityConfig.reference_packet_definition(packet_definition)
  end

  defp build_capability_config(%{
         "runtime_configuration" => %PacketDefinition{} = packet_definition
       }) do
    CapabilityConfig.reference_packet_definition(packet_definition)
  end

  defp build_capability_config(%{handler_configuration: %PacketDefinition{} = packet_definition}) do
    CapabilityConfig.reference_packet_definition(packet_definition)
  end

  defp build_capability_config(%{
         "handler_configuration" => %PacketDefinition{} = packet_definition
       }) do
    CapabilityConfig.reference_packet_definition(packet_definition)
  end

  defp build_capability_config(%{runtime_configuration: runtime_configuration})
       when is_map(runtime_configuration) and not is_struct(runtime_configuration) do
    CapabilityConfig.inline(runtime_configuration)
  end

  defp build_capability_config(%{"runtime_configuration" => runtime_configuration})
       when is_map(runtime_configuration) and not is_struct(runtime_configuration) do
    CapabilityConfig.inline(runtime_configuration)
  end

  defp build_capability_config(%{handler_configuration: handler_configuration})
       when is_map(handler_configuration) and not is_struct(handler_configuration) do
    CapabilityConfig.inline(handler_configuration)
  end

  defp build_capability_config(%{"handler_configuration" => handler_configuration})
       when is_map(handler_configuration) and not is_struct(handler_configuration) do
    CapabilityConfig.inline(handler_configuration)
  end

  defp build_capability_config(_attrs), do: nil

  defp normalize_family_key(family_key) when is_atom(family_key), do: family_key

  defp normalize_family_key(family_key) when is_binary(family_key),
    do: String.to_existing_atom(family_key)

  defp normalize_family_key(nil), do: nil

  defp normalize_target_scope(target_scope) when is_atom(target_scope), do: target_scope

  defp normalize_target_scope(target_scope) when is_binary(target_scope),
    do: String.to_existing_atom(target_scope)

  defp normalize_lifecycle_state(lifecycle_state) when is_atom(lifecycle_state),
    do: lifecycle_state

  defp normalize_lifecycle_state(lifecycle_state) when is_binary(lifecycle_state),
    do: String.to_existing_atom(lifecycle_state)
end
