defmodule Cadence.Catalog.Telemetry.Compiler.Result do
  @moduledoc """
  Output of compiling a canonical telemetry snapshot into current runtime-facing
  artifacts.
  """

  alias Cadence.Catalog.Diagnostic
  alias Cadence.Catalog.Telemetry.Compiler.SelectorInput
  alias Cadence.Telemetry.PacketDefinition

  @type t :: %__MODULE__{
          packet_definitions: [PacketDefinition.t()],
          selector_inputs: [SelectorInput.t()],
          diagnostics: [Diagnostic.t()]
        }

  defstruct packet_definitions: [], selector_inputs: [], diagnostics: []

  @spec new(map()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) do
    %__MODULE__{
      packet_definitions: Map.get(attrs, :packet_definitions, []),
      selector_inputs: Map.get(attrs, :selector_inputs, []),
      diagnostics: Map.get(attrs, :diagnostics, [])
    }
  end
end
