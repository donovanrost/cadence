defmodule Cadence.Catalog.Command.Compiler.ArgumentSpec do
  @moduledoc """
  Runtime-facing command argument specification compiled from canonical command
  catalog data.
  """

  alias Cadence.Catalog.Command.TypeEncoding

  @type base_type ::
          :integer
          | :float
          | :string
          | :binary
          | :boolean
          | :enumerated

  @type t :: %__MODULE__{
          argument_id: binary(),
          name: binary(),
          description: binary() | nil,
          base_type: base_type(),
          required: boolean(),
          encoding: TypeEncoding.t(),
          default_value: term() | nil,
          fixed_value: term() | nil,
          hazardous_values: [term()],
          metadata: map()
        }

  defstruct [
    :argument_id,
    :name,
    :description,
    :base_type,
    :required,
    :encoding,
    :default_value,
    :fixed_value,
    hazardous_values: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      argument_id: Map.fetch!(attrs, :argument_id),
      name: Map.fetch!(attrs, :name),
      description: Map.get(attrs, :description),
      base_type: Map.fetch!(attrs, :base_type),
      required: Map.get(attrs, :required, true),
      encoding: Map.fetch!(attrs, :encoding),
      default_value: Map.get(attrs, :default_value),
      fixed_value: Map.get(attrs, :fixed_value),
      hazardous_values: Map.get(attrs, :hazardous_values, []),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
