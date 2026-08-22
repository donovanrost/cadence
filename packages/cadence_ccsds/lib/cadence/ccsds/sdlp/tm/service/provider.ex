defmodule Cadence.CCSDS.SDLP.TM.Service.Provider do
  @moduledoc """
  Pure TM Virtual Channel Packet and Access service composition.

  This provider composes managed configuration, Virtual Channel generation,
  continuity-aware reception, and request/indication primitives. Scheduling,
  MC/VC multiplexing, persistence, and optional SDLS processing remain caller
  concerns.
  """

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}

  alias Cadence.CCSDS.SDLP.TM.{Configuration, Reassembly, Segmentation}
  alias Cadence.CCSDS.SDLP.TM.Service.{Indication, Request}

  @type t :: %__MODULE__{
          configurations: %{required({0..1023, 0..7}) => Configuration.t()},
          segmentation: map(),
          reassembly: map()
        }

  defstruct configurations: %{}, segmentation: nil, reassembly: nil

  @spec init([Configuration.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def init(configurations, opts \\ []) when is_list(configurations) and is_list(opts) do
    with {:ok, indexed} <- index_configurations(configurations),
         {:ok, segmentation} <- Segmentation.init(Keyword.get(opts, :segmentation, [])),
         {:ok, reassembly} <-
           Reassembly.init(
             Keyword.merge(
               Keyword.get(opts, :reassembly, []),
               configurations: configurations,
               default_sdu_type: :space_packet
             )
           ) do
      {:ok,
       %__MODULE__{
         configurations: indexed,
         segmentation: segmentation,
         reassembly: reassembly
       }}
    end
  end

  @spec request(Request.t(), t()) ::
          {:ok, [LinkFrame.t()], t()} | {:error, term(), t()}
  def request(%Request{} = request, %__MODULE__{} = state) do
    with {:ok, configuration} <- fetch_configuration(request.scid, request.vcid, state),
         :ok <- validate_request(request, configuration),
         sdu = request_sdu(request),
         context = request_context(request, configuration),
         {:ok, frames, next_segmentation} <-
           Segmentation.segment(sdu, context, state.segmentation) do
      {:ok, Enum.map(frames, &tag_service(&1, request.service)),
       %{state | segmentation: next_segmentation}}
    else
      {:error, reason} -> {:error, reason, state}
      {:error, reason, _segmentation} -> {:error, reason, state}
    end
  end

  def request(value, %__MODULE__{} = state),
    do: {:error, {:invalid_tm_service_request, value}, state}

  @spec only_idle(0..1023, 0..7, map(), t()) ::
          {:ok, LinkFrame.t(), t()} | {:error, term(), t()}
  def only_idle(scid, vcid, frame_fields \\ %{}, %__MODULE__{} = state)
      when is_map(frame_fields) do
    with {:ok, configuration} <- fetch_configuration(scid, vcid, state),
         :ok <- require_packet_service(configuration),
         context = Map.put(frame_fields, :configuration, configuration),
         {:ok, frame, next_segmentation} <- Segmentation.only_idle(context, state.segmentation) do
      {:ok, tag_service(frame, :virtual_channel_packet),
       %{state | segmentation: next_segmentation}}
    else
      {:error, reason} -> {:error, reason, state}
      {:error, reason, _segmentation} -> {:error, reason, state}
    end
  end

  @spec ingest(LinkFrame.t(), t()) ::
          {:ok, [Indication.t()], t()} | {:error, term(), t()}
  def ingest(%LinkFrame{} = frame, %__MODULE__{} = state) do
    case ingest_detailed(frame, state) do
      {:ok, indications, _anomalies, next_state} -> {:ok, indications, next_state}
      {:error, reason, _anomalies, next_state} -> {:error, reason, next_state}
    end
  end

  @spec ingest_detailed(LinkFrame.t(), t()) ::
          {:ok, [Indication.t()], [map()], t()}
          | {:error, term(), [map()], t()}
  def ingest_detailed(%LinkFrame{profile: :tm} = frame, %__MODULE__{} = state) do
    case fetch_configuration(frame.scid, frame.vcid, state) do
      {:ok, _configuration} -> ingest_configured_frame(frame, state)
      {:error, reason} -> {:error, reason, [], state}
    end
  end

  def ingest_detailed(%LinkFrame{profile: profile}, %__MODULE__{} = state),
    do: {:error, {:invalid_profile, profile}, [], state}

  defp ingest_configured_frame(frame, state) do
    case Reassembly.ingest_detailed(frame, %{direction: :downlink}, state.reassembly) do
      {:ok, sdus, anomalies, next_reassembly} ->
        {:ok, Enum.map(sdus, &indication/1), anomalies, %{state | reassembly: next_reassembly}}

      {:error, reason, anomalies, next_reassembly} ->
        {:error, reason, anomalies, %{state | reassembly: next_reassembly}}
    end
  end

  defp index_configurations([]), do: {:error, :empty_tm_service_plan}

  defp index_configurations(configurations) do
    with :ok <- Configuration.validate_plan(configurations) do
      {:ok, Map.new(configurations, &{Configuration.address(&1), &1})}
    end
  end

  defp fetch_configuration(scid, vcid, state) do
    case Map.fetch(state.configurations, {scid, vcid}) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> {:error, {:unknown_tm_service_address, scid, vcid}}
    end
  end

  defp validate_request(request, configuration) do
    with :ok <- validate_request_service(request.service, configuration),
         :ok <- validate_binary_data(request.data),
         :ok <- validate_request_metadata(request) do
      validate_request_packet_version(request, configuration)
    end
  end

  defp validate_request_service(:virtual_channel_packet, %Configuration{
         data_field_content: :packets
       }),
       do: :ok

  defp validate_request_service(:virtual_channel_access, %Configuration{
         data_field_content: :vca_sdu
       }),
       do: :ok

  defp validate_request_service(service, configuration),
    do: {:error, {:service_configuration_mismatch, service, configuration.data_field_content}}

  defp validate_binary_data(data) when is_binary(data) and byte_size(data) > 0, do: :ok
  defp validate_binary_data(data), do: {:error, {:invalid_service_data, data}}

  defp validate_request_metadata(%Request{
         service: :virtual_channel_packet,
         vca_status_fields: nil
       }),
       do: :ok

  defp validate_request_metadata(%Request{
         service: :virtual_channel_access,
         vca_status_fields: value
       })
       when is_integer(value) and value in 0..0x3FFF,
       do: :ok

  defp validate_request_metadata(request),
    do: {:error, {:invalid_service_metadata, request.service}}

  defp validate_request_packet_version(
         %Request{service: :virtual_channel_packet, packet_version_number: version},
         configuration
       ) do
    if version in configuration.valid_packet_version_numbers,
      do: :ok,
      else: {:error, {:invalid_packet_version_number, version}}
  end

  defp validate_request_packet_version(
         %Request{service: :virtual_channel_access, packet_version_number: nil},
         _configuration
       ),
       do: :ok

  defp validate_request_packet_version(request, _configuration),
    do: {:error, {:packet_version_number_forbidden, request.packet_version_number}}

  defp request_sdu(request) do
    %SDUOctets{
      profile: :tm,
      scid: request.scid,
      vcid: request.vcid,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: sdu_kind(request.service),
      octets: request.data,
      quality: :good,
      source_frames: [],
      timestamp: request.timestamp,
      meta: Map.put(request.meta, :vca_status_fields, request.vca_status_fields)
    }
  end

  defp request_context(request, configuration) do
    request.meta
    |> Map.take([:secondary_header, :ocf])
    |> Map.put(:configuration, configuration)
  end

  defp tag_service(frame, service),
    do: %{frame | meta: Map.put(frame.meta, :tm_service, service)}

  defp indication(%SDUOctets{} = sdu) do
    %Indication{
      service: indication_service(sdu.sdu_kind_hint),
      data: sdu.octets,
      scid: sdu.scid,
      vcid: sdu.vcid,
      packet_version_number: packet_version_number(sdu),
      quality: if(sdu.quality == :partial, do: :partial, else: :complete),
      source_frames: sdu.source_frames,
      vca_status_fields: Map.get(sdu.meta, :vca_status_fields),
      vca_sdu_loss_flag: Map.get(sdu.meta, :vca_sdu_loss_flag),
      verification_status_code: Map.get(sdu.meta, :verification_status_code),
      timestamp: sdu.timestamp,
      meta: sdu.meta
    }
  end

  defp sdu_kind(:virtual_channel_packet), do: :space_packet
  defp sdu_kind(:virtual_channel_access), do: :vca_sdu
  defp indication_service(:space_packet), do: :virtual_channel_packet
  defp indication_service(:vca_sdu), do: :virtual_channel_access

  defp packet_version_number(%SDUOctets{
         sdu_kind_hint: :space_packet,
         octets: <<version::3, _::bitstring>>
       }),
       do: version

  defp packet_version_number(%SDUOctets{}), do: nil

  defp require_packet_service(%Configuration{data_field_content: :packets}), do: :ok

  defp require_packet_service(configuration),
    do: {:error, {:oid_forbidden, configuration.data_field_content}}
end
