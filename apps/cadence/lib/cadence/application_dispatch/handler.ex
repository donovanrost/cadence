defmodule Cadence.ApplicationDispatch.Handler do
  @moduledoc """
  Behaviour for packet-level application handlers.
  """

  alias Cadence.ApplicationDispatch.WorkItem
  alias Cadence.Protocol.PacketRecord

  @callback handler_key() :: atom()
  @callback handle(PacketRecord.t(), WorkItem.t()) :: {:ok, [term()]} | {:error, term()}
end
