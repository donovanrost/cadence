defmodule Cadence.CCSDS.Custom.SchemaRegistry do
  @moduledoc """
  Versioned registry for custom PDU schemas.
  """

  @spec fetch(String.t(), pos_integer()) :: {:ok, module()} | :error
  def fetch(_name, _version), do: :error
end
