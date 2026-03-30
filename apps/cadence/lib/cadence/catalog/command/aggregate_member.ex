defmodule Cadence.Catalog.Command.AggregateMember do
  @moduledoc """
  One member of a canonical aggregate command argument type.
  """

  alias Cadence.Catalog.Command.Normalize

  @type t :: %__MODULE__{
          name: binary(),
          argument_type_id: binary(),
          description: binary() | nil,
          initial_value: term() | nil
        }

  defstruct [:name, :argument_type_id, :description, :initial_value]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      name: Normalize.fetch!(attrs, :name),
      argument_type_id: Normalize.fetch!(attrs, :argument_type_id),
      description: Normalize.get(attrs, :description),
      initial_value: Normalize.get(attrs, :initial_value)
    }
  end
end
