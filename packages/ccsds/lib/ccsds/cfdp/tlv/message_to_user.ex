defmodule CCSDS.CFDP.TLV.MessageToUser do
  @moduledoc """
  CFDP Message-to-User TLV with application-defined bytes.
  """

  @type t :: %__MODULE__{message: binary()}
  defstruct message: <<>>

  @spec new(binary()) :: t()
  def new(message) when is_binary(message), do: %__MODULE__{message: message}
end
