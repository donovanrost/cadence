defmodule Cadence.SemanticRuntime.Writer do
  @moduledoc """
  A durable ownership epoch: the holder of a partition's semantic runtime. A snapshot is written
  only by the current holder (`Store.snapshot/5`); a holder that was superseded is fenced.
  """

  @enforce_keys [:epoch, :identity]
  defstruct [:epoch, :identity]

  @type t :: %__MODULE__{
          epoch: pos_integer(),
          identity: {binary(), binary(), binary(), binary(), pos_integer()}
        }
end
