defmodule Cadence.Telemetry.Protocols.SDLPPassthroughProtocol do
  @moduledoc """
  Placeholder protocol for SDLP migration; no framing is performed.
  """

  use Cadence.Telemetry.Protocol

  def new(_opts), do: %{buffer: <<>>}

  def read_data(data, state) do
    {:ok, [data], state}
  end

  def packet_format, do: :raw
end
