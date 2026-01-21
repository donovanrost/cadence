defmodule Cadence.Runtime.Transport.COP1.CLCWReportDecoder do
  @moduledoc """
  Decodes CLCW-based COP-1 reports from space packets or TM OCFs.
  """

  @behaviour Cadence.Runtime.Transport.COP1.ReportDecoder

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Runtime.Transport.COP1.Report
  alias Cadence.Transport.TCStreamId

  @impl true
  def decode(%PDU{type: :space_packet, value: %SpacePacket{user_data: user_data}}, ctx) do
    with {:ok, clcw} <- decode_clcw(user_data) do
      report_from_clcw(clcw, ctx)
    end
  end

  def decode({:ocf, ocf}, ctx) when is_binary(ocf) do
    with {:ok, clcw} <- decode_clcw(ocf) do
      report_from_clcw(clcw, ctx)
    end
  end

  def decode(_pdu, _ctx), do: :not_a_report

  defp decode_clcw(data) when is_binary(data) and byte_size(data) == 4 do
    CLCW.decode(data)
  end

  defp decode_clcw(_data), do: {:error, :invalid_cop1_report}

  defp report_from_clcw(%CLCW{} = clcw, ctx) do
    with {:ok, mission_id} <- fetch_context(ctx, :mission_id),
         {:ok, interface_id} <- fetch_context(ctx, :interface_id),
         {:ok, scid} <- fetch_context(ctx, :scid),
         {:ok, vcid} <- fetch_vcid(ctx, clcw) do
      tc_stream_id = TCStreamId.new!(mission_id, interface_id, scid, vcid)

      {:ok,
       %Report{
         tc_stream_id: tc_stream_id,
         seq: clcw.report_value,
         status: status_from_clcw(clcw),
         raw: clcw
       }}
    end
  end

  defp fetch_context(ctx, key) do
    case Map.get(ctx, key) do
      value when is_binary(value) and key in [:mission_id, :interface_id] -> {:ok, value}
      value when is_integer(value) and key in [:scid] -> {:ok, value}
      _ -> {:error, :"missing_#{key}"}
    end
  end

  defp fetch_vcid(ctx, %CLCW{vcid: vcid}) when is_integer(vcid) do
    case Map.get(ctx, :vcid) do
      nil -> {:ok, vcid}
      ^vcid -> {:ok, vcid}
      other when is_integer(other) -> {:error, :vcid_mismatch}
      _ -> {:ok, vcid}
    end
  end

  defp fetch_vcid(ctx, _clcw) do
    case Map.get(ctx, :vcid) do
      vcid when is_integer(vcid) -> {:ok, vcid}
      _ -> {:error, :missing_vcid}
    end
  end

  defp status_from_clcw(%CLCW{lockout: 1}), do: :lockout
  defp status_from_clcw(%CLCW{wait: 1}), do: :wait
  defp status_from_clcw(%CLCW{retransmit: 1}), do: :retransmit
  defp status_from_clcw(%CLCW{}), do: :accept
end
