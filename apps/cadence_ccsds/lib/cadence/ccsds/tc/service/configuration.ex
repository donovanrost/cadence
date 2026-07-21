defmodule Cadence.CCSDS.TC.Service.Configuration do
  @moduledoc """
  Managed parameters for one TC Space Data Link Protocol service instance.

  A configuration names the service at its standard SAP address. A plan is a
  list of configurations validated together so mutually exclusive services
  cannot be configured on the same Master, Virtual, or MAP Channel.
  """

  alias Cadence.CCSDS.FrameErrorControl
  alias Cadence.CCSDS.TC.Service.PacketConfiguration

  @type service ::
          :map_packet
          | :virtual_channel_packet
          | :map_access
          | :virtual_channel_access
          | :virtual_channel_frame
          | :master_channel_frame

  @type t :: %__MODULE__{
          service: service(),
          scid: 0..1023,
          vcid: 0..63 | nil,
          map_id: 0..63 | nil,
          valid_vcids: [0..63],
          frame_size: 6..1024,
          fecf?: boolean(),
          blocking?: boolean(),
          segmentation?: boolean(),
          maximum_sdu_octets: pos_integer() | nil,
          packet: PacketConfiguration.t() | nil,
          cop_management?: boolean(),
          repetitions_type_a: pos_integer(),
          repetitions_bc: pos_integer()
        }

  defstruct service: nil,
            scid: nil,
            vcid: nil,
            map_id: nil,
            valid_vcids: [],
            frame_size: 1024,
            fecf?: false,
            blocking?: false,
            segmentation?: false,
            maximum_sdu_octets: nil,
            packet: nil,
            cop_management?: true,
            repetitions_type_a: 1,
            repetitions_bc: 1

  @services [
    :map_packet,
    :virtual_channel_packet,
    :map_access,
    :virtual_channel_access,
    :virtual_channel_frame,
    :master_channel_frame
  ]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> normalize_packet()
    known_fields = Map.keys(Map.from_struct(%__MODULE__{}))

    with [] <- Map.keys(attrs) -- known_fields,
         configuration = struct(__MODULE__, attrs),
         :ok <- validate(configuration) do
      {:ok, configuration}
    else
      [_unknown | _rest] -> {:error, :unknown_tc_service_configuration_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <- validate_member(configuration.service, @services, :service),
         :ok <- validate_range(configuration.scid, 0, 1023, :scid),
         :ok <- validate_frame_size(configuration.frame_size, configuration.fecf?),
         :ok <- validate_boolean(configuration.fecf?, :fecf?),
         :ok <- validate_boolean(configuration.blocking?, :blocking?),
         :ok <- validate_boolean(configuration.segmentation?, :segmentation?),
         :ok <- validate_optional_positive(configuration.maximum_sdu_octets, :maximum_sdu_octets),
         :ok <- validate_boolean(configuration.cop_management?, :cop_management?),
         :ok <- validate_positive(configuration.repetitions_type_a, :repetitions_type_a),
         :ok <- validate_positive(configuration.repetitions_bc, :repetitions_bc) do
      validate_service_constraints(configuration)
    end
  end

  @spec validate_plan([t()]) :: :ok | {:error, term()}
  def validate_plan(configurations) when is_list(configurations) and configurations != [] do
    with :ok <- validate_configurations(configurations),
         :ok <- validate_unique_service_addresses(configurations),
         :ok <- validate_master_channel_exclusivity(configurations) do
      validate_virtual_channel_exclusivity(configurations)
    end
  end

  def validate_plan(value), do: {:error, {:invalid_service_plan, value}}

  @spec key(t()) :: {service(), 0..1023, 0..63 | nil, 0..63 | nil}
  def key(%__MODULE__{} = configuration) do
    {configuration.service, configuration.scid, configuration.vcid, configuration.map_id}
  end

  @spec virtual_channel_key(t()) :: {0..1023, 0..63} | nil
  def virtual_channel_key(%__MODULE__{vcid: nil}), do: nil
  def virtual_channel_key(%__MODULE__{scid: scid, vcid: vcid}), do: {scid, vcid}

  @spec segment_header?(t()) :: boolean()
  def segment_header?(%__MODULE__{service: service}) when service in [:map_packet, :map_access],
    do: true

  def segment_header?(%__MODULE__{}), do: false

  @spec maximum_data_field_octets(t()) :: pos_integer()
  def maximum_data_field_octets(%__MODULE__{} = configuration) do
    configuration.frame_size - 5 - segment_header_octets(configuration) -
      fecf_octets(configuration)
  end

  @spec packet_service?(t()) :: boolean()
  def packet_service?(%__MODULE__{service: service})
      when service in [:map_packet, :virtual_channel_packet],
      do: true

  def packet_service?(%__MODULE__{}), do: false

  @spec frame_service?(t()) :: boolean()
  def frame_service?(%__MODULE__{service: service})
      when service in [:virtual_channel_frame, :master_channel_frame],
      do: true

  def frame_service?(%__MODULE__{}), do: false

  defp normalize_packet(%{packet: %PacketConfiguration{}} = attrs), do: attrs

  defp normalize_packet(%{packet: packet_attrs} = attrs)
       when is_map(packet_attrs) or is_list(packet_attrs) do
    case PacketConfiguration.new(packet_attrs) do
      {:ok, packet} -> %{attrs | packet: packet}
      {:error, _reason} -> attrs
    end
  end

  defp normalize_packet(attrs), do: attrs

  defp validate_service_constraints(%__MODULE__{service: :map_packet} = configuration) do
    with :ok <- validate_vc_and_map(configuration),
         :ok <- validate_packet_configuration(configuration.packet),
         :ok <- validate_list_empty(configuration.valid_vcids, :valid_vcids),
         :ok <- validate_cop_management(configuration),
         :ok <- validate_sdu_limit(configuration) do
      validate_packet_segmentation(configuration)
    end
  end

  defp validate_service_constraints(%__MODULE__{service: :map_access} = configuration) do
    with :ok <- validate_vc_and_map(configuration),
         :ok <- validate_nil(configuration.packet, :packet),
         :ok <- validate_false(configuration.blocking?, :blocking?),
         :ok <- validate_list_empty(configuration.valid_vcids, :valid_vcids),
         :ok <- validate_cop_management(configuration) do
      validate_sdu_limit(configuration)
    end
  end

  defp validate_service_constraints(%__MODULE__{service: :virtual_channel_packet} = configuration) do
    with :ok <- validate_vc_without_map(configuration),
         :ok <- validate_packet_configuration(configuration.packet),
         :ok <- validate_false(configuration.segmentation?, :segmentation?),
         :ok <- validate_nil(configuration.maximum_sdu_octets, :maximum_sdu_octets),
         :ok <- validate_list_empty(configuration.valid_vcids, :valid_vcids) do
      validate_cop_management(configuration)
    end
  end

  defp validate_service_constraints(%__MODULE__{service: :virtual_channel_access} = configuration) do
    with :ok <- validate_vc_without_map(configuration),
         :ok <- validate_nil(configuration.packet, :packet),
         :ok <- validate_false(configuration.blocking?, :blocking?),
         :ok <- validate_false(configuration.segmentation?, :segmentation?),
         :ok <- validate_list_empty(configuration.valid_vcids, :valid_vcids),
         :ok <- validate_cop_management(configuration) do
      validate_sdu_limit(configuration)
    end
  end

  defp validate_service_constraints(%__MODULE__{service: :virtual_channel_frame} = configuration) do
    with :ok <- validate_vc_without_map(configuration),
         :ok <- validate_nil(configuration.packet, :packet),
         :ok <- validate_false(configuration.blocking?, :blocking?),
         :ok <- validate_false(configuration.segmentation?, :segmentation?),
         :ok <- validate_nil(configuration.maximum_sdu_octets, :maximum_sdu_octets),
         :ok <- validate_list_empty(configuration.valid_vcids, :valid_vcids) do
      validate_false(configuration.cop_management?, :cop_management?)
    end
  end

  defp validate_service_constraints(%__MODULE__{service: :master_channel_frame} = configuration) do
    with :ok <- validate_nil(configuration.vcid, :vcid),
         :ok <- validate_nil(configuration.map_id, :map_id),
         :ok <- validate_vcids(configuration.valid_vcids),
         :ok <- validate_nil(configuration.packet, :packet),
         :ok <- validate_false(configuration.blocking?, :blocking?),
         :ok <- validate_false(configuration.segmentation?, :segmentation?),
         :ok <- validate_nil(configuration.maximum_sdu_octets, :maximum_sdu_octets) do
      validate_false(configuration.cop_management?, :cop_management?)
    end
  end

  defp validate_vc_and_map(configuration) do
    with :ok <- validate_range(configuration.vcid, 0, 63, :vcid) do
      validate_range(configuration.map_id, 0, 63, :map_id)
    end
  end

  defp validate_vc_without_map(configuration) do
    with :ok <- validate_range(configuration.vcid, 0, 63, :vcid) do
      validate_nil(configuration.map_id, :map_id)
    end
  end

  defp validate_packet_segmentation(%__MODULE__{segmentation?: true}), do: :ok

  defp validate_packet_segmentation(%__MODULE__{} = configuration) do
    if configuration.packet.maximum_packet_octets <= maximum_data_field_octets(configuration) do
      :ok
    else
      {:error,
       {:packet_exceeds_unsegmented_map_capacity, configuration.packet.maximum_packet_octets,
        maximum_data_field_octets(configuration)}}
    end
  end

  defp validate_sdu_limit(%__MODULE__{maximum_sdu_octets: nil} = configuration) do
    if configuration.segmentation? do
      {:error, {:missing_field, :maximum_sdu_octets}}
    else
      :ok
    end
  end

  defp validate_sdu_limit(%__MODULE__{} = configuration) do
    if configuration.segmentation? or
         configuration.maximum_sdu_octets <= maximum_data_field_octets(configuration) do
      :ok
    else
      {:error,
       {:sdu_exceeds_unsegmented_capacity, configuration.maximum_sdu_octets,
        maximum_data_field_octets(configuration)}}
    end
  end

  defp validate_configurations(configurations) do
    Enum.reduce_while(configurations, :ok, fn
      %__MODULE__{} = configuration, :ok ->
        case validate(configuration) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, {key(configuration), reason}}}
        end

      value, :ok ->
        {:halt, {:error, {:invalid_service_configuration, value}}}
    end)
  end

  defp validate_unique_service_addresses(configurations) do
    duplicate =
      configurations
      |> Enum.group_by(&key/1)
      |> Enum.find(fn {_key, instances} -> length(instances) > 1 end)

    case duplicate do
      nil -> :ok
      {key, _instances} -> {:error, {:duplicate_service_address, key}}
    end
  end

  defp validate_master_channel_exclusivity(configurations) do
    master_frame_scids =
      for %{service: :master_channel_frame, scid: scid} <- configurations,
          into: MapSet.new(),
          do: scid

    conflict =
      Enum.find(configurations, fn configuration ->
        configuration.service != :master_channel_frame and
          MapSet.member?(master_frame_scids, configuration.scid)
      end)

    if conflict do
      {:error, {:master_channel_frame_service_conflict, conflict.scid}}
    else
      :ok
    end
  end

  defp validate_virtual_channel_exclusivity(configurations) do
    configurations
    |> Enum.reject(&is_nil(&1.vcid))
    |> Enum.group_by(&virtual_channel_key/1)
    |> Enum.reduce_while(:ok, fn {vc_key, instances}, :ok ->
      case validate_virtual_channel_instances(instances) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {vc_key, reason}}}
      end
    end)
  end

  defp validate_virtual_channel_instances(instances) do
    services = MapSet.new(instances, & &1.service)

    exclusive =
      MapSet.intersection(
        services,
        MapSet.new([:virtual_channel_packet, :virtual_channel_access, :virtual_channel_frame])
      )

    map_services = MapSet.intersection(services, MapSet.new([:map_packet, :map_access]))

    cond do
      MapSet.size(exclusive) > 1 ->
        {:error, {:mutually_exclusive_virtual_channel_services, MapSet.to_list(services)}}

      MapSet.size(exclusive) == 1 and MapSet.size(map_services) > 0 ->
        {:error, {:mutually_exclusive_virtual_channel_services, MapSet.to_list(services)}}

      true ->
        validate_unique_map_addresses(instances)
    end
  end

  defp validate_unique_map_addresses(instances) do
    duplicate =
      instances
      |> Enum.reject(&is_nil(&1.map_id))
      |> Enum.group_by(& &1.map_id)
      |> Enum.find(fn {_map_id, map_instances} -> length(map_instances) > 1 end)

    case duplicate do
      nil -> :ok
      {map_id, _instances} -> {:error, {:mutually_exclusive_map_services, map_id}}
    end
  end

  defp validate_frame_size(frame_size, fecf?) when is_boolean(fecf?) do
    minimum = 5 + if(fecf?, do: FrameErrorControl.size(), else: 0) + 1
    validate_range(frame_size, minimum, 1024, :frame_size)
  end

  defp validate_frame_size(frame_size, _fecf?),
    do: {:error, {:invalid_field, :frame_size, frame_size}}

  defp validate_packet_configuration(%PacketConfiguration{} = configuration),
    do: PacketConfiguration.validate(configuration)

  defp validate_packet_configuration(value), do: {:error, {:invalid_field, :packet, value}}

  defp validate_cop_management(%__MODULE__{cop_management?: true}), do: :ok
  defp validate_cop_management(%__MODULE__{}), do: {:error, {:cop_management_required, true}}

  defp validate_vcids(vcids) when is_list(vcids) and vcids != [] do
    cond do
      Enum.any?(vcids, &(!is_integer(&1) or &1 < 0 or &1 > 63)) ->
        {:error, {:invalid_field, :valid_vcids, vcids}}

      length(Enum.uniq(vcids)) != length(vcids) ->
        {:error, {:duplicate_vcid, vcids}}

      true ->
        :ok
    end
  end

  defp validate_vcids(value), do: {:error, {:invalid_field, :valid_vcids, value}}

  defp validate_list_empty([], _field), do: :ok
  defp validate_list_empty(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_nil(nil, _field), do: :ok
  defp validate_nil(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_false(false, _field), do: :ok
  defp validate_false(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_optional_positive(nil, _field), do: :ok
  defp validate_optional_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_optional_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_member(value, allowed, field) do
    if value in allowed, do: :ok, else: {:error, {:invalid_field, field, value}}
  end

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}

  defp segment_header_octets(configuration),
    do: if(segment_header?(configuration), do: 1, else: 0)

  defp fecf_octets(%__MODULE__{fecf?: true}), do: FrameErrorControl.size()
  defp fecf_octets(%__MODULE__{}), do: 0
end
