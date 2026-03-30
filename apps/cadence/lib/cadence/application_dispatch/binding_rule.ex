defmodule Cadence.ApplicationDispatch.BindingRule do
  @moduledoc """
  Mission-scoped routing rule for packet-to-handler dispatch.
  """

  alias Cadence.ApplicationDispatch.{CapabilityConfig, Selector}
  alias Cadence.Ids
  alias Cadence.Telemetry.PacketDefinition

  @type fanout_mode :: :exclusive | :multi

  @type t :: %__MODULE__{
          binding_rule_id: binary(),
          capability_instance_id: binary() | nil,
          handler_key: atom() | nil,
          selector: Selector.t(),
          capability_config: CapabilityConfig.t() | nil,
          priority: non_neg_integer(),
          fanout_mode: fanout_mode(),
          handler_configuration: term()
        }

  defstruct [
    :binding_rule_id,
    :capability_instance_id,
    :handler_key,
    :selector,
    :capability_config,
    :handler_configuration,
    priority: 100,
    fanout_mode: :exclusive
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      binding_rule_id: Map.get(attrs, :binding_rule_id, Ids.new("binding_rule")),
      capability_instance_id:
        Map.get(attrs, :capability_instance_id, Map.get(attrs, "capability_instance_id")),
      handler_key:
        attrs
        |> Map.get(:handler_key, Map.get(attrs, "handler_key"))
        |> normalize_existing_atom(),
      selector: build_selector(attrs),
      capability_config: build_capability_config(attrs),
      priority: Map.get(attrs, :priority, Map.get(attrs, "priority", 100)),
      fanout_mode:
        attrs
        |> Map.get(:fanout_mode, Map.get(attrs, "fanout_mode", :exclusive))
        |> normalize_existing_atom(),
      handler_configuration:
        Map.get(attrs, :handler_configuration, Map.get(attrs, "handler_configuration"))
    }
  end

  @spec capability_instance_id(t()) :: binary() | nil
  def capability_instance_id(%__MODULE__{capability_instance_id: capability_instance_id}),
    do: capability_instance_id

  @spec target_scope(t()) :: atom()
  def target_scope(%__MODULE__{selector: %Selector{scope: scope}}), do: scope.target_scope

  @spec source_endpoint_ref(t()) :: binary() | nil
  def source_endpoint_ref(%__MODULE__{selector: %Selector{scope: scope}}),
    do: scope.source_endpoint_ref

  @spec packet_kind(t()) :: atom() | nil
  def packet_kind(%__MODULE__{selector: %Selector{match: match}}), do: match.packet_kind

  @spec apid(t()) :: non_neg_integer() | nil
  def apid(%__MODULE__{selector: %Selector{match: match}}), do: match.apid

  @spec capability_config(t()) :: CapabilityConfig.t() | nil
  def capability_config(%__MODULE__{capability_config: %CapabilityConfig{} = capability_config}),
    do: capability_config

  def capability_config(%__MODULE__{handler_configuration: nil}), do: CapabilityConfig.none()

  def capability_config(%__MODULE__{
        handler_configuration: %PacketDefinition{} = packet_definition
      }) do
    CapabilityConfig.reference_packet_definition(packet_definition)
  end

  def capability_config(%__MODULE__{handler_configuration: handler_configuration})
      when is_map(handler_configuration) and not is_struct(handler_configuration) do
    CapabilityConfig.inline(handler_configuration)
  end

  def capability_config(%__MODULE__{}), do: nil

  @spec configuration(t()) :: term()
  def configuration(%__MODULE__{handler_configuration: handler_configuration}),
    do: handler_configuration

  defp build_selector(%{selector: %Selector{} = selector}), do: selector
  defp build_selector(%{"selector" => %Selector{} = selector}), do: selector

  defp build_selector(%{selector: selector_attrs}) when is_map(selector_attrs),
    do: Selector.new(selector_attrs)

  defp build_selector(%{"selector" => selector_attrs}) when is_map(selector_attrs),
    do: Selector.new(selector_attrs)

  defp build_selector(attrs), do: Selector.new(attrs)

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

  defp build_capability_config(%{handler_configuration: nil}), do: CapabilityConfig.none()

  defp build_capability_config(%{"handler_configuration" => nil}), do: CapabilityConfig.none()

  defp build_capability_config(%{handler_configuration: %PacketDefinition{} = packet_definition}) do
    CapabilityConfig.reference_packet_definition(packet_definition)
  end

  defp build_capability_config(%{
         "handler_configuration" => %PacketDefinition{} = packet_definition
       }) do
    CapabilityConfig.reference_packet_definition(packet_definition)
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

  defp normalize_existing_atom(nil), do: nil
  defp normalize_existing_atom(value) when is_atom(value), do: value
  defp normalize_existing_atom(value) when is_binary(value), do: String.to_existing_atom(value)
end
