defmodule Cadence.Runtime.Transport.COP1.ReportHandler do
  @moduledoc """
  Handles downlink COP-1 report space packets.
  """

  @behaviour Cadence.CCSDS.PDUHandler

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application
  alias Cadence.Runtime.Transport.COP1.CLCWReportDecoder

  @impl true
  def init(opts) do
    ingest_fun = Keyword.get(opts, :cop1_ingest_fun, &COP1Application.ingest_report/1)
    decoder = Keyword.get(opts, :cop1_report_decoder, CLCWReportDecoder)
    {:ok, %{ingest_fun: ingest_fun, decoder: decoder}}
  end

  @impl true
  def accepts?(%PDU{type: :space_packet, value: %SpacePacket{apid: apid}}, ctx)
      when is_integer(apid) do
    report_apid?(ctx, apid)
  end

  def accepts?(_pdu, _ctx), do: false

  @impl true
  def handle_pdu(%PDU{value: %SpacePacket{} = packet}, ctx, state) do
    decoder = state.decoder

    case decoder.decode(%PDU{type: :space_packet, value: packet}, ctx) do
      {:ok, report} ->
        state.ingest_fun.(report)
        {:ok, [], state}

      :not_a_report ->
        {:skip, :not_a_report, state}

      {:error, reason} ->
        COP1Application.report_decode_failed(reason, ctx)
        {:skip, reason, state}
    end
  end

  defp report_apid?(ctx, apid) do
    case Map.get(ctx, :cop1_report_apids) do
      %MapSet{} = apids -> MapSet.member?(apids, apid)
      apids when is_list(apids) -> Enum.member?(apids, apid)
      _ -> false
    end
  end
end
