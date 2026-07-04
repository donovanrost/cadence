defmodule Cadence.Dashboards.Field do
  @moduledoc """
  Columnar field in a dashboard Frame.
  """

  alias Cadence.Dashboards.ContractNormalization

  @type kind :: :time | :number | :string | :boolean | :enum

  @type t :: %__MODULE__{
          name: binary(),
          kind: kind(),
          values: list(),
          metadata: map()
        }

  defstruct [:name, :kind, values: [], metadata: %{}]

  @kinds [:time, :number, :string, :boolean, :enum]

  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @spec new(map() | t()) :: t()
  def new(attrs), do: normalize(attrs)

  @spec normalize(map() | t()) :: t() | nil
  def normalize(%__MODULE__{} = field) do
    %__MODULE__{
      field
      | kind: ContractNormalization.known_atom(field.kind, @kinds),
        values: ContractNormalization.list_or_default(field.values),
        metadata: ContractNormalization.map_or_default(field.metadata)
    }
  end

  def normalize(field) when is_map(field) do
    %__MODULE__{
      name: ContractNormalization.attr(field, :name),
      kind:
        field
        |> ContractNormalization.attr(:kind)
        |> ContractNormalization.known_atom(@kinds),
      values:
        field
        |> ContractNormalization.attr(:values, [])
        |> ContractNormalization.list_or_default(),
      metadata:
        field
        |> ContractNormalization.attr(:metadata, %{})
        |> ContractNormalization.map_or_default()
    }
  end

  def normalize(_other), do: nil
end
