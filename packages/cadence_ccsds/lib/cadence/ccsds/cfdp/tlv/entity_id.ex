defmodule Cadence.CCSDS.CFDP.TLV.EntityID do
  @moduledoc """
  CFDP Entity ID TLV, used to identify a fault location.
  """

  @type t :: %__MODULE__{entity_id: non_neg_integer(), octets: 1..8 | nil}
  defstruct entity_id: nil, octets: nil

  @spec new(non_neg_integer(), keyword()) :: t()
  def new(entity_id, opts \\ []) when is_integer(entity_id) and entity_id >= 0,
    do: %__MODULE__{entity_id: entity_id, octets: Keyword.get(opts, :octets)}
end
