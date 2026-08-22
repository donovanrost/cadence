defmodule Cadence.Telemetry.UnknownUnit do
  @moduledoc """
  Unknown or unsupported packet unit.
  """

  @type t :: %__MODULE__{
          reason: atom() | term(),
          raw: binary() | nil,
          context: map()
        }

  defstruct [:reason, :raw, context: %{}]
end
