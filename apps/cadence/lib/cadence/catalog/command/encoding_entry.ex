defmodule Cadence.Catalog.Command.EncodingEntry do
  @moduledoc """
  Canonical command encoding entry that references arguments or nested layouts.
  """

  alias Cadence.Catalog.Command.{
    Argument,
    EncodingLayout,
    MatchCriteria,
    Normalize,
    Provenance
  }

  alias Cadence.Ids

  @type entry_kind :: :argument_ref | :fixed_value | :nested_layout_ref
  @type bit_offset_from :: :layout_start | :previous_entry | :base_layout_end

  @type t :: %__MODULE__{
          layout_entry_id: binary(),
          entry_kind: entry_kind(),
          argument_id: binary() | nil,
          nested_layout_id: binary() | nil,
          bit_offset: non_neg_integer() | nil,
          bit_offset_from: bit_offset_from(),
          fixed_value: term() | nil,
          fixed_value_size_bits: pos_integer() | nil,
          display_order: integer() | nil,
          include_condition: MatchCriteria.t() | nil,
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :layout_entry_id,
    :entry_kind,
    :argument_id,
    :nested_layout_id,
    :bit_offset,
    :fixed_value,
    :fixed_value_size_bits,
    :display_order,
    :include_condition,
    :provenance,
    bit_offset_from: :layout_start,
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      layout_entry_id: Normalize.get(attrs, :layout_entry_id, Ids.new("command_layout_entry")),
      entry_kind: Normalize.get(attrs, :entry_kind, :argument_ref) |> normalize_entry_kind(),
      argument_id: argument_ref(Normalize.get(attrs, :argument_ref)),
      nested_layout_id: layout_ref(Normalize.get(attrs, :nested_layout_ref)),
      bit_offset: Normalize.get(attrs, :bit_offset),
      bit_offset_from:
        Normalize.get(attrs, :bit_offset_from, :layout_start) |> normalize_bit_offset_from(),
      fixed_value: Normalize.get(attrs, :fixed_value),
      fixed_value_size_bits: Normalize.get(attrs, :fixed_value_size_bits),
      display_order: Normalize.get(attrs, :display_order),
      include_condition: Normalize.nested(attrs, :include_condition, MatchCriteria),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp argument_ref(%Argument{argument_id: argument_id}), do: argument_id
  defp argument_ref(argument_id) when is_binary(argument_id), do: argument_id
  defp argument_ref(_other), do: nil

  defp layout_ref(%EncodingLayout{layout_id: layout_id}), do: layout_id
  defp layout_ref(layout_id) when is_binary(layout_id), do: layout_id
  defp layout_ref(_other), do: nil

  defp normalize_entry_kind(:argument_ref), do: :argument_ref
  defp normalize_entry_kind("argument_ref"), do: :argument_ref
  defp normalize_entry_kind(:fixed_value), do: :fixed_value
  defp normalize_entry_kind("fixed_value"), do: :fixed_value
  defp normalize_entry_kind(:nested_layout_ref), do: :nested_layout_ref
  defp normalize_entry_kind("nested_layout_ref"), do: :nested_layout_ref
  defp normalize_entry_kind(_other), do: :argument_ref

  defp normalize_bit_offset_from(:layout_start), do: :layout_start
  defp normalize_bit_offset_from("layout_start"), do: :layout_start
  defp normalize_bit_offset_from(:previous_entry), do: :previous_entry
  defp normalize_bit_offset_from("previous_entry"), do: :previous_entry
  defp normalize_bit_offset_from(:base_layout_end), do: :base_layout_end
  defp normalize_bit_offset_from("base_layout_end"), do: :base_layout_end
  defp normalize_bit_offset_from(_other), do: :layout_start
end
