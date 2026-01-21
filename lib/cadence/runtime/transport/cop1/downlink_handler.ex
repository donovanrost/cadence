defmodule Cadence.Runtime.Transport.COP1.DownlinkHandler do
  @moduledoc """
  Handles downlink COP-1 reports (CLCW in TM OCF).
  """

  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application

  @spec ingest_tm_ocf(String.t(), String.t(), binary()) :: :ok
  def ingest_tm_ocf(mission_id, interface_id, ocf)
      when is_binary(ocf) and byte_size(ocf) == 4 do
    case CLCW.decode(ocf) do
      {:ok, clcw} -> COP1Application.ingest_clcw(mission_id, interface_id, clcw)
      {:error, _reason} -> :ok
    end
  end

  def ingest_tm_ocf(_mission_id, _interface_id, _ocf), do: :ok
end
