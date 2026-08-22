defmodule Cadence.Extensions.Presentation.ReferenceOption do
  @moduledoc "A typed option returned by a registered host reference provider."

  @type t :: %__MODULE__{
          value: binary(),
          label: binary(),
          description: binary() | nil
        }

  @enforce_keys [:value, :label]
  defstruct [:value, :label, :description]
end
