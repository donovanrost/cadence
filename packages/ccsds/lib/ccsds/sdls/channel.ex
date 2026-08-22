defmodule CCSDS.SDLS.Channel do
  @moduledoc """
  Managed SDLS service-access address.

  A channel without a MAP ID represents a GVCID. A TC or USLP channel with a
  MAP ID represents a GMAP ID. The physical-channel name keeps SPI uniqueness
  scoped to the link on which the value is transmitted.
  """

  @type protocol :: :tm | :tc | :aos | :uslp
  @type t :: %__MODULE__{
          physical_channel: binary(),
          protocol: protocol(),
          transfer_frame_version: 0..15,
          scid: 0..65_535,
          vcid: 0..63,
          map_id: 0..63 | nil,
          only_idle_data?: boolean(),
          cop_in_use?: boolean()
        }

  defstruct physical_channel: nil,
            protocol: nil,
            transfer_frame_version: nil,
            scid: nil,
            vcid: nil,
            map_id: nil,
            only_idle_data?: false,
            cop_in_use?: false

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    known_fields = Map.keys(Map.from_struct(%__MODULE__{}))

    with [] <- Map.keys(attrs) -- known_fields,
         channel = struct(__MODULE__, attrs),
         :ok <- validate(channel) do
      {:ok, channel}
    else
      [_unknown | _rest] -> {:error, :unknown_sdls_channel_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, channel} -> channel
      {:error, reason} -> raise ArgumentError, "invalid SDLS channel: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = channel) do
    with :ok <- validate_physical_channel(channel.physical_channel),
         :ok <- validate_member(channel.protocol, [:tm, :tc, :aos, :uslp], :protocol),
         :ok <- validate_version(channel.transfer_frame_version, channel.protocol),
         :ok <- validate_scid(channel.scid, channel.protocol),
         :ok <- validate_vcid(channel.vcid, channel.protocol),
         :ok <- validate_map_id(channel.map_id, channel.protocol),
         :ok <- validate_boolean(channel.only_idle_data?, :only_idle_data?),
         :ok <- validate_boolean(channel.cop_in_use?, :cop_in_use?),
         :ok <- validate_cop_use(channel) do
      validate_only_idle_data(channel)
    end
  end

  def validate(value), do: {:error, {:invalid_sdls_channel, value}}

  @spec key(t()) :: tuple()
  def key(%__MODULE__{} = channel) do
    {
      channel.physical_channel,
      channel.protocol,
      channel.transfer_frame_version,
      channel.scid,
      channel.vcid,
      channel.map_id
    }
  end

  defp validate_scid(value, :uslp), do: validate_range(value, 0, 65_535, :scid)
  defp validate_scid(value, _protocol), do: validate_range(value, 0, 1023, :scid)

  defp validate_version(0, protocol) when protocol in [:tm, :tc], do: :ok
  defp validate_version(1, :aos), do: :ok
  defp validate_version(12, :uslp), do: :ok

  defp validate_version(value, protocol),
    do: {:error, {:invalid_transfer_frame_version, protocol, value}}

  defp validate_vcid(value, :tm), do: validate_range(value, 0, 7, :vcid)
  defp validate_vcid(value, _protocol), do: validate_range(value, 0, 63, :vcid)

  defp validate_map_id(nil, _protocol), do: :ok
  defp validate_map_id(value, :tc), do: validate_range(value, 0, 63, :map_id)
  defp validate_map_id(value, :uslp), do: validate_range(value, 0, 15, :map_id)
  defp validate_map_id(value, _protocol), do: {:error, {:invalid_field, :map_id, value}}

  defp validate_cop_use(%__MODULE__{cop_in_use?: true, protocol: protocol})
       when protocol != :uslp,
       do: {:error, {:cop_in_use_not_applicable, protocol}}

  defp validate_cop_use(_channel), do: :ok

  defp validate_only_idle_data(%__MODULE__{only_idle_data?: true}),
    do: {:error, :sdls_forbidden_on_only_idle_data}

  defp validate_only_idle_data(%__MODULE__{protocol: protocol, vcid: 63})
       when protocol in [:aos, :uslp],
       do: {:error, :sdls_forbidden_on_only_idle_data}

  defp validate_only_idle_data(_channel), do: :ok

  defp validate_physical_channel(value) when is_binary(value) and byte_size(value) > 0, do: :ok
  defp validate_physical_channel(value), do: {:error, {:invalid_field, :physical_channel, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_member(value, allowed, field) do
    if value in allowed, do: :ok, else: {:error, {:invalid_field, field, value}}
  end

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}
end
