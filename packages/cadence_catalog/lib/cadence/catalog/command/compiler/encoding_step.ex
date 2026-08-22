defmodule Cadence.Catalog.Command.Compiler.EncodingStep do
  @moduledoc """
  One compiled command encoding step used by the runtime encoder boundary.
  """

  @type step_kind :: :argument_ref | :fixed_value
  @type bit_offset_from :: :layout_start

  @type t :: %__MODULE__{
          step_kind: step_kind(),
          argument_id: binary() | nil,
          bit_offset: non_neg_integer(),
          bit_offset_from: bit_offset_from(),
          size_bits: pos_integer(),
          fixed_value: term() | nil,
          display_order: integer() | nil,
          metadata: map()
        }

  defstruct [
    :step_kind,
    :argument_id,
    :bit_offset,
    :size_bits,
    :fixed_value,
    :display_order,
    bit_offset_from: :layout_start,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      step_kind: Map.fetch!(attrs, :step_kind),
      argument_id: Map.get(attrs, :argument_id),
      bit_offset: Map.fetch!(attrs, :bit_offset),
      bit_offset_from: Map.get(attrs, :bit_offset_from, :layout_start),
      size_bits: Map.fetch!(attrs, :size_bits),
      fixed_value: Map.get(attrs, :fixed_value),
      display_order: Map.get(attrs, :display_order),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
