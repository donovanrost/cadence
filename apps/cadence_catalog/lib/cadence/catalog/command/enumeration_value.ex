defmodule Cadence.Catalog.Command.EnumerationValue do
  @moduledoc """
  One canonical enumerated value mapping for a command argument type.
  """

  alias Cadence.Catalog.Command.Normalize

  @type t :: %__MODULE__{
          value: integer(),
          label: binary(),
          description: binary() | nil,
          max_value: integer() | nil
        }

  defstruct [:value, :label, :description, :max_value]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      value: Normalize.fetch!(attrs, :value),
      label: Normalize.fetch!(attrs, :label),
      description: Normalize.get(attrs, :description),
      max_value: Normalize.get(attrs, :max_value)
    }
  end
end
