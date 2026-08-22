defmodule CCSDS.CFDP.Directive.KeepAlive do
  @moduledoc """
  CFDP Keep Alive directive payload.
  """

  @type t :: %__MODULE__{progress: non_neg_integer()}

  defstruct progress: 0

  @spec new(non_neg_integer()) :: t()
  def new(progress) when is_integer(progress) and progress >= 0,
    do: %__MODULE__{progress: progress}
end
