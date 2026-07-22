defmodule Cadence.CCSDS.SDLP.USLP.Configuration do
  @moduledoc """
  Managed parameters for one USLP service access point.

  USLP places frame length, QoS and counter size on the wire, but physical,
  Master, Virtual and MAP Channel membership and the permitted service remain
  managed facts. A configuration is keyed by physical channel, SCID, VCID and
  MAP ID so a managed decoder can route mixed variable-length streams.
  """

  alias Cadence.CCSDS.Packet.Configuration, as: PacketConfiguration
  alias Cadence.CCSDS.SDLP.USLP.TFDF

  @type frame_type :: :fixed | :variable
  @type source_destination :: :source | :destination
  @type qos :: :sequence_controlled | :expedited
  @type cop :: :none | :cop1 | :copp
  @type data_field_content ::
          :packets
          | :mapa_sdu
          | :vca_sdu
          | :octet_stream
          | :protocol_control
          | :idle_data

  @type packet_service :: :map | :virtual_channel

  @type t :: %__MODULE__{
          physical_channel: binary(),
          frame_type: frame_type(),
          frame_size: pos_integer(),
          scid: 0..65_535,
          vcid: 0..63,
          map_id: 0..15,
          valid_scids: [0..65_535],
          valid_vcids: [0..63],
          valid_map_ids: [0..15],
          source_destination: source_destination(),
          insert_zone_length: non_neg_integer(),
          fecf?: boolean(),
          maximum_frames_per_coding_unit: pos_integer(),
          maximum_repetitions: non_neg_integer(),
          ocf?: boolean(),
          sequence_count_octets: 0..7,
          expedited_count_octets: 0..7,
          cop: cop(),
          clcw_version: 1,
          clcw_reporting_rate: pos_integer() | nil,
          sequence_repetitions: non_neg_integer(),
          protocol_control_repetitions: non_neg_integer(),
          maximum_tfdf_delay_ms: non_neg_integer(),
          maximum_frame_release_delay_ms: non_neg_integer(),
          data_field_content: data_field_content(),
          packet_service: packet_service() | nil,
          upid: 0..31,
          truncated_frame_length: 6..32 | nil,
          packet_configuration: PacketConfiguration.t() | nil
        }

  defstruct physical_channel: "default",
            frame_type: :variable,
            frame_size: nil,
            scid: nil,
            vcid: nil,
            map_id: 0,
            valid_scids: [],
            valid_vcids: [],
            valid_map_ids: [],
            source_destination: :source,
            insert_zone_length: 0,
            fecf?: false,
            maximum_frames_per_coding_unit: 1,
            maximum_repetitions: 0,
            ocf?: false,
            sequence_count_octets: 1,
            expedited_count_octets: 1,
            cop: :none,
            clcw_version: 1,
            clcw_reporting_rate: nil,
            sequence_repetitions: 0,
            protocol_control_repetitions: 0,
            maximum_tfdf_delay_ms: 0,
            maximum_frame_release_delay_ms: 0,
            data_field_content: :packets,
            packet_service: :map,
            upid: TFDF.upid(:packets),
            truncated_frame_length: nil,
            packet_configuration: %PacketConfiguration{}

  @known_fields [
    :physical_channel,
    :frame_type,
    :frame_size,
    :scid,
    :vcid,
    :map_id,
    :valid_scids,
    :valid_vcids,
    :valid_map_ids,
    :source_destination,
    :insert_zone_length,
    :fecf?,
    :maximum_frames_per_coding_unit,
    :maximum_repetitions,
    :ocf?,
    :sequence_count_octets,
    :expedited_count_octets,
    :cop,
    :clcw_version,
    :clcw_reporting_rate,
    :sequence_repetitions,
    :protocol_control_repetitions,
    :maximum_tfdf_delay_ms,
    :maximum_frame_release_delay_ms,
    :data_field_content,
    :packet_service,
    :upid,
    :truncated_frame_length,
    :packet_configuration
  ]
  @contents [:packets, :mapa_sdu, :vca_sdu, :octet_stream, :protocol_control, :idle_data]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> normalize_packet_configuration()

    case Map.keys(attrs) -- @known_fields do
      [] ->
        configuration =
          __MODULE__
          |> struct(attrs)
          |> normalize_content_defaults(attrs)
          |> fill_address_sets()

        case validate(configuration) do
          :ok -> {:ok, configuration}
          {:error, _reason} = error -> error
        end

      _unknown ->
        {:error, :unknown_uslp_configuration_attribute}
    end
  end

  def new(value), do: {:error, {:invalid_uslp_configuration, value}}

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, configuration} -> configuration
      {:error, reason} -> raise ArgumentError, "invalid USLP configuration: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <- validate_non_empty_binary(configuration.physical_channel, :physical_channel),
         :ok <- validate_member(configuration.frame_type, [:fixed, :variable], :frame_type),
         :ok <- validate_range(configuration.frame_size, 6, 65_536, :frame_size),
         :ok <- validate_range(configuration.scid, 0, 65_535, :scid),
         :ok <- validate_range(configuration.vcid, 0, 63, :vcid),
         :ok <- validate_range(configuration.map_id, 0, 15, :map_id),
         :ok <- validate_set(configuration.valid_scids, 0, 65_535, :valid_scids),
         :ok <- validate_set(configuration.valid_vcids, 0, 63, :valid_vcids),
         :ok <- validate_set(configuration.valid_map_ids, 0, 15, :valid_map_ids),
         :ok <- validate_member(configuration.scid, configuration.valid_scids, :valid_scids),
         :ok <- validate_member(configuration.vcid, configuration.valid_vcids, :valid_vcids),
         :ok <- validate_member(configuration.map_id, configuration.valid_map_ids, :valid_map_ids),
         :ok <-
           validate_member(
             configuration.source_destination,
             [:source, :destination],
             :source_destination
           ),
         :ok <- validate_non_negative(configuration.insert_zone_length, :insert_zone_length),
         :ok <- validate_boolean(configuration.fecf?, :fecf?),
         :ok <-
           validate_positive(
             configuration.maximum_frames_per_coding_unit,
             :maximum_frames_per_coding_unit
           ),
         :ok <- validate_non_negative(configuration.maximum_repetitions, :maximum_repetitions),
         :ok <- validate_boolean(configuration.ocf?, :ocf?),
         :ok <- validate_range(configuration.sequence_count_octets, 0, 7, :sequence_count_octets),
         :ok <-
           validate_range(configuration.expedited_count_octets, 0, 7, :expedited_count_octets),
         :ok <- validate_member(configuration.cop, [:none, :cop1, :copp], :cop),
         :ok <- validate_range(configuration.clcw_version, 1, 1, :clcw_version),
         :ok <-
           validate_optional_positive(configuration.clcw_reporting_rate, :clcw_reporting_rate),
         :ok <- validate_non_negative(configuration.sequence_repetitions, :sequence_repetitions),
         :ok <-
           validate_non_negative(
             configuration.protocol_control_repetitions,
             :protocol_control_repetitions
           ),
         :ok <- validate_repetition_limits(configuration),
         :ok <- validate_non_negative(configuration.maximum_tfdf_delay_ms, :maximum_tfdf_delay_ms),
         :ok <-
           validate_non_negative(
             configuration.maximum_frame_release_delay_ms,
             :maximum_frame_release_delay_ms
           ),
         :ok <- validate_member(configuration.data_field_content, @contents, :data_field_content),
         :ok <- validate_range(configuration.upid, 0, 31, :upid),
         :ok <- validate_frame_type_constraints(configuration),
         :ok <- validate_content(configuration),
         :ok <- validate_idle_channel(configuration),
         :ok <- validate_truncated(configuration) do
      validate_frame_capacity(configuration)
    end
  end

  def validate(value), do: {:error, {:invalid_uslp_configuration, value}}

  @spec validate_plan([t()]) :: :ok | {:error, term()}
  def validate_plan(configurations) when is_list(configurations) and configurations != [] do
    with :ok <- validate_configurations(configurations),
         :ok <- validate_unique_addresses(configurations),
         :ok <- validate_physical_channels(configurations),
         :ok <- validate_master_channels(configurations) do
      validate_virtual_channels(configurations)
    end
  end

  def validate_plan(value), do: {:error, {:invalid_uslp_configuration_plan, value}}

  @spec address(t()) :: {0..65_535, 0..63, 0..15}
  def address(%__MODULE__{} = configuration),
    do: {configuration.scid, configuration.vcid, configuration.map_id}

  @spec physical_address(t()) :: {binary(), 0..65_535, 0..63, 0..15}
  def physical_address(%__MODULE__{} = configuration),
    do:
      {configuration.physical_channel, configuration.scid, configuration.vcid,
       configuration.map_id}

  @spec count_octets(t(), qos()) :: 0..7
  def count_octets(%__MODULE__{} = configuration, :sequence_controlled),
    do: configuration.sequence_count_octets

  def count_octets(%__MODULE__{} = configuration, :expedited),
    do: configuration.expedited_count_octets

  @spec primary_header_octets(t(), qos()) :: 7..14
  def primary_header_octets(configuration, qos), do: 7 + count_octets(configuration, qos)

  @spec tfdf_header_octets(t()) :: 1 | 3
  def tfdf_header_octets(%__MODULE__{frame_type: :fixed}), do: 3
  def tfdf_header_octets(%__MODULE__{frame_type: :variable}), do: 1

  @spec maximum_tfdz_octets(t(), qos()) :: pos_integer()
  def maximum_tfdz_octets(configuration, qos) do
    configuration.frame_size - primary_header_octets(configuration, qos) -
      configuration.insert_zone_length - tfdf_header_octets(configuration) -
      if(configuration.ocf?, do: 4, else: 0) - if(configuration.fecf?, do: 2, else: 0)
  end

  @spec codec_options(t()) :: keyword()
  def codec_options(configuration), do: [configuration: configuration]

  defp normalize_packet_configuration(%{packet_configuration: %PacketConfiguration{}} = attrs),
    do: attrs

  defp normalize_packet_configuration(%{packet_configuration: attrs} = configuration)
       when is_map(attrs) or is_list(attrs) do
    %{configuration | packet_configuration: struct(PacketConfiguration, Map.new(attrs))}
  end

  defp normalize_packet_configuration(attrs), do: attrs

  defp normalize_content_defaults(configuration, attrs) do
    case configuration.data_field_content do
      :packets -> configuration
      :mapa_sdu -> defaults(configuration, attrs, nil, TFDF.upid(:mission_specific), nil)
      :vca_sdu -> defaults(configuration, attrs, nil, TFDF.upid(:mission_specific), nil)
      :octet_stream -> defaults(configuration, attrs, nil, TFDF.upid(:octet_stream), nil)
      :protocol_control -> defaults(configuration, attrs, nil, protocol_upid(configuration), nil)
      :idle_data -> defaults(configuration, attrs, nil, TFDF.upid(:only_idle), nil)
    end
  end

  defp defaults(configuration, attrs, packet_service, upid, packet_configuration) do
    configuration
    |> maybe_default(attrs, :packet_service, packet_service)
    |> maybe_default(attrs, :upid, upid)
    |> maybe_default(attrs, :packet_configuration, packet_configuration)
  end

  defp protocol_upid(%__MODULE__{cop: :copp}), do: TFDF.upid(:copp)
  defp protocol_upid(_configuration), do: TFDF.upid(:cop1)

  defp maybe_default(configuration, attrs, field, value) do
    if Map.has_key?(attrs, field), do: configuration, else: Map.put(configuration, field, value)
  end

  defp fill_address_sets(configuration) do
    configuration
    |> maybe_fill(:valid_scids, configuration.scid)
    |> maybe_fill(:valid_vcids, [configuration.vcid, 63] |> Enum.reject(&is_nil/1) |> Enum.uniq())
    |> maybe_fill(:valid_map_ids, configuration.map_id)
  end

  defp maybe_fill(configuration, field, value) do
    if Map.fetch!(configuration, field) == [],
      do: Map.put(configuration, field, List.wrap(value)),
      else: configuration
  end

  defp validate_frame_type_constraints(%__MODULE__{frame_type: :variable, insert_zone_length: 0}),
    do: :ok

  defp validate_frame_type_constraints(%__MODULE__{frame_type: :variable}),
    do: {:error, :variable_length_uslp_forbids_insert_zone}

  defp validate_frame_type_constraints(%__MODULE__{}), do: :ok

  defp validate_content(%__MODULE__{data_field_content: :packets} = configuration) do
    with :ok <-
           validate_member(
             configuration.packet_service,
             [:map, :virtual_channel],
             :packet_service
           ),
         true <- match?(%PacketConfiguration{}, configuration.packet_configuration),
         :ok <- PacketConfiguration.validate(configuration.packet_configuration) do
      if configuration.upid == TFDF.upid(:packets),
        do: :ok,
        else: {:error, {:invalid_packet_upid, configuration.upid}}
    else
      false -> {:error, {:invalid_packet_configuration, configuration.packet_configuration}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_content(%__MODULE__{data_field_content: :mapa_sdu} = configuration) do
    validate_non_packet_content(configuration, [TFDF.upid(:mission_specific)])
  end

  defp validate_content(%__MODULE__{data_field_content: :vca_sdu} = configuration) do
    validate_non_packet_content(configuration, [TFDF.upid(:mission_specific)])
  end

  defp validate_content(%__MODULE__{data_field_content: :octet_stream} = configuration) do
    with :ok <- validate_non_packet_content(configuration, [TFDF.upid(:octet_stream)]) do
      if configuration.frame_type == :variable,
        do: :ok,
        else: {:error, :octet_stream_requires_variable_length_frames}
    end
  end

  defp validate_content(%__MODULE__{data_field_content: :protocol_control} = configuration) do
    validate_non_packet_content(configuration, [
      TFDF.upid(:cop1),
      TFDF.upid(:copp),
      TFDF.upid(:sdls)
    ])
  end

  defp validate_content(%__MODULE__{data_field_content: :idle_data} = configuration) do
    validate_non_packet_content(configuration, [TFDF.upid(:only_idle)])
  end

  defp validate_non_packet_content(configuration, allowed_upids) do
    cond do
      not is_nil(configuration.packet_service) ->
        {:error, {:unexpected_packet_service, configuration.packet_service}}

      not is_nil(configuration.packet_configuration) ->
        {:error, {:unexpected_packet_configuration, configuration.packet_configuration}}

      configuration.upid not in allowed_upids ->
        {:error,
         {:invalid_upid_for_content, configuration.data_field_content, configuration.upid}}

      true ->
        :ok
    end
  end

  defp validate_idle_channel(%__MODULE__{
         vcid: 63,
         map_id: 0,
         data_field_content: :idle_data,
         frame_type: :fixed,
         ocf?: false
       }),
       do: :ok

  defp validate_idle_channel(%__MODULE__{vcid: 63}),
    do: {:error, :idle_vcid_requires_fixed_only_idle_data}

  defp validate_idle_channel(%__MODULE__{data_field_content: :idle_data}),
    do: {:error, :idle_data_requires_vcid_63}

  defp validate_idle_channel(%__MODULE__{}), do: :ok

  defp validate_truncated(%__MODULE__{truncated_frame_length: nil}), do: :ok

  defp validate_truncated(%__MODULE__{} = configuration) do
    with :ok <-
           validate_range(configuration.truncated_frame_length, 6, 32, :truncated_frame_length),
         true <- configuration.frame_type == :variable,
         true <- configuration.data_field_content == :mapa_sdu,
         true <- configuration.upid == TFDF.upid(:mission_specific) do
      :ok
    else
      false -> {:error, :invalid_truncated_uslp_configuration}
      {:error, _reason} = error -> error
    end
  end

  defp validate_frame_capacity(configuration) do
    maximum_primary_header =
      7 + max(configuration.sequence_count_octets, configuration.expedited_count_octets)

    minimum =
      maximum_primary_header +
        configuration.insert_zone_length + tfdf_header_octets(configuration) + 1 +
        if(configuration.ocf?, do: 4, else: 0) + if(configuration.fecf?, do: 2, else: 0)

    if configuration.frame_size >= minimum,
      do: :ok,
      else: {:error, {:frame_size_too_small, configuration.frame_size, minimum}}
  end

  defp validate_configurations(configurations) do
    Enum.reduce_while(configurations, :ok, fn
      %__MODULE__{} = configuration, :ok ->
        case validate(configuration) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, {physical_address(configuration), reason}}}
        end

      value, :ok ->
        {:halt, {:error, {:invalid_uslp_configuration, value}}}
    end)
  end

  defp validate_unique_addresses(configurations) do
    duplicate =
      configurations
      |> Enum.group_by(&physical_address/1)
      |> Enum.find(fn {_address, instances} -> length(instances) > 1 end)

    if duplicate,
      do: {:error, {:duplicate_uslp_channel, elem(duplicate, 0)}},
      else: :ok
  end

  defp validate_physical_channels(configurations) do
    validate_group_settings(configurations, & &1.physical_channel, [
      :frame_type,
      :frame_size,
      :insert_zone_length,
      :fecf?,
      :maximum_frames_per_coding_unit,
      :maximum_repetitions,
      :valid_scids
    ])
  end

  defp validate_master_channels(configurations) do
    configurations
    |> Enum.group_by(&{&1.physical_channel, &1.scid})
    |> Enum.reduce_while(:ok, fn {address, instances}, :ok ->
      fields =
        if hd(instances).frame_type == :fixed,
          do: [:valid_vcids, :ocf?],
          else: [:valid_vcids]

      case same_settings(instances, fields) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {address, reason}}}
      end
    end)
  end

  defp validate_virtual_channels(configurations) do
    configurations
    |> Enum.group_by(&{&1.physical_channel, &1.scid, &1.vcid})
    |> Enum.reduce_while(:ok, fn {address, instances}, :ok ->
      with :ok <-
             same_settings(instances, [
               :frame_type,
               :sequence_count_octets,
               :expedited_count_octets,
               :cop,
               :clcw_version,
               :clcw_reporting_rate,
               :sequence_repetitions,
               :protocol_control_repetitions,
               :maximum_tfdf_delay_ms,
               :maximum_frame_release_delay_ms,
               :valid_map_ids
             ]),
           :ok <- validate_vc_service_exclusivity(instances) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {address, reason}}}
      end
    end)
  end

  defp validate_vc_service_exclusivity(instances) do
    contents = instances |> Enum.map(& &1.data_field_content) |> Enum.uniq()

    cond do
      :vca_sdu in contents and length(instances) > 1 ->
        {:error, :vca_service_requires_exclusive_virtual_channel}

      Enum.any?(
        instances,
        &(&1.data_field_content == :packets and &1.packet_service == :virtual_channel)
      ) and length(instances) > 1 ->
        {:error, :vc_packet_service_requires_exclusive_virtual_channel}

      true ->
        :ok
    end
  end

  defp validate_group_settings(configurations, grouper, fields) do
    configurations
    |> Enum.group_by(grouper)
    |> Enum.reduce_while(:ok, fn {address, instances}, :ok ->
      case same_settings(instances, fields) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {address, reason}}}
      end
    end)
  end

  defp same_settings(instances, fields) do
    case Enum.find(fields, fn field ->
           instances |> Enum.map(&Map.fetch!(&1, field)) |> Enum.uniq() |> length() > 1
         end) do
      nil -> :ok
      field -> {:error, {:inconsistent_managed_parameter, field}}
    end
  end

  defp validate_non_empty_binary(value, _field) when is_binary(value) and byte_size(value) > 0,
    do: :ok

  defp validate_non_empty_binary(value, field), do: {:error, {:invalid_field, field, value}}
  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}
  defp validate_non_negative(value, _field) when is_integer(value) and value >= 0, do: :ok
  defp validate_non_negative(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_optional_positive(nil, _field), do: :ok
  defp validate_optional_positive(value, field), do: validate_positive(value, field)

  defp validate_repetition_limits(configuration) do
    maximum = configuration.maximum_repetitions

    if configuration.sequence_repetitions <= maximum and
         configuration.protocol_control_repetitions <= maximum,
       do: :ok,
       else:
         {:error,
          {:repetitions_exceed_physical_maximum, configuration.sequence_repetitions,
           configuration.protocol_control_repetitions, maximum}}
  end

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}

  defp validate_member(value, values, field) when is_list(values) do
    if value in values, do: :ok, else: {:error, {:invalid_field, field, value}}
  end

  defp validate_set(values, minimum, maximum, _field) when is_list(values) and values != [] do
    cond do
      Enum.any?(values, &(!is_integer(&1) or &1 < minimum or &1 > maximum)) ->
        {:error, :invalid_set_member}

      length(values) != length(Enum.uniq(values)) ->
        {:error, :duplicate_set_member}

      true ->
        :ok
    end
  end

  defp validate_set(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}
end
