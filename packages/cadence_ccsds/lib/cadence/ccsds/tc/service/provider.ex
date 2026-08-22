defmodule Cadence.CCSDS.TC.Service.Provider do
  @moduledoc """
  Pure sending- and receiving-end TC data-service composition.

  The provider exposes distinct Packet, Access, and Frame Service primitives
  over the shared TC frame, segmentation, and reassembly codecs. Packet
  blocking is greedy and stable within one `request_many/2` call. Channel
  multiplexing order remains mission-managed and is therefore left to callers.

  Receiving data frames must already have passed the applicable FARM-1 and
  optional SDLS processing. This keeps COP and security state independent from
  service-data extraction.
  """

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}
  alias Cadence.CCSDS.Packet.Configuration, as: PacketConfiguration
  alias Cadence.CCSDS.TC.{FrameCodec, Reassembly, Segmentation}

  alias Cadence.CCSDS.TC.Service.{
    Configuration,
    Indication,
    PacketProcessing,
    Request
  }

  @type t :: %__MODULE__{
          configurations: %{required(tuple()) => Configuration.t()},
          frame_sequences: %{optional({0..1023, 0..63}) => 0..255},
          reassembly: map()
        }

  defstruct configurations: %{}, frame_sequences: %{}, reassembly: nil

  @spec init([Configuration.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def init(configurations, opts \\ []) do
    with :ok <- Configuration.validate_plan(configurations),
         {:ok, reassembly} <-
           Reassembly.init(max_sdu_octets: maximum_reassembly_octets(configurations)),
         {:ok, frame_sequences} <-
           normalize_frame_sequences(Keyword.get(opts, :frame_sequences, %{})) do
      indexed = Map.new(configurations, &{Configuration.key(&1), &1})

      {:ok,
       %__MODULE__{
         configurations: indexed,
         frame_sequences: frame_sequences,
         reassembly: reassembly
       }}
    end
  end

  @spec request(Request.t(), t()) ::
          {:ok, [LinkFrame.t()], t()} | {:error, term(), t()}
  def request(%Request{} = request, %__MODULE__{} = state) do
    request_many([request], state)
  end

  @spec request_many([Request.t()], t()) ::
          {:ok, [LinkFrame.t()], t()} | {:error, term(), t()}
  def request_many(requests, %__MODULE__{} = state) when is_list(requests) do
    with {:ok, configuration} <- fetch_request_configuration(requests, state),
         :ok <- validate_request_batch(requests, configuration) do
      dispatch_requests(requests, configuration, state)
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @spec ingest(LinkFrame.t(), t()) ::
          {:ok, [Indication.t()], t()} | {:error, term(), t()}
  def ingest(%LinkFrame{profile: :tc} = frame, %__MODULE__{} = state) do
    with {:ok, configuration} <- fetch_frame_configuration(frame, state),
         :ok <- validate_received_frame_type(frame, configuration) do
      dispatch_frame(frame, configuration, state)
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  def ingest(%LinkFrame{profile: profile}, %__MODULE__{} = state),
    do: {:error, {:invalid_profile, profile}, state}

  defp dispatch_requests(requests, configuration, state) do
    case configuration.service do
      service when service in [:map_packet, :virtual_channel_packet] ->
        request_packets(requests, configuration, state)

      service when service in [:map_access, :virtual_channel_access] ->
        request_access(hd(requests), configuration, state)

      service when service in [:virtual_channel_frame, :master_channel_frame] ->
        request_frame(hd(requests), configuration, state)
    end
  end

  defp request_packets(requests, configuration, state) do
    with :ok <- PacketProcessing.validate_requests(requests, configuration.packet),
         {:ok, groups} <- PacketProcessing.block(requests, configuration),
         {:ok, frames, next_state} <- segment_packet_groups(groups, configuration, state) do
      {:ok, frames, next_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp segment_packet_groups(groups, configuration, state) do
    Enum.reduce_while(groups, {:ok, [], state}, fn group, {:ok, frames_acc, current_state} ->
      case segment_packet_group(group, configuration, current_state) do
        {:ok, frames, next_state} ->
          {:cont, {:ok, [frames | frames_acc], next_state}}

        {:error, reason, _unchanged_state} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, frame_groups, next_state} ->
        {:ok, frame_groups |> Enum.reverse() |> List.flatten(), next_state}

      {:error, _reason} = error ->
        error
    end
  end

  defp segment_packet_group(group, configuration, state) do
    data = group |> Enum.map(& &1.data) |> IO.iodata_to_binary()
    first_request = hd(group)

    sdu = build_sdu(data, first_request, configuration)

    segment_sdu(
      sdu,
      first_request.service_type,
      configuration,
      state,
      PacketProcessing.metadata(group)
    )
  end

  defp request_access(request, configuration, state) do
    with :ok <- validate_access_data(request.data, configuration),
         sdu = build_sdu(request.data, request, configuration),
         {:ok, frames, next_state} <-
           segment_sdu(
             sdu,
             request.service_type,
             configuration,
             state,
             %{sdu_ids: [request.sdu_id]}
           ) do
      {:ok, frames, next_state}
    else
      {:error, reason} -> {:error, reason, state}
      {:error, reason, _state} -> {:error, reason, state}
    end
  end

  defp segment_sdu(sdu, service_type, configuration, state, service_metadata) do
    vc_key = Configuration.virtual_channel_key(configuration)
    segmentation_state = %{frame_seq: Map.get(state.frame_sequences, vc_key, 0)}

    context = %{
      frame_size: configuration.frame_size,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: configuration.map_id,
      bypass_flag: bypass_flag(service_type),
      control_command_flag: 0,
      segment_header_flag: if(Configuration.segment_header?(configuration), do: 1, else: 0),
      fecf: configuration.fecf?
    }

    case Segmentation.segment(sdu, context, segmentation_state) do
      {:ok, frames, next_segmentation_state} ->
        metadata =
          Map.put(
            service_metadata,
            :coding_repetitions,
            coding_repetitions(service_type, configuration)
          )

        tagged_frames = Enum.map(frames, &tag_service_frame(&1, configuration, metadata))
        next_sequences = Map.put(state.frame_sequences, vc_key, next_segmentation_state.frame_seq)
        {:ok, tagged_frames, %{state | frame_sequences: next_sequences}}

      {:error, reason, _segmentation_state} ->
        {:error, reason, state}
    end
  end

  defp request_frame(request, configuration, state) do
    with %LinkFrame{} = frame <- request.data,
         :ok <- validate_frame_service_address(frame, configuration),
         :ok <- validate_empty_fecf(frame),
         {:ok, _encoded} <-
           FrameCodec.encode(frame,
             frame_size: configuration.frame_size,
             fecf: configuration.fecf?
           ) do
      tagged = tag_service_frame(frame, configuration, %{sdu_ids: [request.sdu_id]})
      {:ok, [tagged], state}
    else
      {:error, reason} -> {:error, reason, state}
      value -> {:error, {:invalid_frame_service_data, value}, state}
    end
  end

  defp dispatch_frame(frame, configuration, state) do
    case configuration.service do
      service when service in [:virtual_channel_frame, :master_channel_frame] ->
        {:ok, [frame_indication(frame, configuration)], state}

      :virtual_channel_access ->
        {:ok, [access_indication(frame.payload_octets, frame, configuration, [frame.frame_seq])],
         state}

      :virtual_channel_packet ->
        packet_indications(frame.payload_octets, frame, configuration, [frame.frame_seq], state)

      service when service in [:map_access, :map_packet] ->
        reassemble_map_frame(frame, configuration, state)
    end
  end

  defp reassemble_map_frame(frame, configuration, state) do
    context = %{direction: :uplink, sdu_kind_hint: configuration.service}

    case Reassembly.ingest(frame, context, state.reassembly) do
      {:ok, sdus, next_reassembly} ->
        emit_reassembled(sdus, frame, configuration, %{state | reassembly: next_reassembly})

      {:error, reason, next_reassembly} ->
        {:error, reason, %{state | reassembly: next_reassembly}}
    end
  end

  defp emit_reassembled(sdus, _frame, %Configuration{service: :map_access} = configuration, state) do
    indications =
      Enum.map(sdus, fn sdu ->
        access_indication(sdu.octets, sdu, configuration, sdu.source_frames)
      end)

    {:ok, indications, state}
  end

  defp emit_reassembled(sdus, frame, %Configuration{service: :map_packet} = configuration, state) do
    Enum.reduce_while(sdus, {:ok, []}, fn sdu, {:ok, acc} ->
      case PacketProcessing.indications(
             sdu.octets,
             frame,
             configuration,
             sdu.source_frames,
             sdu.timestamp,
             service_type(frame)
           ) do
        {:ok, indications} -> {:cont, {:ok, [indications | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, indication_groups} ->
        {:ok, indication_groups |> Enum.reverse() |> List.flatten(), state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp packet_indications(data, frame, configuration, source_frames, state) do
    case PacketProcessing.indications(
           data,
           frame,
           configuration,
           source_frames,
           frame.timestamp,
           service_type(frame)
         ) do
      {:ok, indications} -> {:ok, indications, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp access_indication(data, source, configuration, source_frames) do
    %Indication{
      service: configuration.service,
      data: data,
      scid: source.scid,
      vcid: source.vcid,
      map_id: source.map_id,
      service_type: service_type(source),
      quality: :complete,
      source_frames: source_frames,
      timestamp: source.timestamp,
      verification_status_code: Map.get(source.meta, :verification_status_code),
      meta: %{}
    }
  end

  defp frame_indication(frame, configuration) do
    %Indication{
      service: configuration.service,
      data: frame,
      scid: frame.scid,
      vcid: frame.vcid,
      map_id: frame.map_id,
      service_type: nil,
      quality: :complete,
      source_frames: [frame.frame_seq],
      timestamp: frame.timestamp,
      verification_status_code: nil,
      meta: %{}
    }
  end

  defp fetch_request_configuration([], _state), do: {:error, :empty_service_request_batch}

  defp fetch_request_configuration([%Request{} = first | rest], state) do
    key = {first.service, first.scid, first.vcid, first.map_id}

    with {:ok, configuration} <- fetch_configuration(key, state),
         true <- Enum.all?(rest, &same_request_endpoint?(&1, first)) do
      {:ok, configuration}
    else
      false -> {:error, :mixed_service_request_batch}
      {:error, _reason} = error -> error
    end
  end

  defp fetch_request_configuration([value | _rest], _state),
    do: {:error, {:invalid_service_request, value}}

  defp fetch_configuration(key, state) do
    case Map.fetch(state.configurations, key) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> {:error, {:unknown_service_address, key}}
    end
  end

  defp fetch_frame_configuration(frame, state) do
    master_key = {:master_channel_frame, frame.scid, nil, nil}

    case Map.fetch(state.configurations, master_key) do
      {:ok, configuration} ->
        validate_received_vcid(frame, configuration)

      :error ->
        fetch_virtual_or_map_configuration(frame, state)
    end
  end

  defp fetch_virtual_or_map_configuration(frame, state) do
    virtual_frame_key = {:virtual_channel_frame, frame.scid, frame.vcid, nil}

    case Map.fetch(state.configurations, virtual_frame_key) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> fetch_data_service_configuration(frame, state)
    end
  end

  defp fetch_data_service_configuration(frame, state) do
    candidates =
      if is_nil(frame.map_id),
        do: [:virtual_channel_packet, :virtual_channel_access],
        else: [:map_packet, :map_access]

    matches = Enum.filter(candidates, &configured_for_frame?(&1, frame, state))

    case matches do
      [service] -> fetch_configuration({service, frame.scid, frame.vcid, frame.map_id}, state)
      [] -> {:error, {:unknown_received_service_address, frame.scid, frame.vcid, frame.map_id}}
    end
  end

  defp configured_for_frame?(service, frame, state) do
    Map.has_key?(state.configurations, {service, frame.scid, frame.vcid, frame.map_id})
  end

  defp validate_received_vcid(frame, configuration) do
    if frame.vcid in configuration.valid_vcids do
      {:ok, configuration}
    else
      {:error, {:invalid_vcid, frame.vcid}}
    end
  end

  defp validate_request_batch(requests, configuration) do
    with :ok <- validate_batch_cardinality(requests, configuration),
         :ok <- validate_request_data_types(requests, configuration),
         :ok <- validate_service_types(requests, configuration) do
      validate_request_packet_versions(requests, configuration)
    end
  end

  defp validate_batch_cardinality([_request], _configuration), do: :ok

  defp validate_batch_cardinality(_requests, %Configuration{} = configuration) do
    if Configuration.packet_service?(configuration) do
      :ok
    else
      {:error, {:batching_not_supported, configuration.service}}
    end
  end

  defp validate_request_data_types(requests, configuration) do
    valid? =
      if Configuration.frame_service?(configuration) do
        Enum.all?(requests, &match?(%LinkFrame{}, &1.data))
      else
        Enum.all?(requests, &(is_binary(&1.data) and byte_size(&1.data) > 0))
      end

    if valid?, do: :ok, else: {:error, {:invalid_service_data, configuration.service}}
  end

  defp validate_service_types(requests, configuration) do
    service_types = requests |> Enum.map(& &1.service_type) |> Enum.uniq()

    cond do
      Configuration.frame_service?(configuration) and service_types == [nil] ->
        :ok

      Configuration.frame_service?(configuration) ->
        {:error, {:service_type_forbidden, service_types}}

      service_types in [[:sequence_controlled], [:expedited]] ->
        :ok

      true ->
        {:error, {:invalid_or_mixed_service_types, service_types}}
    end
  end

  defp validate_request_packet_versions(requests, configuration) do
    if Configuration.packet_service?(configuration) do
      if Enum.all?(requests, &(&1.packet_version_number in 0..7)) do
        :ok
      else
        {:error, :packet_version_number_required}
      end
    else
      if Enum.all?(requests, &is_nil(&1.packet_version_number)) do
        :ok
      else
        {:error, :packet_version_number_forbidden}
      end
    end
  end

  defp validate_access_data(data, configuration) do
    data_octets = byte_size(data)
    capacity = Configuration.maximum_data_field_octets(configuration)

    cond do
      configuration.maximum_sdu_octets && data_octets > configuration.maximum_sdu_octets ->
        {:error, {:sdu_size_limit_exceeded, data_octets, configuration.maximum_sdu_octets}}

      not configuration.segmentation? and data_octets > capacity ->
        {:error, {:segmentation_prohibited, data_octets, capacity}}

      true ->
        :ok
    end
  end

  defp validate_frame_service_address(
         frame,
         %Configuration{service: :virtual_channel_frame} = config
       ) do
    if frame.profile == :tc and frame.scid == config.scid and frame.vcid == config.vcid do
      :ok
    else
      {:error, {:frame_service_address_mismatch, frame.scid, frame.vcid}}
    end
  end

  defp validate_frame_service_address(
         frame,
         %Configuration{service: :master_channel_frame} = config
       ) do
    if frame.profile == :tc and frame.scid == config.scid and frame.vcid in config.valid_vcids do
      :ok
    else
      {:error, {:frame_service_address_mismatch, frame.scid, frame.vcid}}
    end
  end

  defp validate_empty_fecf(frame) do
    if Map.get(frame.meta, :fecf_present, false) or not is_nil(Map.get(frame.meta, :fecf)) do
      {:error, :frame_service_fecf_must_be_empty}
    else
      :ok
    end
  end

  defp validate_received_frame_type(_frame, %Configuration{} = configuration)
       when configuration.service in [:virtual_channel_frame, :master_channel_frame],
       do: :ok

  defp validate_received_frame_type(frame, %Configuration{}) do
    if Map.get(frame.meta, :control_command_flag, 0) == 0 do
      :ok
    else
      {:error, :control_command_is_not_service_data}
    end
  end

  defp build_sdu(data, request, configuration) do
    %SDUOctets{
      profile: :tc,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: configuration.map_id,
      direction: :uplink,
      sdu_kind_hint: configuration.service,
      octets: data,
      quality: :good,
      source_frames: [],
      timestamp: request.timestamp,
      meta: request.meta
    }
  end

  defp tag_service_frame(frame, configuration, service_metadata) do
    metadata =
      frame.meta
      |> Map.put(:tc_service, configuration.service)
      |> Map.merge(service_metadata)

    %{frame | meta: metadata}
  end

  defp same_request_endpoint?(%Request{} = left, %Request{} = right) do
    {left.service, left.scid, left.vcid, left.map_id, left.service_type} ==
      {right.service, right.scid, right.vcid, right.map_id, right.service_type}
  end

  defp same_request_endpoint?(_value, _request), do: false

  defp service_type(%LinkFrame{} = frame) do
    case Map.get(frame.meta, :bypass_flag, 0) do
      0 -> :sequence_controlled
      1 -> :expedited
    end
  end

  defp service_type(%SDUOctets{} = sdu) do
    case Map.get(sdu.meta, :bypass_flag, 0) do
      0 -> :sequence_controlled
      1 -> :expedited
    end
  end

  defp bypass_flag(:sequence_controlled), do: 0
  defp bypass_flag(:expedited), do: 1

  defp coding_repetitions(:sequence_controlled, configuration),
    do: configuration.repetitions_type_a

  defp coding_repetitions(:expedited, _configuration), do: 1

  defp maximum_reassembly_octets(configurations) do
    configurations
    |> Enum.map(fn configuration ->
      configuration.maximum_sdu_octets ||
        packet_maximum(configuration.packet) ||
        Configuration.maximum_data_field_octets(configuration)
    end)
    |> Enum.max()
  end

  defp packet_maximum(%PacketConfiguration{maximum_packet_octets: maximum}), do: maximum
  defp packet_maximum(nil), do: nil

  defp normalize_frame_sequences(frame_sequences) when is_map(frame_sequences) do
    invalid =
      Enum.find(frame_sequences, fn
        {{scid, vcid}, sequence}
        when is_integer(scid) and scid in 0..1023 and is_integer(vcid) and vcid in 0..63 and
               is_integer(sequence) and sequence in 0..255 ->
          false

        _entry ->
          true
      end)

    if invalid, do: {:error, {:invalid_frame_sequence, invalid}}, else: {:ok, frame_sequences}
  end

  defp normalize_frame_sequences(value), do: {:error, {:invalid_frame_sequences, value}}
end
