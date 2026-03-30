defmodule Cadence.Catalog.Telemetry.AggregateMember do
  @moduledoc """
  One member of a canonical aggregate telemetry type.
  """

  alias Cadence.Catalog.Telemetry.Normalize

  @type t :: %__MODULE__{
          name: binary(),
          type_id: binary(),
          description: binary() | nil,
          initial_value: term() | nil
        }

  defstruct [:name, :type_id, :description, :initial_value]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      name: Normalize.fetch!(attrs, :name),
      type_id: Normalize.fetch!(attrs, :type_id),
      description: Normalize.get(attrs, :description),
      initial_value: Normalize.get(attrs, :initial_value)
    }
  end
end
