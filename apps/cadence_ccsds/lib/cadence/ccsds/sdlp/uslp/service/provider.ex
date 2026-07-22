defmodule Cadence.CCSDS.SDLP.USLP.Service.Provider do
  @moduledoc """
  Pure composition of all USLP services.

  MAP Packet, VC Packet, MAP Access, VC Access and MAP Octet Stream requests
  use the generation kernel. OCF and Insert requests enqueue synchronous SDUs.
  VCF and MCF requests validate independently generated frames. COP management
  requests are exposed as algorithm-neutral directives for a caller-owned
  COP-1 or COP-P state machine. Multiplex scheduling, channel coding, SDLS,
  persistence and runtime orchestration remain caller concerns.
  """

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}
  alias Cadence.CCSDS.Packet.Format, as: PacketFormat

  alias Cadence.CCSDS.SDLP.USLP.{Configuration, Continuity, FrameCodec, Reassembly, Segmentation}
  alias Cadence.CCSDS.SDLP.USLP.Service.{Indication, Request}

  @type physical_address :: {binary(), 0..65_535, 0..63, 0..15}
  @type virtual_address :: {binary(), 0..65_535, 0..63}
  @type master_address :: {binary(), 0..65_535}

  @type t :: %__MODULE__{
          configurations: %{required(physical_address()) => Configuration.t()},
          virtual_frame_services: MapSet.t(virtual_address()),
          master_frame_services: MapSet.t(master_address()),
          segmentation: map(),
          reassembly: map(),
          frame_continuity: Continuity.t(),
          pending_ocf: %{optional(virtual_address()) => [binary()]},
          pending_insert: %{optional(binary()) => [binary()]},
          cop_directives: [map()]
        }

  defstruct configurations: %{},
            virtual_frame_services: MapSet.new(),
            master_frame_services: MapSet.new(),
            segmentation: nil,
            reassembly: nil,
            frame_continuity: nil,
            pending_ocf: %{},
            pending_insert: %{},
            cop_directives: []

  @spec init([Configuration.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def init(configurations, opts \\ []) when is_list(configurations) and is_list(opts) do
    with :ok <- Configuration.validate_plan(configurations),
         indexed <- Map.new(configurations, &{Configuration.physical_address(&1), &1}),
         {:ok, virtual_frames, master_frames} <-
           normalize_frame_services(Keyword.get(opts, :frame_services, []), indexed),
         :ok <- validate_frame_services(indexed, virtual_frames, master_frames),
         {:ok, segmentation} <- Segmentation.init(Keyword.get(opts, :segmentation, [])),
         {:ok, reassembly} <-
           Reassembly.init(
             Keyword.merge(Keyword.get(opts, :reassembly, []), configurations: configurations)
           ) do
      {:ok,
       %__MODULE__{
         configurations: indexed,
         virtual_frame_services: virtual_frames,
         master_frame_services: master_frames,
         segmentation: segmentation,
         reassembly: reassembly,
         frame_continuity: Continuity.init()
       }}
    end
  end

  @spec request(Request.t(), t()) :: {:ok, [LinkFrame.t()], t()} | {:error, term(), t()}
  def request(%Request{service: :master_channel_operational_control} = request, state),
    do: enqueue_ocf(request, state)

  def request(%Request{service: :insert} = request, state), do: enqueue_insert(request, state)

  def request(%Request{service: :cops_management} = request, state),
    do: enqueue_cop_directive(request, state)

  def request(%Request{service: service} = request, state)
      when service in [
             :map_packet,
             :virtual_channel_packet,
             :map_access,
             :virtual_channel_access,
             :map_octet_stream
           ],
      do: generate_frames(request, state)

  def request(%Request{service: service} = request, state)
      when service in [:virtual_channel_frame, :master_channel_frame],
      do: accept_external_frame(request, state)

  def request(%Request{} = request, %__MODULE__{} = state),
    do: {:error, {:invalid_uslp_service, request.service}, state}

  def request(value, %__MODULE__{} = state),
    do: {:error, {:invalid_uslp_service_request, value}, state}

  @spec only_idle(binary(), 0..65_535, t()) ::
          {:ok, LinkFrame.t(), t()} | {:error, term(), t()}
  def only_idle(physical_channel, scid, %__MODULE__{} = state) do
    with {:ok, configuration} <- fetch_configuration(physical_channel, scid, 63, 0, state),
         {:ok, insert_sdus, pending_insert} <-
           take_queue(
             state.pending_insert,
             physical_channel,
             configuration.insert_zone_length,
             1,
             :insert
           ),
         context =
           %{configuration: configuration}
           |> maybe_put(:insert_zone, List.first(insert_sdus)),
         {:ok, frame, next_segmentation} <- Segmentation.only_idle(context, state.segmentation) do
      {:ok, frame, %{state | segmentation: next_segmentation, pending_insert: pending_insert}}
    else
      {:error, reason} -> {:error, reason, state}
      {:error, reason, _segmentation} -> {:error, reason, state}
    end
  end

  @spec take_cop_directives(t()) :: {[map()], t()}
  def take_cop_directives(%__MODULE__{} = state) do
    {Enum.reverse(state.cop_directives), %{state | cop_directives: []}}
  end

  @spec ingest(LinkFrame.t(), t()) ::
          {:ok, [Indication.t()], t()} | {:error, term(), t()}
  def ingest(%LinkFrame{} = frame, %__MODULE__{} = state) do
    case ingest_detailed(frame, %{}, state) do
      {:ok, indications, _anomalies, next_state} -> {:ok, indications, next_state}
      {:error, reason, _anomalies, next_state} -> {:error, reason, next_state}
    end
  end

  @spec ingest_detailed(LinkFrame.t(), map(), t()) ::
          {:ok, [Indication.t()], [map()], t()}
          | {:error, term(), [map()], t()}
  def ingest_detailed(%LinkFrame{profile: :uslp} = frame, ctx, %__MODULE__{} = state)
      when is_map(ctx) do
    case frame_configuration(frame, state) do
      {:ok, configuration} ->
        ingest_configured_frame(frame, configuration, ctx, state)

      {:error, reason} ->
        {:error, reason, [], state}
    end
  end

  def ingest_detailed(%LinkFrame{profile: profile}, _ctx, %__MODULE__{} = state),
    do: {:error, {:invalid_profile, profile}, [], state}

  @spec ingest_wire(binary(), binary(), map(), t()) ::
          {:ok, [Indication.t()], [map()], binary(), t()} | {:error, term(), t()}
  def ingest_wire(binary, physical_channel, ctx, %__MODULE__{} = state)
      when is_binary(binary) and is_binary(physical_channel) and is_map(ctx) do
    case FrameCodec.decode_managed(binary, Map.values(state.configurations),
           physical_channel: physical_channel
         ) do
      {:ok, decoded, dropped, rest} ->
        {indications, anomalies, next_state} =
          Enum.reduce(decoded, {[], dropped, state}, &ingest_wire_frame(&1, ctx, &2))

        {:ok, indications, anomalies, rest, next_state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp ingest_configured_frame(frame, configuration, ctx, state) do
    virtual = virtual_address(configuration)
    master = master_address(configuration)

    cond do
      MapSet.member?(state.master_frame_services, master) ->
        ingest_frame_service(:master_channel_frame, frame, configuration, ctx, state)

      MapSet.member?(state.virtual_frame_services, virtual) ->
        ingest_frame_service(:virtual_channel_frame, frame, configuration, ctx, state)

      true ->
        ingest_generated_frame(frame, ctx, state)
    end
  end

  defp ingest_wire_frame(evidence, ctx, {indications, anomalies, current}) do
    case ingest_detailed(evidence.frame, ctx, current) do
      {:ok, emitted, frame_anomalies, next} ->
        {indications ++ emitted, anomalies ++ frame_anomalies, next}

      {:error, reason, frame_anomalies, next} ->
        anomaly = %{
          anomaly_kind: :uslp_service_ingest_failed,
          scid: evidence.frame.scid,
          vcid: evidence.frame.vcid,
          map_id: evidence.frame.map_id,
          metadata: %{reason: reason}
        }

        {indications, anomalies ++ frame_anomalies ++ [anomaly], next}
    end
  end

  defp enqueue_ocf(request, state) do
    with {:ok, configuration} <- request_configuration(request, state),
         :ok <- reject_frame_service(configuration, state),
         true <- configuration.ocf?,
         :ok <- validate_exact_binary(request.data, 4, :ocf_sdu),
         :ok <-
           forbid_extra_request_fields(request, [
             :data,
             :physical_channel,
             :scid,
             :vcid,
             :map_id
           ]) do
      key = virtual_address(configuration)
      pending = enqueue(state.pending_ocf, key, request.data)
      {:ok, [], %{state | pending_ocf: pending}}
    else
      false -> {:error, :ocf_service_not_configured, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp enqueue_insert(request, state) do
    with {:ok, physical_channel} <- request_physical_channel(request),
         {:ok, length} <- insert_length(physical_channel, state),
         :ok <- validate_exact_binary(request.data, length, :in_sdu),
         :ok <- forbid_extra_request_fields(request, [:data, :physical_channel]) do
      pending = enqueue(state.pending_insert, physical_channel, request.data)
      {:ok, [], %{state | pending_insert: pending}}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp enqueue_cop_directive(request, state) do
    with {:ok, configuration} <- request_configuration(request, state),
         :ok <- reject_frame_service(configuration, state),
         :ok <- validate_cop_configuration(configuration),
         :ok <- validate_cop_directive(request.directive),
         :ok <-
           forbid_extra_request_fields(request, [
             :directive,
             :physical_channel,
             :scid,
             :vcid,
             :map_id
           ]) do
      action = %{
        cop: configuration.cop,
        directive: request.directive,
        physical_channel: configuration.physical_channel,
        scid: configuration.scid,
        vcid: configuration.vcid,
        meta: request.meta
      }

      {:ok, [], %{state | cop_directives: [action | state.cop_directives]}}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp generate_frames(request, state) do
    with {:ok, configuration} <- request_configuration(request, state),
         :ok <- reject_frame_service(configuration, state),
         :ok <- validate_primary_service(request, configuration),
         {:ok, sdu} <- request_sdu(request, configuration),
         preview_context <- preview_context(request, configuration),
         {:ok, frames, next_segmentation} <-
           Segmentation.segment(sdu, preview_context, state.segmentation),
         count = length(frames),
         {:ok, ocf_sdus, pending_ocf} <-
           take_queue(
             state.pending_ocf,
             virtual_address(configuration),
             if(configuration.ocf?, do: 4, else: 0),
             count,
             :ocf
           ),
         {:ok, insert_sdus, pending_insert} <-
           take_queue(
             state.pending_insert,
             configuration.physical_channel,
             configuration.insert_zone_length,
             count,
             :insert
           ) do
      completed =
        frames
        |> Enum.with_index()
        |> Enum.map(fn {frame, index} ->
          frame
          |> attach_ocf(Enum.at(ocf_sdus, index))
          |> attach_insert(Enum.at(insert_sdus, index))
          |> tag_request(request)
        end)

      {:ok, completed,
       %{
         state
         | segmentation: next_segmentation,
           pending_ocf: pending_ocf,
           pending_insert: pending_insert
       }}
    else
      {:error, reason} -> {:error, reason, state}
      {:error, reason, _segmentation} -> {:error, reason, state}
    end
  end

  defp accept_external_frame(request, state) do
    with {:ok, frame, configuration} <- normalize_external_frame(request, state),
         :ok <- validate_external_service(request.service, configuration, state),
         {:ok, _encoded} <- FrameCodec.encode(frame, configuration: configuration) do
      {:ok, [tag_request(frame, request)], state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp normalize_external_frame(%Request{frame: %LinkFrame{profile: :uslp} = frame}, state) do
    with {:ok, configuration} <- frame_configuration(frame, state),
         do: {:ok, frame, configuration}
  end

  defp normalize_external_frame(%Request{frame: binary} = request, state)
       when is_binary(binary) do
    with {:ok, configuration} <- request_configuration(request, state),
         {:ok, [frame], [], <<>>} <-
           FrameCodec.decode_detailed(binary, configuration: configuration) do
      {:ok, frame.frame, configuration}
    else
      {:ok, _decoded, dropped, rest} ->
        {:error, {:invalid_external_uslp_frame, dropped, byte_size(rest)}}

      {:error, _reason} = error ->
        error
    end
  end

  defp normalize_external_frame(request, _state),
    do: {:error, {:invalid_external_uslp_frame, request.frame}}

  defp validate_external_service(:virtual_channel_frame, configuration, state) do
    address = virtual_address(configuration)

    if MapSet.member?(state.virtual_frame_services, address),
      do: :ok,
      else: {:error, {:undeclared_virtual_channel_frame_service, address}}
  end

  defp validate_external_service(:master_channel_frame, configuration, state) do
    address = master_address(configuration)

    if MapSet.member?(state.master_frame_services, address),
      do: :ok,
      else: {:error, {:undeclared_master_channel_frame_service, address}}
  end

  defp ingest_frame_service(service, frame, configuration, ctx, state) do
    case Continuity.observe(frame, state.frame_continuity) do
      {:ok, continuity, next_continuity} ->
        indication = frame_indication(service, frame, configuration, ctx, continuity.loss?)
        {:ok, [indication], continuity.anomalies, %{state | frame_continuity: next_continuity}}

      {:error, reason} ->
        {:error, reason, [], state}
    end
  end

  defp ingest_generated_frame(frame, ctx, state) do
    case Reassembly.ingest_detailed(
           frame,
           Map.put_new(ctx, :direction, :downlink),
           state.reassembly
         ) do
      {:ok, sdus, anomalies, next_reassembly} ->
        {:ok, Enum.map(sdus, &indication/1), anomalies, %{state | reassembly: next_reassembly}}

      {:error, reason, anomalies, next_reassembly} ->
        {:error, reason, anomalies, %{state | reassembly: next_reassembly}}
    end
  end

  defp indication(%SDUOctets{} = sdu) do
    meta = sdu.meta

    %Indication{
      service: indication_service(sdu.sdu_kind_hint),
      data: sdu.octets,
      physical_channel: Map.fetch!(meta, :physical_channel),
      scid: sdu.scid,
      vcid: sdu.vcid,
      map_id: sdu.map_id,
      packet_version_number: Map.get(meta, :packet_version_number),
      sdu_id: Map.get(meta, :sdu_id),
      qos: Map.get(meta, :qos),
      quality: if(sdu.quality == :good, do: :complete, else: :partial),
      source_frames: sdu.source_frames,
      packet_quality_indicator: Map.get(meta, :packet_quality_indicator),
      mapa_sdu_loss_flag: Map.get(meta, :mapa_sdu_loss_flag),
      vca_sdu_loss_flag: Map.get(meta, :vca_sdu_loss_flag),
      octet_stream_data_loss_flag: Map.get(meta, :octet_stream_data_loss_flag),
      ocf_sdu_loss_flag: Map.get(meta, :ocf_sdu_loss_flag),
      in_sdu_loss_flag: Map.get(meta, :in_sdu_loss_flag),
      verification_status_code: Map.get(meta, :verification_status_code),
      timestamp: sdu.timestamp,
      meta: meta
    }
  end

  defp frame_indication(service, frame, configuration, ctx, loss?) do
    %Indication{
      service: service,
      frame: frame,
      physical_channel: configuration.physical_channel,
      scid: frame.scid,
      vcid: frame.vcid,
      map_id: frame.map_id,
      qos: Map.get(frame.meta, :qos),
      quality: if(frame.quality == :good, do: :complete, else: :partial),
      source_frames: [frame.frame_seq],
      frame_loss_flag: loss?,
      verification_status_code: Map.get(ctx, :verification_status_code),
      timestamp: frame.timestamp,
      meta: frame.meta
    }
  end

  defp request_sdu(request, configuration) do
    with :ok <- validate_non_empty_binary(request.data, :data) do
      {:ok,
       %SDUOctets{
         profile: :uslp,
         scid: configuration.scid,
         vcid: configuration.vcid,
         map_id: configuration.map_id,
         direction: :uplink,
         sdu_kind_hint: request_kind(request.service),
         octets: request.data,
         quality: :good,
         source_frames: [],
         timestamp: request.timestamp,
         meta: request.meta
       }}
    end
  end

  defp validate_primary_service(request, configuration) do
    with true <- service_matches_configuration?(request.service, configuration),
         :ok <- validate_qos(request.qos),
         :ok <- validate_repetitions(request.repetitions, configuration),
         :ok <- validate_request_pvn(request, configuration),
         :ok <-
           forbid_extra_request_fields(request, [
             :data,
             :physical_channel,
             :scid,
             :vcid,
             :map_id,
             :packet_version_number,
             :sdu_id,
             :qos,
             :repetitions,
             :timestamp
           ]) do
      :ok
    else
      false ->
        {:error,
         {:service_configuration_mismatch, request.service, configuration.data_field_content}}

      {:error, _reason} = error ->
        error
    end
  end

  defp service_matches_configuration?(:map_packet, %{
         data_field_content: :packets,
         packet_service: :map
       }),
       do: true

  defp service_matches_configuration?(:virtual_channel_packet, %{
         data_field_content: :packets,
         packet_service: :virtual_channel
       }),
       do: true

  defp service_matches_configuration?(:map_access, %{data_field_content: :mapa_sdu}), do: true

  defp service_matches_configuration?(:virtual_channel_access, %{data_field_content: :vca_sdu}),
    do: true

  defp service_matches_configuration?(:map_octet_stream, %{data_field_content: :octet_stream}),
    do: true

  defp service_matches_configuration?(_service, _configuration), do: false

  defp validate_request_pvn(
         %Request{service: service, data: data, packet_version_number: expected},
         _configuration
       )
       when service in [:map_packet, :virtual_channel_packet] do
    with {:ok, actual} <- PacketFormat.packet_version_number(data) do
      if is_nil(expected) or expected == actual,
        do: :ok,
        else: {:error, {:packet_version_mismatch, actual, expected}}
    end
  end

  defp validate_request_pvn(%Request{packet_version_number: nil}, _configuration), do: :ok

  defp validate_request_pvn(request, _configuration),
    do: {:error, {:unexpected_packet_version_number, request.packet_version_number}}

  defp preview_context(request, configuration) do
    capacity =
      max(
        Configuration.maximum_tfdz_octets(configuration, request.qos || :sequence_controlled),
        1
      )

    count = ceil_div(byte_size(request.data), capacity) + 2

    %{
      configuration: configuration,
      qos: request.qos || default_qos(configuration),
      truncated?: Map.get(request.meta, :truncated?, false),
      timestamp: request.timestamp,
      insert_zone_sdus:
        List.duplicate(:binary.copy(<<0>>, configuration.insert_zone_length), count),
      ocf_sdus: List.duplicate(<<0, 0, 0, 0>>, if(configuration.ocf?, do: count, else: 0))
    }
  end

  defp default_qos(%Configuration{data_field_content: :protocol_control}), do: :expedited
  defp default_qos(%Configuration{}), do: :sequence_controlled

  defp request_configuration(request, state) do
    with {:ok, physical} <- request_physical_channel(request) do
      fetch_configuration(physical, request.scid, request.vcid, request.map_id || 0, state)
    end
  end

  defp request_physical_channel(%Request{physical_channel: physical}) when is_binary(physical),
    do: {:ok, physical}

  defp request_physical_channel(%Request{}),
    do: {:error, {:missing_request_address, :physical_channel}}

  defp frame_configuration(frame, state) do
    physical = Map.get(frame.meta, :physical_channel)
    fetch_configuration(physical, frame.scid, frame.vcid, frame.map_id, state)
  end

  defp fetch_configuration(physical, scid, vcid, map_id, state) do
    case Map.fetch(state.configurations, {physical, scid, vcid, map_id}) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> {:error, {:unknown_uslp_channel, physical, scid, vcid, map_id}}
    end
  end

  defp reject_frame_service(configuration, state) do
    cond do
      MapSet.member?(state.master_frame_services, master_address(configuration)) ->
        {:error, {:master_channel_reserved_for_frame_service, master_address(configuration)}}

      MapSet.member?(state.virtual_frame_services, virtual_address(configuration)) ->
        {:error, {:virtual_channel_reserved_for_frame_service, virtual_address(configuration)}}

      true ->
        :ok
    end
  end

  defp normalize_frame_services(services, indexed) when is_list(services) do
    Enum.reduce_while(services, {:ok, MapSet.new(), MapSet.new()}, fn
      {:virtual_channel, {physical, scid, vcid} = address}, {:ok, virtual, master} ->
        if virtual_channel_exists?(indexed, address),
          do: {:cont, {:ok, MapSet.put(virtual, address), master}},
          else:
            {:halt, {:error, {:unknown_virtual_channel_frame_service, {physical, scid, vcid}}}}

      {:master_channel, {physical, scid} = address}, {:ok, virtual, master} ->
        if master_channel_exists?(indexed, address),
          do: {:cont, {:ok, virtual, MapSet.put(master, address)}},
          else: {:halt, {:error, {:unknown_master_channel_frame_service, {physical, scid}}}}

      value, _acc ->
        {:halt, {:error, {:invalid_uslp_frame_service, value}}}
    end)
  end

  defp normalize_frame_services(value, _indexed),
    do: {:error, {:invalid_uslp_frame_services, value}}

  defp virtual_channel_exists?(indexed, address) do
    Enum.any?(indexed, fn {{physical, scid, vcid, _map}, _configuration} ->
      {physical, scid, vcid} == address
    end)
  end

  defp master_channel_exists?(indexed, address) do
    Enum.any?(indexed, fn {{physical, scid, _vcid, _map}, _configuration} ->
      {physical, scid} == address
    end)
  end

  defp validate_frame_services(indexed, virtual_frames, master_frames) do
    conflict =
      Enum.find(MapSet.to_list(virtual_frames), fn {physical, scid, _vcid} ->
        MapSet.member?(master_frames, {physical, scid})
      end)

    cond do
      conflict ->
        {:error, {:frame_service_hierarchy_conflict, conflict}}

      Enum.any?(indexed, fn {_address, configuration} ->
        reserved =
            MapSet.member?(virtual_frames, virtual_address(configuration)) or
              MapSet.member?(master_frames, master_address(configuration))

        reserved and configuration.insert_zone_length > 0
      end) ->
        {:error, :frame_services_forbid_provider_insert_zone}

      true ->
        :ok
    end
  end

  defp insert_length(physical_channel, state) do
    lengths =
      state.configurations
      |> Map.values()
      |> Enum.filter(&(&1.physical_channel == physical_channel))
      |> Enum.map(& &1.insert_zone_length)
      |> Enum.uniq()

    case lengths do
      [0] -> {:error, :insert_service_not_configured}
      [length] -> {:ok, length}
      [] -> {:error, {:unknown_physical_channel, physical_channel}}
    end
  end

  defp take_queue(queues, _key, 0, count, _kind), do: {:ok, List.duplicate(nil, count), queues}

  defp take_queue(queues, key, _octets, count, kind) do
    values = Map.get(queues, key, [])

    if length(values) >= count do
      {taken, rest} = Enum.split(values, count)
      next = if(rest == [], do: Map.delete(queues, key), else: Map.put(queues, key, rest))
      {:ok, taken, next}
    else
      {:error, {:insufficient_synchronous_sdus, kind, key, count, length(values)}}
    end
  end

  defp enqueue(queues, key, value), do: Map.update(queues, key, [value], &(&1 ++ [value]))

  defp attach_ocf(frame, nil), do: %{frame | ocf: nil}
  defp attach_ocf(frame, ocf), do: %{frame | ocf: ocf}

  defp attach_insert(frame, nil), do: %{frame | meta: Map.put(frame.meta, :insert_zone, nil)}

  defp attach_insert(frame, insert),
    do: %{frame | meta: Map.put(frame.meta, :insert_zone, insert)}

  defp tag_request(frame, request) do
    %{
      frame
      | meta:
          frame.meta
          |> Map.put(:service, request.service)
          |> Map.put(:sdu_id, request.sdu_id)
          |> Map.put(:repetitions, request.repetitions)
    }
  end

  defp indication_service(:map_packet), do: :map_packet
  defp indication_service(:virtual_channel_packet), do: :virtual_channel_packet
  defp indication_service(:mapa_sdu), do: :map_access
  defp indication_service(:vca_sdu), do: :virtual_channel_access
  defp indication_service(:octet_stream), do: :map_octet_stream
  defp indication_service(:operational_control), do: :master_channel_operational_control
  defp indication_service(:insert), do: :insert
  defp indication_service(:protocol_control), do: :cops_management

  defp request_kind(:map_packet), do: :map_packet
  defp request_kind(:virtual_channel_packet), do: :virtual_channel_packet
  defp request_kind(:map_access), do: :mapa_sdu
  defp request_kind(:virtual_channel_access), do: :vca_sdu
  defp request_kind(:map_octet_stream), do: :octet_stream

  defp virtual_address(configuration),
    do: {configuration.physical_channel, configuration.scid, configuration.vcid}

  defp master_address(configuration), do: {configuration.physical_channel, configuration.scid}

  defp forbid_extra_request_fields(request, allowed) do
    fields = [
      :data,
      :frame,
      :physical_channel,
      :scid,
      :vcid,
      :map_id,
      :packet_version_number,
      :sdu_id,
      :qos,
      :repetitions,
      :directive,
      :timestamp
    ]

    unexpected = Enum.find(fields -- allowed, &(not is_nil(Map.fetch!(request, &1))))
    if unexpected, do: {:error, {:unexpected_request_field, unexpected}}, else: :ok
  end

  defp validate_qos(nil), do: :ok
  defp validate_qos(value) when value in [:sequence_controlled, :expedited], do: :ok
  defp validate_qos(value), do: {:error, {:invalid_uslp_qos, value}}
  defp validate_repetitions(nil, _configuration), do: :ok

  defp validate_repetitions(value, configuration)
       when is_integer(value) and value >= 0 and value <= configuration.maximum_repetitions,
       do: :ok

  defp validate_repetitions(value, configuration),
    do: {:error, {:invalid_repetitions, value, configuration.maximum_repetitions}}

  defp validate_cop_configuration(%Configuration{cop: :none}),
    do: {:error, :cop_service_not_configured}

  defp validate_cop_configuration(%Configuration{}), do: :ok
  defp validate_cop_directive(nil), do: {:error, :missing_cop_directive}
  defp validate_cop_directive(_directive), do: :ok

  defp validate_exact_binary(value, length, _field)
       when is_binary(value) and byte_size(value) == length,
       do: :ok

  defp validate_exact_binary(value, length, field),
    do: {:error, {:invalid_sdu_length, field, value, length}}

  defp validate_non_empty_binary(value, _field) when is_binary(value) and byte_size(value) > 0,
    do: :ok

  defp validate_non_empty_binary(value, field), do: {:error, {:invalid_field, field, value}}
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)
end
