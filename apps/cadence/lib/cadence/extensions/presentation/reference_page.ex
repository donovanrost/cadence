defmodule Cadence.Extensions.Presentation.ReferencePage do
  @moduledoc "Bounded result page returned by a registered reference provider."

  alias Cadence.Extensions.Presentation.ReferenceOption

  @type t :: %__MODULE__{
          query: binary(),
          options: [ReferenceOption.t()],
          more?: boolean()
        }

  @enforce_keys [:query, :options, :more?]
  defstruct [:query, :options, :more?]
end
