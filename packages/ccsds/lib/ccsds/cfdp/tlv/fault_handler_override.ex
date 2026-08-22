defmodule CCSDS.CFDP.TLV.FaultHandlerOverride do
  @moduledoc """
  CFDP per-transaction fault-handler override TLV.
  """

  alias CCSDS.CFDP

  @type handler :: :cancel | :suspend | :ignore | :abandon
  @type t :: %__MODULE__{condition: CFDP.condition(), handler: handler()}

  defstruct condition: nil, handler: nil

  @spec new(CFDP.condition(), handler()) :: t()
  def new(condition, handler), do: %__MODULE__{condition: condition, handler: handler}
end
