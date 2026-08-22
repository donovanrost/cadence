defmodule CCSDS.CFDP.ChecksumTestProvider do
  @moduledoc false

  @behaviour CCSDS.CFDP.ChecksumProvider

  @impl true
  def compute(type, file), do: {:ok, :binary.decode_unsigned(file <> <<type>>)}
end
