defmodule Cadence.CCSDS.SDLP.AOS.Configuration do
  @moduledoc """
  Managed parameters for one AOS Virtual Channel.

  AOS frames have a fixed physical-channel length. Header protection, Insert
  Zone and FECF presence are physical-channel facts; OCF and data-field content
  are Virtual Channel facts. This value makes those off-wire facts explicit.
  """

  alias Cadence.CCSDS.FrameErrorControl

  @type data_field_content :: :m_pdu | :b_pdu | :vca_sdu | :idle_data

  @type t :: %__MODULE__{
          physical_channel: binary(),
          frame_size: pos_integer(),
          scid: 0..1023,
          vcid: 0..63,
          valid_scids: [0..1023],
          valid_vcids: [0..63],
          frame_header_error_control?: boolean(),
          insert_zone_length: non_neg_integer(),
          fecf?: boolean(),
          data_field_content: data_field_content(),
          ocf?: boolean(),
          valid_packet_version_numbers: [0..7],
          maximum_packet_octets: pos_integer() | nil,
          deliver_incomplete_packets?: boolean()
        }

  defstruct physical_channel: "default",
            frame_size: nil,
            scid: nil,
            vcid: nil,
            valid_scids: [],
            valid_vcids: [],
            frame_header_error_control?: false,
            insert_zone_length: 0,
            fecf?: false,
            data_field_content: :m_pdu,
            ocf?: false,
            valid_packet_version_numbers: [0],
            maximum_packet_octets: 65_542,
            deliver_incomplete_packets?: false

  @known_fields [
    :physical_channel,
    :frame_size,
    :scid,
    :vcid,
    :valid_scids,
    :valid_vcids,
    :frame_header_error_control?,
    :insert_zone_length,
    :fecf?,
    :data_field_content,
    :ocf?,
    :valid_packet_version_numbers,
    :maximum_packet_octets,
    :deliver_incomplete_packets?
  ]
  @contents [:m_pdu, :b_pdu, :vca_sdu, :idle_data]
  @base_primary_header_octets 6
  @header_error_control_octets 2
  @pdu_header_octets 2
  @ocf_octets 4

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

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
        {:error, :unknown_aos_configuration_attribute}
    end
  end

  def new(value), do: {:error, {:invalid_aos_configuration, value}}

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, configuration} -> configuration
      {:error, reason} -> raise ArgumentError, "invalid AOS configuration: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <- validate_non_empty_binary(configuration.physical_channel, :physical_channel),
         :ok <- validate_range(configuration.scid, 0, 1023, :scid),
         :ok <- validate_range(configuration.vcid, 0, 63, :vcid),
         :ok <- validate_set(configuration.valid_scids, 0, 1023, :valid_scids),
         :ok <- validate_set(configuration.valid_vcids, 0, 63, :valid_vcids),
         :ok <- validate_member(configuration.scid, configuration.valid_scids, :valid_scids),
         :ok <- validate_member(configuration.vcid, configuration.valid_vcids, :valid_vcids),
         :ok <- validate_member(63, configuration.valid_vcids, :valid_vcids),
         :ok <-
           validate_boolean(
             configuration.frame_header_error_control?,
             :frame_header_error_control?
           ),
         :ok <- validate_non_negative(configuration.insert_zone_length, :insert_zone_length),
         :ok <- validate_boolean(configuration.fecf?, :fecf?),
         :ok <- validate_member(configuration.data_field_content, @contents, :data_field_content),
         :ok <- validate_boolean(configuration.ocf?, :ocf?),
         :ok <-
           validate_boolean(
             configuration.deliver_incomplete_packets?,
             :deliver_incomplete_packets?
           ),
         :ok <- validate_idle_channel(configuration),
         :ok <- validate_frame_capacity(configuration) do
      validate_content_parameters(configuration)
    end
  end

  def validate(value), do: {:error, {:invalid_aos_configuration, value}}

  @spec validate_plan([t()]) :: :ok | {:error, term()}
  def validate_plan(configurations) when is_list(configurations) and configurations != [] do
    with :ok <- validate_configurations(configurations),
         :ok <- validate_unique_addresses(configurations),
         :ok <- validate_physical_channels(configurations) do
      validate_master_channels(configurations)
    end
  end

  def validate_plan(value), do: {:error, {:invalid_aos_configuration_plan, value}}

  @spec address(t()) :: {0..1023, 0..63}
  def address(%__MODULE__{scid: scid, vcid: vcid}), do: {scid, vcid}

  @spec physical_address(t()) :: {binary(), 0..1023, 0..63}
  def physical_address(%__MODULE__{} = configuration) do
    {configuration.physical_channel, configuration.scid, configuration.vcid}
  end

  @spec matches?(t(), 0..1023, 0..63) :: boolean()
  def matches?(%__MODULE__{} = configuration, scid, vcid) do
    configuration.scid == scid and configuration.vcid == vcid
  end

  @spec primary_header_octets(t()) :: 6 | 8
  def primary_header_octets(%__MODULE__{frame_header_error_control?: true}),
    do: @base_primary_header_octets + @header_error_control_octets

  def primary_header_octets(%__MODULE__{}), do: @base_primary_header_octets

  @spec data_field_octets(t()) :: pos_integer()
  def data_field_octets(%__MODULE__{} = configuration) do
    configuration.frame_size - primary_header_octets(configuration) -
      configuration.insert_zone_length - ocf_octets(configuration) - fecf_octets(configuration)
  end

  @spec payload_octets(t()) :: pos_integer()
  def payload_octets(%__MODULE__{data_field_content: content} = configuration)
      when content in [:m_pdu, :b_pdu],
      do: data_field_octets(configuration) - @pdu_header_octets

  def payload_octets(%__MODULE__{} = configuration), do: data_field_octets(configuration)

  @spec codec_options(t()) :: keyword()
  def codec_options(%__MODULE__{} = configuration), do: [configuration: configuration]

  defp fill_address_sets(configuration) do
    configuration
    |> maybe_fill(:valid_scids, configuration.scid)
    |> maybe_fill(:valid_vcids, [configuration.vcid, 63] |> Enum.reject(&is_nil/1) |> Enum.uniq())
  end

  defp normalize_content_defaults(configuration, attrs) do
    if configuration.data_field_content == :m_pdu do
      configuration
    else
      configuration
      |> maybe_default(attrs, :valid_packet_version_numbers, [])
      |> maybe_default(attrs, :maximum_packet_octets, nil)
    end
  end

  defp maybe_default(configuration, attrs, field, value) do
    if Map.has_key?(attrs, field), do: configuration, else: Map.put(configuration, field, value)
  end

  defp maybe_fill(configuration, field, value) do
    case Map.fetch!(configuration, field) do
      [] -> Map.put(configuration, field, List.wrap(value))
      _values -> configuration
    end
  end

  defp validate_idle_channel(%__MODULE__{vcid: 63, data_field_content: :idle_data, ocf?: false}),
    do: :ok

  defp validate_idle_channel(%__MODULE__{vcid: 63, data_field_content: :idle_data}),
    do: {:error, :idle_vcid_forbids_ocf}

  defp validate_idle_channel(%__MODULE__{vcid: 63}), do: {:error, :idle_vcid_requires_idle_data}

  defp validate_idle_channel(%__MODULE__{data_field_content: :idle_data}),
    do: {:error, :idle_data_requires_vcid_63}

  defp validate_idle_channel(%__MODULE__{}), do: :ok

  defp validate_frame_capacity(configuration) do
    overhead =
      primary_header_octets(configuration) + configuration.insert_zone_length +
        ocf_octets(configuration) + fecf_octets(configuration)

    minimum_data = if(configuration.data_field_content in [:m_pdu, :b_pdu], do: 3, else: 1)
    minimum = overhead + minimum_data

    if is_integer(configuration.frame_size) and configuration.frame_size >= minimum do
      :ok
    else
      {:error, {:frame_size_too_small, configuration.frame_size, minimum}}
    end
  end

  defp validate_content_parameters(%__MODULE__{data_field_content: :m_pdu} = configuration) do
    with :ok <-
           validate_set(
             configuration.valid_packet_version_numbers,
             0,
             7,
             :valid_packet_version_numbers
           ),
         :ok <- validate_positive(configuration.maximum_packet_octets, :maximum_packet_octets) do
      if configuration.maximum_packet_octets <= 65_542,
        do: :ok,
        else:
          {:error, {:invalid_field, :maximum_packet_octets, configuration.maximum_packet_octets}}
    end
  end

  defp validate_content_parameters(%__MODULE__{data_field_content: :b_pdu} = configuration) do
    if payload_octets(configuration) * 8 <= 16_384,
      do: validate_packet_parameters_absent(configuration),
      else: {:error, {:bitstream_data_zone_too_large, payload_octets(configuration) * 8}}
  end

  defp validate_content_parameters(configuration),
    do: validate_packet_parameters_absent(configuration)

  defp validate_packet_parameters_absent(%__MODULE__{} = configuration) do
    if configuration.valid_packet_version_numbers == [] and
         is_nil(configuration.maximum_packet_octets) do
      :ok
    else
      {:error, :packet_parameters_forbidden_for_non_packet_channel}
    end
  end

  defp validate_configurations(configurations) do
    Enum.reduce_while(configurations, :ok, fn
      %__MODULE__{} = configuration, :ok ->
        case validate(configuration) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, {address(configuration), reason}}}
        end

      value, :ok ->
        {:halt, {:error, {:invalid_aos_configuration, value}}}
    end)
  end

  defp validate_unique_addresses(configurations) do
    duplicate =
      configurations
      |> Enum.group_by(&{&1.physical_channel, &1.scid, &1.vcid})
      |> Enum.find(fn {_key, values} -> length(values) > 1 end)

    if duplicate, do: {:error, {:duplicate_aos_channel, elem(duplicate, 0)}}, else: :ok
  end

  defp validate_physical_channels(configurations) do
    configurations
    |> Enum.group_by(& &1.physical_channel)
    |> Enum.reduce_while(:ok, fn {name, instances}, :ok ->
      settings =
        instances
        |> Enum.map(
          &{&1.frame_size, &1.frame_header_error_control?, &1.insert_zone_length, &1.fecf?,
           &1.valid_scids}
        )
        |> Enum.uniq()

      if length(settings) == 1,
        do: {:cont, :ok},
        else: {:halt, {:error, {:inconsistent_aos_physical_channel, name}}}
    end)
  end

  defp validate_master_channels(configurations) do
    configurations
    |> Enum.group_by(&{&1.physical_channel, &1.scid})
    |> Enum.reduce_while(:ok, fn {master, instances}, :ok ->
      if instances |> Enum.map(& &1.valid_vcids) |> Enum.uniq() |> length() == 1,
        do: {:cont, :ok},
        else: {:halt, {:error, {:inconsistent_aos_master_channel, master}}}
    end)
  end

  defp ocf_octets(%__MODULE__{ocf?: true}), do: @ocf_octets
  defp ocf_octets(%__MODULE__{}), do: 0
  defp fecf_octets(%__MODULE__{fecf?: true}), do: FrameErrorControl.size()
  defp fecf_octets(%__MODULE__{}), do: 0

  defp validate_non_empty_binary(value, _field) when is_binary(value) and byte_size(value) > 0,
    do: :ok

  defp validate_non_empty_binary(value, field), do: {:error, {:invalid_field, field, value}}
  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}
  defp validate_non_negative(value, _field) when is_integer(value) and value >= 0, do: :ok
  defp validate_non_negative(value, field), do: {:error, {:invalid_field, field, value}}
  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}

  defp validate_set(values, minimum, maximum, _field)
       when is_list(values) and values != [] do
    if Enum.uniq(values) == values and
         Enum.all?(values, &(is_integer(&1) and &1 >= minimum and &1 <= maximum)),
       do: :ok,
       else: {:error, :invalid_set}
  end

  defp validate_set(values, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, values}}

  defp validate_member(value, values, _field) do
    if value in values, do: :ok, else: {:error, {:value_not_managed, value}}
  end
end
