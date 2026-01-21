defmodule Cadence.Runtime.Transport.COP1.ReportHandler do
  @moduledoc """
  Handles downlink COP-1 report space packets.
  """

  @behaviour Cadence.CCSDS.PDUHandler

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application

  @impl true
  def init(opts) do
    ingest_fun = Keyword.get(opts, :cop1_ingest_fun, &COP1Application.ingest_clcw/3)
    {:ok, %{ingest_fun: ingest_fun}}
  end

  @impl true
  def accepts?(%PDU{type: :space_packet, value: %SpacePacket{apid: apid}}, ctx)
      when is_integer(apid) do
    report_apid?(ctx, apid)
  end

  def accepts?(_pdu, _ctx), do: false

  @impl true
  def handle_pdu(%PDU{value: %SpacePacket{user_data: user_data}}, ctx, state) do
    mission_id = Map.get(ctx, :mission_id)
    interface_id = Map.get(ctx, :interface_id)

    with {:ok, clcw} <- decode_clcw(user_data),
         true <- is_binary(mission_id) and is_binary(interface_id) do
      state.ingest_fun.(mission_id, interface_id, clcw)
      {:ok, [], state}
    else
      false -> {:skip, :missing_context, state}
      {:error, reason} -> {:skip, reason, state}
    end
  end

  defp decode_clcw(data) when is_binary(data) and byte_size(data) == 4 do
    CLCW.decode(data)
  end

  defp decode_clcw(_data), do: {:error, :invalid_cop1_report}

  defp report_apid?(ctx, apid) do
    case Map.get(ctx, :cop1_report_apids) do
      %MapSet{} = apids -> MapSet.member?(apids, apid)
      apids when is_list(apids) -> Enum.member?(apids, apid)
      _ -> false
    end
  end
end
