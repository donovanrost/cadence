defmodule CadenceWeb.API.RuntimeIngressParams do
  @moduledoc "Development data-plane ingress request parsing boundary."

  import CadenceWeb.API.ParamParser

  alias Cadence.Ingress.RawEvidence

  @spec dev_space_packet_ingress(binary(), map()) :: {:ok, RawEvidence.t()} | {:error, term()}
  def dev_space_packet_ingress(mission_id, params)
      when is_binary(mission_id) and is_map(params) do
    with {:ok, raw_packet} <- required_packet_binary(params),
         {:ok, source_time} <- optional_datetime(params, "source_time"),
         {:ok, receipt_time} <- optional_datetime(params, "receipt_time"),
         {:ok, direction} <- optional_direction(params, "direction") do
      {:ok,
       RawEvidence.new(
         %{
           mission_id: mission_id,
           protocol_family: :space_packet,
           direction: direction || :downlink,
           raw: raw_packet,
           source_endpoint_ref: string_value(params, "source_endpoint_ref"),
           spacecraft_id: string_value(params, "spacecraft_id"),
           source_ref: string_value(params, "source_ref"),
           metadata: map_value(params, "metadata")
         }
         |> maybe_put_attr(:source_time, source_time)
         |> maybe_put_attr(:receipt_time, receipt_time)
       )}
    end
  end

  @spec dev_tm_frame_ingress(binary(), map()) :: {:ok, RawEvidence.t()} | {:error, term()}
  def dev_tm_frame_ingress(mission_id, params) when is_binary(mission_id) and is_map(params) do
    with {:ok, raw_frame} <- required_frame_binary(params),
         {:ok, source_time} <- optional_datetime(params, "source_time"),
         {:ok, receipt_time} <- optional_datetime(params, "receipt_time"),
         {:ok, direction} <- optional_direction(params, "direction"),
         {:ok, frame_size} <- optional_positive_integer(params, "frame_size"),
         {:ok, secondary_header_length} <- non_neg_integer(params, "secondary_header_length", 0),
         {:ok, ocf_length} <- non_neg_integer(params, "ocf_length", 0) do
      metadata =
        params
        |> map_value("metadata")
        |> Map.put(:frame_size, frame_size || byte_size(raw_frame))
        |> Map.put_new(:secondary_header_length, secondary_header_length)
        |> Map.put_new(:ocf_length, ocf_length)

      {:ok,
       RawEvidence.new(
         %{
           mission_id: mission_id,
           protocol_family: :tm_transfer_frame,
           direction: direction || :downlink,
           raw: raw_frame,
           source_endpoint_ref: string_value(params, "source_endpoint_ref"),
           spacecraft_id: string_value(params, "spacecraft_id"),
           source_ref: string_value(params, "source_ref"),
           metadata: metadata
         }
         |> maybe_put_attr(:source_time, source_time)
         |> maybe_put_attr(:receipt_time, receipt_time)
       )}
    end
  end
end
