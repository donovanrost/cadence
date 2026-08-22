defmodule CCSDS.TC.Service.PacketProcessing do
  @moduledoc false

  alias CCSDS.Core.LinkFrame
  alias CCSDS.Packet.Configuration, as: PacketConfiguration
  alias CCSDS.TC.Service.{Configuration, Indication, Request}

  @spec validate_requests([Request.t()], PacketConfiguration.t()) :: :ok | {:error, term()}
  def validate_requests(requests, %PacketConfiguration{} = packet_configuration) do
    Enum.reduce_while(requests, :ok, fn request, :ok ->
      case PacketConfiguration.validate_packet(
             request.data,
             request.packet_version_number,
             packet_configuration
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {request.sdu_id, reason}}}
      end
    end)
  end

  @spec block([Request.t()], Configuration.t()) :: {:ok, [[Request.t()]]}
  def block(requests, %Configuration{blocking?: false}),
    do: {:ok, Enum.map(requests, &[&1])}

  def block(requests, %Configuration{} = configuration) do
    capacity = Configuration.maximum_data_field_octets(configuration)

    requests
    |> Enum.reduce({[], [], 0}, &add_to_block(&1, &2, capacity))
    |> then(fn {groups, current, _octets} ->
      completed_groups = if current == [], do: groups, else: [Enum.reverse(current) | groups]
      {:ok, Enum.reverse(completed_groups)}
    end)
  end

  @spec metadata([Request.t()]) :: map()
  def metadata(group) do
    %{
      sdu_ids: Enum.map(group, & &1.sdu_id),
      packet_version_numbers: Enum.map(group, & &1.packet_version_number),
      packet_count: length(group)
    }
  end

  @spec indications(
          binary(),
          LinkFrame.t(),
          Configuration.t(),
          [0..255],
          DateTime.t() | nil,
          Request.service_type()
        ) :: {:ok, [Indication.t()]} | {:error, term()}
  def indications(data, frame, configuration, source_frames, timestamp, service_type) do
    with {:ok, packets} <- PacketConfiguration.extract(data, configuration.packet) do
      {:ok,
       Enum.map(packets, fn packet ->
         %Indication{
           service: configuration.service,
           data: packet.octets,
           scid: frame.scid,
           vcid: frame.vcid,
           map_id: frame.map_id,
           packet_version_number: packet.packet_version_number,
           service_type: service_type,
           quality: packet.quality,
           source_frames: source_frames,
           timestamp: timestamp,
           verification_status_code: Map.get(frame.meta, :verification_status_code),
           meta: %{packet_count_in_frame_data_unit: length(packets)}
         }
       end)}
    end
  end

  defp add_to_block(request, {groups, current, current_octets}, capacity) do
    packet_octets = byte_size(request.data)

    if current != [] and current_octets + packet_octets > capacity do
      {[Enum.reverse(current) | groups], [request], packet_octets}
    else
      {groups, [request | current], current_octets + packet_octets}
    end
  end
end
