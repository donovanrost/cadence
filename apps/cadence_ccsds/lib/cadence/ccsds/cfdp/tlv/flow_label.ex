defmodule Cadence.CCSDS.CFDP.TLV.FlowLabel do
  @moduledoc """
  CFDP implementation-defined Flow Label TLV.
  """

  @type t :: %__MODULE__{value: binary()}
  defstruct value: <<>>

  @spec new(binary()) :: t()
  def new(value) when is_binary(value), do: %__MODULE__{value: value}
end
