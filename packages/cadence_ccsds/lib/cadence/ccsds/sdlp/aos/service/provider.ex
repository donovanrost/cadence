defmodule Cadence.CCSDS.SDLP.AOS.Service.Provider do
  @moduledoc """
  Pure composition of all seven AOS transfer services.

  VCP, Bitstream, and VCA requests use the AOS generation kernel. VC_OCF and
  Insert requests enqueue synchronous SDUs which are consumed once per emitted
  frame. VCF and MCF requests pass complete, independently generated AOS frames
  after managed validation. Scheduling, VC/MC multiplexing, channel coding,
  persistence, and optional SDLS processing remain caller concerns.

  VCF/MCF service instances are declared with `:frame_services` at init, using
  `{:virtual_channel, {physical_channel, scid, vcid}}` or
  `{:master_channel, {physical_channel, scid}}`. The provider enforces their
  service-exclusivity and Insert-Zone restrictions.
  """

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}

  alias Cadence.CCSDS.SDLP.AOS.{Configuration, Continuity, FrameCodec, Reassembly, Segmentation}
  alias Cadence.CCSDS.SDLP.AOS.Service.{Indication, Request}
  alias Cadence.CCSDS.SpacePacket.Stream

  @type physical_address :: {binary(), 0..1023, 0..63}
  @type master_address :: {binary(), 0..1023}

  @type t :: %__MODULE__{
          configurations: %{required(physical_address()) => Configuration.t()},
          virtual_frame_services: MapSet.t(physical_address()),
          master_frame_services: MapSet.t(master_address()),
          segmentation: map(),
          reassembly: map(),
          frame_continuity: Continuity.t(),
          pending_ocf: %{optional(physical_address()) => [binary()]},
          pending_insert: %{optional(binary()) => [binary()]}
        }

  defstruct configurations: %{},
            virtual_frame_services: MapSet.new(),
            master_frame_services: MapSet.new(),
            segmentation: nil,
            reassembly: nil,
            frame_continuity: nil,
            pending_ocf: %{},
            pending_insert: %{}

  @spec init([Configuration.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def init(configurations, opts \\ []) when is_list(configurations) and is_list(opts) do
    with :ok <- Configuration.validate_plan(configurations),
         {:ok, indexed} <- index_configurations(configurations),
         {:ok, virtual_frames, master_frames} <-
           normalize_frame_services(Keyword.get(opts, :frame_services, []), indexed),
         :ok <- validate_frame_service_plan(indexed, virtual_frames, master_frames),
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

  @spec request(Request.t(), t()) ::
          {:ok, [LinkFrame.t()], t()} | {:error, term(), t()}
  def request(%Request{service: :virtual_channel_operational_control} = request, state) do
    enqueue_ocf(request, state)
  end

  def request(%Request{service: :insert} = request, state) do
    enqueue_insert(request, state)
  end

  def request(%Request{service: service} = request, state)
      when service in [:virtual_channel_packet, :bitstream, :virtual_channel_access] do
    generate_frames(request, state)
  end

  def request(%Request{service: service} = request, state)
      when service in [:virtual_channel_frame, :master_channel_frame] do
    accept_external_frame(request, state)
  end

  def request(%Request{} = request, %__MODULE__{} = state),
    do: {:error, {:invalid_aos_service, request.service}, state}

  def request(value, %__MODULE__{} = state),
    do: {:error, {:invalid_aos_service_request, value}, state}

  @spec only_idle(binary(), 0..1023, t()) ::
          {:ok, LinkFrame.t(), t()} | {:error, term(), t()}
  def only_idle(physical_channel, scid, %__MODULE__{} = state) do
    with {:ok, configuration} <-
           fetch_configuration(physical_channel, scid, 63, state.configurations),
         :ok <- require_content(configuration, :idle_data),
         {:ok, insert_sdus, pending_insert} <-
           take_insert(state.pending_insert, configuration, 1),
         context =
           %{configuration: configuration}
           |> maybe_put_single(:insert_zone, insert_sdus),
         {:ok, frame, next_segmentation} <-
           Segmentation.only_idle(context, state.segmentation) do
      {:ok, frame, %{state | segmentation: next_segmentation, pending_insert: pending_insert}}
    else
      {:error, reason} -> {:error, reason, state}
      {:error, reason, _segmentation} -> {:error, reason, state}
    end
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
  def ingest_detailed(%LinkFrame{profile: :aos} = frame, ctx, %__MODULE__{} = state)
      when is_map(ctx) do
    case frame_configuration(frame, state.configurations) do
      {:ok, configuration} ->
        ingest_configured_frame_service(frame, configuration, ctx, state)

      {:error, reason} ->
        {:error, reason, [], state}
    end
  end

  def ingest_detailed(%LinkFrame{profile: profile}, _ctx, %__MODULE__{} = state),
    do: {:error, {:invalid_profile, profile}, [], state}

  defp ingest_configured_frame_service(frame, configuration, ctx, state) do
    address = Configuration.physical_address(configuration)
    master = {configuration.physical_channel, configuration.scid}

    cond do
      MapSet.member?(state.master_frame_services, master) ->
        {:ok, [frame_indication(:master_channel_frame, frame, configuration, ctx, false)], [],
         state}

      MapSet.member?(state.virtual_frame_services, address) ->
        ingest_virtual_frame_service(frame, configuration, ctx, state)

      true ->
        ingest_generated_frame(frame, ctx, state)
    end
  end

  @doc """
  Decodes and ingests all complete AOS frames in one physical-channel stream.

  Decode drops and service-level reception failures are returned as portable
  anomalies; an incomplete trailing frame is returned unchanged.
  """
  @spec ingest_wire(binary(), binary(), map(), t()) ::
          {:ok, [Indication.t()], [map()], binary(), t()} | {:error, term(), t()}
  def ingest_wire(binary, physical_channel, ctx, %__MODULE__{} = state)
      when is_binary(binary) and is_binary(physical_channel) and is_map(ctx) do
    configurations = Map.values(state.configurations)

    case FrameCodec.decode_managed(binary, configurations, physical_channel: physical_channel) do
      {:ok, decoded, dropped, rest} ->
        {indications, anomalies, next_state} =
          Enum.reduce(decoded, {[], dropped, state}, fn evidence, acc ->
            ingest_wire_frame(evidence.frame, ctx, acc)
          end)

        {:ok, Enum.reverse(indications), anomalies, rest, next_state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  def ingest_wire(binary, physical_channel, ctx, %__MODULE__{} = state),
    do: {:error, {:invalid_aos_wire_input, binary, physical_channel, ctx}, state}

  defp ingest_wire_frame(frame, ctx, {indications, anomalies, state}) do
    case ingest_detailed(frame, ctx, state) do
      {:ok, emitted, frame_anomalies, next_state} ->
        {Enum.reverse(emitted, indications), anomalies ++ frame_anomalies, next_state}

      {:error, reason, frame_anomalies, next_state} ->
        anomaly = %{
          anomaly_kind: :aos_service_ingest_failed,
          scid: frame.scid,
          vcid: frame.vcid,
          frame_seq: frame.frame_seq,
          metadata: %{reason: reason}
        }

        {indications, anomalies ++ frame_anomalies ++ [anomaly], next_state}
    end
  end

  defp enqueue_ocf(request, state) do
    with {:ok, configuration} <- request_configuration(request, state),
         :ok <- reject_reserved_frame_service(configuration, state),
         true <- configuration.ocf?,
         :ok <- validate_exact_binary(request.data, 4, :ocf_sdu),
         :ok <- forbid_frame_and_bit_metadata(request) do
      address = Configuration.physical_address(configuration)
      pending = enqueue(state.pending_ocf, address, request.data)
      {:ok, [], %{state | pending_ocf: pending}}
    else
      false -> {:error, :ocf_service_not_configured, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp enqueue_insert(request, state) do
    with {:ok, physical_channel} <- request_physical_channel(request),
         {:ok, length} <- insert_length(physical_channel, state.configurations),
         :ok <- validate_exact_binary(request.data, length, :in_sdu),
         :ok <- forbid_frame_and_bit_metadata(request) do
      pending = enqueue(state.pending_insert, physical_channel, request.data)
      {:ok, [], %{state | pending_insert: pending}}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp generate_frames(request, state) do
    with {:ok, configuration} <- request_configuration(request, state),
         :ok <- reject_reserved_frame_service(configuration, state),
         :ok <- validate_primary_request(request, configuration),
         sdu = request_sdu(request, configuration),
         context = placeholder_context(request, configuration),
         {:ok, frames, next_segmentation} <-
           Segmentation.segment(sdu, context, state.segmentation),
         count = length(frames),
         {:ok, ocf_sdus, pending_ocf} <- take_ocf(state.pending_ocf, configuration, count),
         {:ok, insert_sdus, pending_insert} <-
           take_insert(state.pending_insert, configuration, count) do
      completed =
        frames
        |> Enum.with_index()
        |> Enum.map(fn {frame, index} ->
          frame
          |> attach_ocf(Enum.at(ocf_sdus, index))
          |> attach_insert(Enum.at(insert_sdus, index))
          |> tag_service(request.service)
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
      {:ok, [tag_service(frame, request.service)], state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp normalize_external_frame(
         %Request{frame: %LinkFrame{profile: :aos} = frame} = request,
         state
       ) do
    with {:ok, configuration} <- external_frame_configuration(request, frame, state) do
      {:ok, frame, configuration}
    end
  end

  defp normalize_external_frame(%Request{frame: binary} = request, state)
       when is_binary(binary) do
    with {:ok, configuration} <- request_configuration(request, state),
         {:ok, [frame], [], <<>>} <-
           FrameCodec.decode_detailed(binary, configuration: configuration) do
      {:ok, frame.frame, configuration}
    else
      {:ok, _decoded, dropped, rest} ->
        {:error, {:invalid_external_aos_frame, dropped, byte_size(rest)}}

      {:error, _reason} = error ->
        error
    end
  end

  defp normalize_external_frame(request, _state),
    do: {:error, {:invalid_external_aos_frame, request.frame}}

  defp external_frame_configuration(request, frame, state) do
    physical_channel = request.physical_channel || Map.get(frame.meta, :physical_channel)
    fetch_configuration(physical_channel, frame.scid, frame.vcid, state.configurations)
  end

  defp validate_external_service(:virtual_channel_frame, configuration, state) do
    address = Configuration.physical_address(configuration)

    if MapSet.member?(state.virtual_frame_services, address),
      do: :ok,
      else: {:error, {:undeclared_virtual_channel_frame_service, address}}
  end

  defp validate_external_service(:master_channel_frame, configuration, state) do
    master = {configuration.physical_channel, configuration.scid}

    if MapSet.member?(state.master_frame_services, master),
      do: :ok,
      else: {:error, {:undeclared_master_channel_frame_service, master}}
  end

  defp ingest_virtual_frame_service(frame, configuration, ctx, state) do
    case Continuity.observe(frame, state.frame_continuity) do
      {:ok, continuity, next_continuity} ->
        indication =
          frame_indication(
            :virtual_channel_frame,
            frame,
            configuration,
            ctx,
            continuity.loss?
          )

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

  defp frame_indication(service, frame, configuration, ctx, continuity_loss?) do
    frame_loss =
      if service == :master_channel_frame,
        do: Map.get(ctx, :frame_loss_flag, false),
        else: continuity_loss?

    %Indication{
      service: service,
      data: nil,
      frame: frame,
      physical_channel: configuration.physical_channel,
      scid: frame.scid,
      vcid: if(service == :virtual_channel_frame, do: frame.vcid, else: nil),
      quality: :complete,
      source_frames: [frame.frame_seq],
      frame_loss_flag: frame_loss,
      timestamp: frame.timestamp,
      meta: frame.meta
    }
  end

  defp indication(%SDUOctets{} = sdu) do
    %Indication{
      service: indication_service(sdu.sdu_kind_hint),
      data: sdu.octets,
      frame: nil,
      physical_channel: Map.get(sdu.meta, :physical_channel, "default"),
      scid: sdu.scid,
      vcid: sdu.vcid,
      packet_version_number: Map.get(sdu.meta, :packet_version_number),
      quality: if(sdu.quality == :partial, do: :partial, else: :complete),
      source_frames: sdu.source_frames,
      valid_bits: Map.get(sdu.meta, :valid_bits),
      bitstream_data_loss_flag: Map.get(sdu.meta, :bitstream_data_loss_flag),
      vca_sdu_loss_flag: Map.get(sdu.meta, :vca_sdu_loss_flag),
      ocf_sdu_loss_flag: Map.get(sdu.meta, :ocf_sdu_loss_flag),
      in_sdu_loss_flag: Map.get(sdu.meta, :in_sdu_loss_flag),
      verification_status_code: Map.get(sdu.meta, :verification_status_code),
      timestamp: sdu.timestamp,
      meta: sdu.meta
    }
  end

  defp validate_primary_request(
         %Request{service: :virtual_channel_packet} = request,
         configuration
       ) do
    with :ok <- require_content(configuration, :m_pdu),
         :ok <- validate_binary(request.data, :packet),
         {:ok, [packet], <<>>} <-
           Stream.extract(request.data, max_packet_size: configuration.maximum_packet_octets),
         <<version::3, _rest::bitstring>> <- packet,
         true <- version == request.packet_version_number,
         true <- version in configuration.valid_packet_version_numbers,
         :ok <- forbid_frame_and_bit_metadata(request) do
      :ok
    else
      {:ok, packets, rest} ->
        {:error, {:vcp_request_requires_one_packet, length(packets), byte_size(rest)}}

      false ->
        {:error, {:invalid_packet_version_number, request.packet_version_number}}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_primary_request(%Request{service: :bitstream} = request, configuration) do
    with :ok <- require_content(configuration, :b_pdu),
         :ok <- validate_binary(request.data, :bitstream_data),
         :ok <- validate_valid_bits(request.valid_bits, request.data),
         true <- is_nil(request.packet_version_number),
         true <- is_nil(request.frame) do
      :ok
    else
      false -> {:error, :invalid_bitstream_request_metadata}
      {:error, _reason} = error -> error
    end
  end

  defp validate_primary_request(
         %Request{service: :virtual_channel_access} = request,
         configuration
       ) do
    with :ok <- require_content(configuration, :vca_sdu),
         :ok <-
           validate_exact_binary(
             request.data,
             Configuration.payload_octets(configuration),
             :vca_sdu
           ) do
      forbid_frame_and_bit_metadata(request)
    end
  end

  defp request_sdu(request, configuration) do
    meta =
      request.meta
      |> Map.put(:valid_bits, request.valid_bits)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    %SDUOctets{
      profile: :aos,
      scid: configuration.scid,
      vcid: configuration.vcid,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: sdu_kind(request.service),
      octets: request.data,
      quality: :good,
      source_frames: [],
      timestamp: request.timestamp,
      meta: meta
    }
  end

  defp placeholder_context(request, configuration) do
    %{
      configuration: configuration,
      replay_flag: Map.get(request.meta, :replay_flag, 0),
      insert_zone: placeholder(configuration.insert_zone_length),
      ocf: placeholder(if(configuration.ocf?, do: 4, else: 0))
    }
  end

  defp take_ocf(pending, %Configuration{ocf?: false}, count),
    do: {:ok, List.duplicate(nil, count), pending}

  defp take_ocf(pending, configuration, count) do
    take_queue(pending, Configuration.physical_address(configuration), count, :ocf_sdu)
  end

  defp take_insert(pending, %Configuration{insert_zone_length: 0}, count),
    do: {:ok, List.duplicate(nil, count), pending}

  defp take_insert(pending, configuration, count) do
    take_queue(pending, configuration.physical_channel, count, :in_sdu)
  end

  defp take_queue(pending, key, count, kind) do
    queued = Map.get(pending, key, [])

    if length(queued) >= count do
      {taken, remaining} = Enum.split(queued, count)

      next_pending =
        if(remaining == [], do: Map.delete(pending, key), else: Map.put(pending, key, remaining))

      {:ok, taken, next_pending}
    else
      {:error, {:insufficient_synchronous_sdus, kind, key, count, length(queued)}}
    end
  end

  defp attach_ocf(frame, nil), do: frame
  defp attach_ocf(frame, ocf), do: %{frame | ocf: ocf}

  defp attach_insert(frame, nil), do: frame

  defp attach_insert(frame, insert) do
    %{frame | meta: Map.put(frame.meta, :insert_zone, insert)}
  end

  defp tag_service(frame, service),
    do: %{frame | meta: Map.put(frame.meta, :aos_service, service)}

  defp request_configuration(request, state) do
    fetch_configuration(
      request.physical_channel,
      request.scid,
      request.vcid,
      state.configurations
    )
  end

  defp frame_configuration(frame, configurations) do
    physical = Map.get(frame.meta, :physical_channel)
    fetch_configuration(physical, frame.scid, frame.vcid, configurations)
  end

  defp fetch_configuration(physical, scid, vcid, configurations) when is_binary(physical) do
    case Map.fetch(configurations, {physical, scid, vcid}) do
      {:ok, configuration} -> {:ok, configuration}
      :error -> {:error, {:unknown_aos_service_address, physical, scid, vcid}}
    end
  end

  defp fetch_configuration(nil, scid, vcid, configurations) do
    matches =
      configurations
      |> Map.values()
      |> Enum.filter(&Configuration.matches?(&1, scid, vcid))

    case matches do
      [configuration] -> {:ok, configuration}
      [] -> {:error, {:unknown_aos_service_address, scid, vcid}}
      _many -> {:error, {:ambiguous_aos_service_address, scid, vcid}}
    end
  end

  defp fetch_configuration(physical, scid, vcid, _configurations),
    do: {:error, {:invalid_aos_service_address, physical, scid, vcid}}

  defp index_configurations(configurations) do
    {:ok, Map.new(configurations, &{Configuration.physical_address(&1), &1})}
  end

  defp normalize_frame_services(values, configurations) when is_list(values) do
    Enum.reduce_while(values, {:ok, MapSet.new(), MapSet.new()}, fn
      {:virtual_channel, {physical, scid, vcid}}, {:ok, virtual, master}
      when is_binary(physical) ->
        address = {physical, scid, vcid}

        if Map.has_key?(configurations, address),
          do: {:cont, {:ok, MapSet.put(virtual, address), master}},
          else: {:halt, {:error, {:unknown_virtual_frame_service, address}}}

      {:master_channel, {physical, scid}}, {:ok, virtual, master} when is_binary(physical) ->
        address = {physical, scid}

        if master_configuration?(configurations, address),
          do: {:cont, {:ok, virtual, MapSet.put(master, address)}},
          else: {:halt, {:error, {:unknown_master_frame_service, address}}}

      value, _acc ->
        {:halt, {:error, {:invalid_aos_frame_service, value}}}
    end)
  end

  defp normalize_frame_services(value, _configurations),
    do: {:error, {:invalid_aos_frame_services, value}}

  defp master_configuration?(configurations, address) do
    Enum.any?(configurations, fn {{physical, scid, _vcid}, _configuration} ->
      {physical, scid} == address
    end)
  end

  defp validate_frame_service_plan(configurations, virtual, master) do
    with :ok <- validate_frame_service_exclusivity(virtual, master) do
      frame_physicals =
        Enum.map(virtual, &elem(&1, 0)) ++ Enum.map(master, &elem(&1, 0))

      invalid =
        Enum.find(configurations, fn {{physical, _scid, _vcid}, configuration} ->
          physical in frame_physicals and configuration.insert_zone_length > 0
        end)

      if invalid,
        do: {:error, {:insert_zone_forbidden_with_frame_service, elem(invalid, 0)}},
        else: :ok
    end
  end

  defp validate_frame_service_exclusivity(virtual, master) do
    conflict =
      Enum.find(virtual, fn {physical, scid, _vcid} ->
        MapSet.member?(master, {physical, scid})
      end)

    if conflict, do: {:error, {:overlapping_aos_frame_services, conflict}}, else: :ok
  end

  defp reject_reserved_frame_service(configuration, state) do
    address = Configuration.physical_address(configuration)
    master = {configuration.physical_channel, configuration.scid}

    cond do
      MapSet.member?(state.master_frame_services, master) ->
        {:error, {:master_channel_reserved_for_frame_service, master}}

      MapSet.member?(state.virtual_frame_services, address) ->
        {:error, {:virtual_channel_reserved_for_frame_service, address}}

      true ->
        :ok
    end
  end

  defp insert_length(physical_channel, configurations) do
    lengths =
      configurations
      |> Enum.filter(fn {{physical, _scid, _vcid}, _configuration} ->
        physical == physical_channel
      end)
      |> Enum.map(fn {_address, configuration} -> configuration.insert_zone_length end)
      |> Enum.uniq()

    case lengths do
      [length] when length > 0 -> {:ok, length}
      [0] -> {:error, {:insert_service_not_configured, physical_channel}}
      [] -> {:error, {:unknown_physical_channel, physical_channel}}
      _many -> {:error, {:inconsistent_insert_service, physical_channel}}
    end
  end

  defp request_physical_channel(%Request{physical_channel: value})
       when is_binary(value) and byte_size(value) > 0,
       do: {:ok, value}

  defp request_physical_channel(request),
    do: {:error, {:invalid_physical_channel, request.physical_channel}}

  defp validate_binary(value, _field) when is_binary(value) and byte_size(value) > 0, do: :ok
  defp validate_binary(value, field), do: {:error, {:invalid_service_data, field, value}}

  defp validate_exact_binary(value, size, _field)
       when is_binary(value) and byte_size(value) == size,
       do: :ok

  defp validate_exact_binary(value, size, field),
    do: {:error, {:invalid_service_data_length, field, byte_size_or_value(value), size}}

  defp validate_valid_bits(value, data)
       when is_integer(value) and value > 0 and value <= bit_size(data),
       do: :ok

  defp validate_valid_bits(value, data),
    do: {:error, {:invalid_bitstream_length, value, bit_size(data)}}

  defp forbid_frame_and_bit_metadata(%Request{frame: nil, valid_bits: nil}), do: :ok

  defp forbid_frame_and_bit_metadata(request),
    do: {:error, {:invalid_service_metadata, request.service}}

  defp require_content(%Configuration{data_field_content: expected}, expected), do: :ok

  defp require_content(configuration, expected),
    do: {:error, {:service_configuration_mismatch, expected, configuration.data_field_content}}

  defp sdu_kind(:virtual_channel_packet), do: :space_packet
  defp sdu_kind(:bitstream), do: :bitstream
  defp sdu_kind(:virtual_channel_access), do: :vca_sdu

  defp indication_service(:space_packet), do: :virtual_channel_packet
  defp indication_service(:bitstream), do: :bitstream
  defp indication_service(:vca_sdu), do: :virtual_channel_access
  defp indication_service(:operational_control_field), do: :virtual_channel_operational_control
  defp indication_service(:insert), do: :insert

  defp enqueue(pending, key, value), do: Map.update(pending, key, [value], &(&1 ++ [value]))
  defp placeholder(0), do: nil
  defp placeholder(size), do: :binary.copy(<<0>>, size)

  defp maybe_put_single(context, _field, [nil]), do: context
  defp maybe_put_single(context, field, [value]), do: Map.put(context, field, value)

  defp byte_size_or_value(value) when is_binary(value), do: byte_size(value)
  defp byte_size_or_value(value), do: value
end
