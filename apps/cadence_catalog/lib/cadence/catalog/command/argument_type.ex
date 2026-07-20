defmodule Cadence.Catalog.Command.ArgumentType do
  @moduledoc """
  Canonical reusable command argument type definition.
  """

  alias Cadence.Catalog.Command.{
    AggregateMember,
    ArrayShape,
    EnumerationValue,
    Normalize,
    Provenance,
    TypeEncoding
  }

  alias Cadence.Catalog.Ids

  @type base_type ::
          :integer
          | :float
          | :string
          | :binary
          | :boolean
          | :enumerated
          | :aggregate
          | :array
          | :absolute_time
          | :relative_time

  @type t :: %__MODULE__{
          argument_type_id: binary(),
          snapshot_id: binary(),
          name: binary(),
          description: binary() | nil,
          base_type: base_type(),
          encoding: TypeEncoding.t() | nil,
          enumerations: [EnumerationValue.t()],
          aggregate_members: [AggregateMember.t()],
          array_shape: ArrayShape.t() | nil,
          display_unit: binary() | nil,
          valid_range_min: number() | nil,
          valid_range_max: number() | nil,
          valid_range_applies_to_engineering: boolean(),
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :argument_type_id,
    :snapshot_id,
    :name,
    :description,
    :base_type,
    :encoding,
    :array_shape,
    :display_unit,
    :valid_range_min,
    :valid_range_max,
    :provenance,
    enumerations: [],
    aggregate_members: [],
    valid_range_applies_to_engineering: true,
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      argument_type_id: Normalize.get(attrs, :argument_type_id, Ids.new("command_argument_type")),
      snapshot_id: Normalize.fetch!(attrs, :snapshot_id),
      name: Normalize.fetch!(attrs, :name),
      description: Normalize.get(attrs, :description),
      base_type: Normalize.get(attrs, :base_type, :integer) |> normalize_base_type(),
      encoding: Normalize.nested(attrs, :encoding, TypeEncoding),
      enumerations: Normalize.nested_list(attrs, :enumerations, EnumerationValue),
      aggregate_members: Normalize.nested_list(attrs, :aggregate_members, AggregateMember),
      array_shape: Normalize.nested(attrs, :array_shape, ArrayShape),
      display_unit: Normalize.get(attrs, :display_unit),
      valid_range_min: Normalize.get(attrs, :valid_range_min),
      valid_range_max: Normalize.get(attrs, :valid_range_max),
      valid_range_applies_to_engineering:
        Normalize.get(attrs, :valid_range_applies_to_engineering, true),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp normalize_base_type(:integer), do: :integer
  defp normalize_base_type("integer"), do: :integer
  defp normalize_base_type(:float), do: :float
  defp normalize_base_type("float"), do: :float
  defp normalize_base_type(:string), do: :string
  defp normalize_base_type("string"), do: :string
  defp normalize_base_type(:binary), do: :binary
  defp normalize_base_type("binary"), do: :binary
  defp normalize_base_type(:boolean), do: :boolean
  defp normalize_base_type("boolean"), do: :boolean
  defp normalize_base_type(:enumerated), do: :enumerated
  defp normalize_base_type("enumerated"), do: :enumerated
  defp normalize_base_type(:aggregate), do: :aggregate
  defp normalize_base_type("aggregate"), do: :aggregate
  defp normalize_base_type(:array), do: :array
  defp normalize_base_type("array"), do: :array
  defp normalize_base_type(:absolute_time), do: :absolute_time
  defp normalize_base_type("absolute_time"), do: :absolute_time
  defp normalize_base_type(:relative_time), do: :relative_time
  defp normalize_base_type("relative_time"), do: :relative_time
  defp normalize_base_type(_other), do: :integer
end
