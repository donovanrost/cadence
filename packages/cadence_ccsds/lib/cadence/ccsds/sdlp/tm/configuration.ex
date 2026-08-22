defmodule Cadence.CCSDS.SDLP.TM.Configuration do
  @moduledoc """
  Managed parameters for one TM Virtual Channel.

  TM Transfer Frames do not carry their fixed frame length, FECF presence,
  secondary-header association, or channel content type on the wire. This
  value makes those mission-managed facts explicit and validates them before
  the frame codec, segmentation, or reassembly kernels are used.
  """

  alias Cadence.CCSDS.FrameErrorControl

  @type data_field_content :: :packets | :vca_sdu
  @type field_source :: :none | :virtual_channel | :master_channel

  @type t :: %__MODULE__{
          physical_channel: binary(),
          frame_size: pos_integer(),
          scid: 0..1023,
          vcid: 0..7,
          valid_scids: [0..1023],
          valid_vcids: [0..7],
          fecf?: boolean(),
          data_field_content: data_field_content(),
          secondary_header_source: field_source(),
          secondary_header_length: 0 | 2..64,
          ocf_source: field_source(),
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
            fecf?: false,
            data_field_content: :packets,
            secondary_header_source: :none,
            secondary_header_length: 0,
            ocf_source: :none,
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
    :fecf?,
    :data_field_content,
    :secondary_header_source,
    :secondary_header_length,
    :ocf_source,
    :valid_packet_version_numbers,
    :maximum_packet_octets,
    :deliver_incomplete_packets?
  ]
  @field_sources [:none, :virtual_channel, :master_channel]
  @primary_header_octets 6
  @ocf_octets 4

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    case Map.keys(attrs) -- @known_fields do
      [] ->
        configuration =
          __MODULE__
          |> struct(attrs)
          |> fill_address_sets()

        case validate(configuration) do
          :ok -> {:ok, configuration}
          {:error, _reason} = error -> error
        end

      _unknown ->
        {:error, :unknown_tm_configuration_attribute}
    end
  end

  def new(value), do: {:error, {:invalid_tm_configuration, value}}

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <- validate_non_empty_binary(configuration.physical_channel, :physical_channel),
         :ok <- validate_range(configuration.scid, 0, 1023, :scid),
         :ok <- validate_range(configuration.vcid, 0, 7, :vcid),
         :ok <- validate_set(configuration.valid_scids, 0, 1023, :valid_scids),
         :ok <- validate_set(configuration.valid_vcids, 0, 7, :valid_vcids),
         :ok <- validate_member(configuration.scid, configuration.valid_scids, :valid_scids),
         :ok <- validate_member(configuration.vcid, configuration.valid_vcids, :valid_vcids),
         :ok <- validate_boolean(configuration.fecf?, :fecf?),
         :ok <-
           validate_member(
             configuration.data_field_content,
             [:packets, :vca_sdu],
             :data_field_content
           ),
         :ok <-
           validate_member(
             configuration.secondary_header_source,
             @field_sources,
             :secondary_header_source
           ),
         :ok <- validate_secondary_header(configuration),
         :ok <- validate_member(configuration.ocf_source, @field_sources, :ocf_source),
         :ok <-
           validate_boolean(
             configuration.deliver_incomplete_packets?,
             :deliver_incomplete_packets?
           ),
         :ok <- validate_data_field_capacity(configuration) do
      validate_content_parameters(configuration)
    end
  end

  @spec validate_plan([t()]) :: :ok | {:error, term()}
  def validate_plan(configurations) when is_list(configurations) and configurations != [] do
    with :ok <- validate_configurations(configurations),
         :ok <- validate_unique_addresses(configurations),
         :ok <- validate_physical_channels(configurations) do
      validate_master_channels(configurations)
    end
  end

  def validate_plan(value), do: {:error, {:invalid_tm_configuration_plan, value}}

  @spec maximum_data_field_octets(t()) :: pos_integer()
  def maximum_data_field_octets(%__MODULE__{} = configuration) do
    configuration.frame_size - @primary_header_octets - configuration.secondary_header_length -
      ocf_octets(configuration) - fecf_octets(configuration)
  end

  @spec secondary_header?(t()) :: boolean()
  def secondary_header?(%__MODULE__{secondary_header_source: source}), do: source != :none

  @spec ocf?(t()) :: boolean()
  def ocf?(%__MODULE__{ocf_source: source}), do: source != :none

  @spec address(t()) :: {0..1023, 0..7}
  def address(%__MODULE__{scid: scid, vcid: vcid}), do: {scid, vcid}

  @spec codec_options(t()) :: keyword()
  def codec_options(%__MODULE__{} = configuration), do: [configuration: configuration]

  @spec matches?(t(), 0..1023, 0..7) :: boolean()
  def matches?(%__MODULE__{} = configuration, scid, vcid) do
    configuration.scid == scid and configuration.vcid == vcid
  end

  defp fill_address_sets(configuration) do
    configuration
    |> maybe_fill(:valid_scids, configuration.scid)
    |> maybe_fill(:valid_vcids, configuration.vcid)
  end

  defp validate_configurations(configurations) do
    Enum.reduce_while(configurations, :ok, fn
      %__MODULE__{} = configuration, :ok ->
        case validate(configuration) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, {address(configuration), reason}}}
        end

      value, :ok ->
        {:halt, {:error, {:invalid_tm_configuration, value}}}
    end)
  end

  defp validate_unique_addresses(configurations) do
    duplicate =
      configurations
      |> Enum.group_by(&{&1.physical_channel, &1.scid, &1.vcid})
      |> Enum.find(fn {_address, instances} -> length(instances) > 1 end)

    case duplicate do
      nil -> :ok
      {address, _instances} -> {:error, {:duplicate_tm_channel, address}}
    end
  end

  defp validate_physical_channels(configurations) do
    configurations
    |> Enum.group_by(& &1.physical_channel)
    |> Enum.reduce_while(:ok, fn {name, instances}, :ok ->
      settings =
        instances
        |> Enum.map(&{&1.frame_size, &1.fecf?, &1.valid_scids})
        |> Enum.uniq()

      case settings do
        [_one] -> {:cont, :ok}
        _many -> {:halt, {:error, {:inconsistent_physical_channel, name}}}
      end
    end)
  end

  defp validate_master_channels(configurations) do
    configurations
    |> Enum.group_by(&{&1.physical_channel, &1.scid})
    |> Enum.reduce_while(:ok, fn {master_address, instances}, :ok ->
      case validate_master_channel(instances) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {master_address, reason}}}
      end
    end)
  end

  defp validate_master_channel(instances) do
    with :ok <- same_setting(instances, :valid_vcids),
         :ok <-
           validate_master_field(instances, :secondary_header_source, :secondary_header_length) do
      validate_master_field(instances, :ocf_source, nil)
    end
  end

  defp same_setting(instances, field) do
    if instances |> Enum.map(&Map.fetch!(&1, field)) |> Enum.uniq() |> length() == 1,
      do: :ok,
      else: {:error, {:inconsistent_master_channel_setting, field}}
  end

  defp validate_master_field(instances, source_field, value_field) do
    master_instances =
      Enum.filter(instances, &(Map.fetch!(&1, source_field) == :master_channel))

    cond do
      master_instances == [] ->
        :ok

      length(master_instances) != length(instances) ->
        {:error, {:inconsistent_master_channel_field_source, source_field}}

      is_nil(value_field) ->
        :ok

      true ->
        same_setting(instances, value_field)
    end
  end

  defp maybe_fill(configuration, field, value) do
    case Map.fetch!(configuration, field) do
      [] -> Map.put(configuration, field, [value])
      _values -> configuration
    end
  end

  defp validate_secondary_header(%__MODULE__{
         secondary_header_source: :none,
         secondary_header_length: 0
       }),
       do: :ok

  defp validate_secondary_header(%__MODULE__{
         secondary_header_source: :none,
         secondary_header_length: length
       }),
       do: {:error, {:secondary_header_length_without_source, length}}

  defp validate_secondary_header(%__MODULE__{secondary_header_length: length})
       when length in 2..64,
       do: :ok

  defp validate_secondary_header(%__MODULE__{secondary_header_length: length}),
    do: {:error, {:invalid_secondary_header_length, length}}

  defp validate_data_field_capacity(%__MODULE__{frame_size: frame_size} = configuration)
       when is_integer(frame_size) do
    minimum =
      @primary_header_octets + configuration.secondary_header_length +
        ocf_octets(configuration) + fecf_octets(configuration) + 1

    if frame_size >= minimum do
      :ok
    else
      {:error, {:frame_size_too_small, frame_size, minimum}}
    end
  end

  defp validate_data_field_capacity(%__MODULE__{frame_size: frame_size}),
    do: {:error, {:invalid_frame_size, frame_size}}

  defp validate_content_parameters(%__MODULE__{data_field_content: :packets} = configuration) do
    with :ok <-
           validate_set(
             configuration.valid_packet_version_numbers,
             0,
             7,
             :valid_packet_version_numbers
           ) do
      validate_positive(configuration.maximum_packet_octets, :maximum_packet_octets)
    end
  end

  defp validate_content_parameters(%__MODULE__{data_field_content: :vca_sdu} = configuration) do
    with :ok <-
           validate_empty(
             configuration.valid_packet_version_numbers,
             :valid_packet_version_numbers
           ),
         :ok <- validate_nil(configuration.maximum_packet_octets, :maximum_packet_octets) do
      validate_false(configuration.deliver_incomplete_packets?, :deliver_incomplete_packets?)
    end
  end

  defp ocf_octets(configuration), do: if(ocf?(configuration), do: @ocf_octets, else: 0)
  defp fecf_octets(%__MODULE__{fecf?: true}), do: FrameErrorControl.size()
  defp fecf_octets(%__MODULE__{}), do: 0

  defp validate_non_empty_binary(value, _field) when is_binary(value) and byte_size(value) > 0,
    do: :ok

  defp validate_non_empty_binary(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}

  defp validate_set(values, minimum, maximum, field) when is_list(values) and values != [] do
    if values == Enum.uniq(values) and
         Enum.all?(values, &(is_integer(&1) and &1 >= minimum and &1 <= maximum)) do
      :ok
    else
      {:error, {:invalid_field, field, values}}
    end
  end

  defp validate_set(values, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, values}}

  defp validate_member(value, allowed, field) do
    if value in allowed, do: :ok, else: {:error, {:invalid_field, field, value}}
  end

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_empty([], _field), do: :ok
  defp validate_empty(value, field), do: {:error, {:field_must_be_empty, field, value}}

  defp validate_nil(nil, _field), do: :ok
  defp validate_nil(value, field), do: {:error, {:field_must_be_nil, field, value}}

  defp validate_false(false, _field), do: :ok
  defp validate_false(value, field), do: {:error, {:field_must_be_false, field, value}}
end
