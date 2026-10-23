defmodule Cadence.SemanticRuntime.Writer do
  @moduledoc "A durable ownership epoch and the exact log position recovered by its holder."

  @enforce_keys [:epoch, :commit_sequence, :identity]
  defstruct [:epoch, :commit_sequence, :identity]

  @type t :: %__MODULE__{
          epoch: pos_integer(),
          commit_sequence: non_neg_integer(),
          identity: {binary(), binary(), binary(), binary(), pos_integer()}
        }
end
