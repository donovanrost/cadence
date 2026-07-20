defmodule Cadence.Catalog.Telemetry.Compiler.SelectorInput do
  @moduledoc """
  Portable selector-facing compilation output for one canonical telemetry
  packet.

  Consumers project these plain values into their own routing, governance, or
  activation types.
  """

  alias Cadence.Catalog.Ids
  alias Cadence.Catalog.Telemetry.Normalize

  @type t :: %__MODULE__{
          selector_input_id: binary(),
          packet_id: binary(),
          packet_definition_id: binary(),
          capability_instance_id: binary(),
          capability_family_key: atom(),
          selector: map(),
          capability_config: map(),
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
      selector: Normalize.get(attrs, :selector, default_selector()),
      capability_config: Normalize.get(attrs, :capability_config, default_capability_config()),
      metadata: Normalize.get(attrs, :metadata, %{})
    }
  end

  defp default_selector do
    %{
      scope: %{target_scope: :mission, source_endpoint_ref: nil},
      match: %{packet_kind: nil, apid: nil}
    }
  end

  defp default_capability_config do
    %{config_type: :none, document: %{}}
  end
end
