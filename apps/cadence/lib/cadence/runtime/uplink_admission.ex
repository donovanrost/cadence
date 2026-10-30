defmodule Cadence.Runtime.UplinkAdmission do
  @moduledoc "Ephemeral admission bound to an exact runtime PID, target and session generation."
  @enforce_keys [:runtime, :target, :permit]
  defstruct @enforce_keys
  @type t :: %__MODULE__{runtime: pid(), target: tuple(), permit: map() | nil}
end
