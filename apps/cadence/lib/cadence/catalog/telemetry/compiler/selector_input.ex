defmodule Cadence.Catalog.Telemetry.Compiler.SelectorInput do
  @moduledoc """
  Selector-facing compilation output for one canonical telemetry packet.

  This is intentionally narrower than a full binding rule or binding set. It
  captures the information needed to later build governed runtime routing for a
  compiled packet definition.
  """

  alias Cadence.ApplicationDispatch.{CapabilityConfig, Selector}
  alias Cadence.Catalog.Telemetry.Normalize
  alias Cadence.Ids

  @type t :: %__MODULE__{
          selector_input_id: binary(),
          packet_id: binary(),
          packet_definition_id: binary(),
          capability_instance_id: binary(),
          capability_family_key: atom(),
          selector: Selector.t(),
          capability_config: CapabilityConfig.t(),
          metadata: map()
        }

  defstruct [
    :selector_input_id,
    :packet_id,
    :packet_definition_id,
    :capability_instance_id,
    :capability_family_key,
    :selector,
    :capability_config,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      selector_input_id: Normalize.get(attrs, :selector_input_id, Ids.new("selector_input")),
      packet_id: Normalize.fetch!(attrs, :packet_id),
      packet_definition_id: Normalize.fetch!(attrs, :packet_definition_id),
      capability_instance_id: Normalize.fetch!(attrs, :capability_instance_id),
      capability_family_key:
        Normalize.get(attrs, :capability_family_key, :definition_bound_telemetry),
      selector: build_selector(attrs),
      capability_config: build_capability_config(attrs),
      metadata: Normalize.get(attrs, :metadata, %{})
    }
  end

  defp build_selector(%{selector: %Selector{} = selector}), do: selector
  defp build_selector(%{"selector" => %Selector{} = selector}), do: selector

  defp build_selector(%{selector: selector_attrs}) when is_map(selector_attrs),
    do: Selector.new(selector_attrs)

  defp build_selector(%{"selector" => selector_attrs}) when is_map(selector_attrs),
    do: Selector.new(selector_attrs)

  defp build_selector(attrs) do
    Selector.new(attrs)
  end

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

  defp build_capability_config(_attrs), do: CapabilityConfig.none()
end
