defmodule Cadence.Runtime.Transport.COP1.DownlinkHandler do
  @moduledoc """
  Handles downlink COP-1 reports (CLCW in TM OCF).
  """

  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application
  alias Cadence.Runtime.Transport.COP1.CLCWReportDecoder

  @spec ingest_tm_ocf(String.t(), String.t(), binary(), map()) :: :ok
  def ingest_tm_ocf(mission_id, interface_id, ocf, ctx \\ %{})

  def ingest_tm_ocf(mission_id, interface_id, ocf, ctx)
      when is_binary(ocf) and byte_size(ocf) == 4 do
    ctx =
      ctx
      |> Map.put_new(:mission_id, mission_id)
      |> Map.put_new(:interface_id, interface_id)

    case CLCWReportDecoder.decode({:ocf, ocf}, ctx) do
      {:ok, report} ->
        COP1Application.ingest_report(report)
        :ok

      :not_a_report ->
        :ok

      {:error, reason} ->
        COP1Application.report_decode_failed(reason, ctx)
        :ok
    end
  end

  def ingest_tm_ocf(_mission_id, _interface_id, _ocf, _ctx), do: :ok
end
