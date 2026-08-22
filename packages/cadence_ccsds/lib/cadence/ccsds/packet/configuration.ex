defmodule Cadence.CCSDS.Packet.Configuration do
  @moduledoc """
  Managed parameters shared by CCSDS Space Data Link Packet Services.

  Formats are keyed by Packet Version Number so blocked packets can be
  delimited without assuming every Packet Service user uses Space Packets.
  """

  alias Cadence.CCSDS.Packet.Format, as: PacketFormat

  @type extracted_packet :: %{
          octets: binary(),
          packet_version_number: 0..7,
          quality: :complete | :partial
        }

  @type t :: %__MODULE__{
          valid_packet_version_numbers: [0..7],
          maximum_packet_octets: pos_integer(),
          deliver_incomplete?: boolean(),
          formats: %{required(0..7) => PacketFormat.t()}
        }

  defstruct valid_packet_version_numbers: [0],
            maximum_packet_octets: 65_542,
            deliver_incomplete?: false,
            formats: %{0 => %PacketFormat{}}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> normalize_formats()
    known_fields = Map.keys(Map.from_struct(%__MODULE__{}))

    with [] <- Map.keys(attrs) -- known_fields,
         configuration = struct(__MODULE__, attrs),
         :ok <- validate(configuration) do
      {:ok, configuration}
    else
      [_unknown | _rest] -> {:error, :unknown_packet_configuration_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <- validate_pvns(configuration.valid_packet_version_numbers),
         :ok <- validate_positive(configuration.maximum_packet_octets, :maximum_packet_octets),
         :ok <- validate_boolean(configuration.deliver_incomplete?, :deliver_incomplete?),
         :ok <- validate_formats(configuration.formats) do
      validate_format_coverage(configuration)
    end
  end

  @spec validate_packet(binary(), 0..7, t()) :: :ok | {:error, term()}
  def validate_packet(packet, expected_pvn, %__MODULE__{} = configuration)
      when is_binary(packet) do
    with :ok <- validate(configuration),
         {:ok, actual_pvn} <- PacketFormat.packet_version_number(packet),
         :ok <- validate_expected_pvn(actual_pvn, expected_pvn),
         :ok <- validate_allowed_pvn(actual_pvn, configuration),
         :ok <- validate_packet_maximum(packet, configuration),
         {:ok, format} <- fetch_format(actual_pvn, configuration),
         {:ok, expected_octets} <- PacketFormat.total_packet_octets(packet, format) do
      validate_exact_length(packet, expected_octets)
    end
  end

  @spec extract(binary(), t()) :: {:ok, [extracted_packet()]} | {:error, term()}
  def extract(data, %__MODULE__{} = configuration) when is_binary(data) do
    with :ok <- validate(configuration) do
      do_extract(data, configuration, [])
    end
  end

  defp do_extract(<<>>, _configuration, acc), do: {:ok, Enum.reverse(acc)}

  defp do_extract(data, configuration, acc) do
    with {:ok, pvn} <- PacketFormat.packet_version_number(data),
         :ok <- validate_allowed_pvn(pvn, configuration),
         {:ok, format} <- fetch_format(pvn, configuration) do
      extract_next(data, pvn, format, configuration, acc)
    end
  end

  defp extract_next(data, pvn, format, configuration, acc) do
    case PacketFormat.total_packet_octets(data, format) do
      {:ok, packet_octets} when packet_octets > configuration.maximum_packet_octets ->
        {:error,
         {:packet_size_exceeds_managed_maximum, packet_octets,
          configuration.maximum_packet_octets}}

      {:ok, packet_octets} when byte_size(data) >= packet_octets ->
        <<packet::binary-size(^packet_octets), rest::binary>> = data
        extracted = %{octets: packet, packet_version_number: pvn, quality: :complete}
        do_extract(rest, configuration, [extracted | acc])

      {:ok, packet_octets} ->
        incomplete_packet(data, pvn, packet_octets, configuration, acc)

      {:error, {:truncated_packet_length_field, _required, _actual}} ->
        incomplete_packet(data, pvn, nil, configuration, acc)

      {:error, _reason} = error ->
        error
    end
  end

  defp incomplete_packet(data, pvn, _expected_octets, %{deliver_incomplete?: true}, acc) do
    extracted = %{octets: data, packet_version_number: pvn, quality: :partial}
    {:ok, Enum.reverse([extracted | acc])}
  end

  defp incomplete_packet(data, _pvn, expected_octets, _configuration, _acc) do
    {:error, {:incomplete_packet, expected_octets, byte_size(data)}}
  end

  defp normalize_formats(%{formats: formats} = attrs) when is_map(formats) do
    normalized =
      Map.new(formats, fn
        {pvn, %PacketFormat{} = format} -> {pvn, format}
        {pvn, format_attrs} -> {pvn, struct(PacketFormat, Map.new(format_attrs))}
      end)

    %{attrs | formats: normalized}
  end

  defp normalize_formats(attrs), do: attrs

  defp validate_pvns(pvns) when is_list(pvns) and pvns != [] do
    cond do
      Enum.any?(pvns, &(!is_integer(&1) or &1 < 0 or &1 > 7)) ->
        {:error, {:invalid_field, :valid_packet_version_numbers, pvns}}

      length(Enum.uniq(pvns)) != length(pvns) ->
        {:error, {:duplicate_packet_version_number, pvns}}

      true ->
        :ok
    end
  end

  defp validate_pvns(value), do: {:error, {:invalid_field, :valid_packet_version_numbers, value}}

  defp validate_formats(formats) when is_map(formats) and map_size(formats) > 0 do
    Enum.reduce_while(formats, :ok, fn
      {pvn, %PacketFormat{packet_version_number: pvn} = format}, :ok ->
        case PacketFormat.validate(format) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, {:invalid_packet_format, pvn, reason}}}
        end

      {pvn, %PacketFormat{packet_version_number: actual_pvn}}, :ok ->
        {:halt, {:error, {:packet_format_key_mismatch, pvn, actual_pvn}}}

      {pvn, value}, :ok ->
        {:halt, {:error, {:invalid_packet_format, pvn, value}}}
    end)
  end

  defp validate_formats(value), do: {:error, {:invalid_field, :formats, value}}

  defp validate_format_coverage(configuration) do
    missing = configuration.valid_packet_version_numbers -- Map.keys(configuration.formats)

    if missing == [], do: :ok, else: {:error, {:missing_packet_formats, missing}}
  end

  defp validate_expected_pvn(pvn, pvn), do: :ok

  defp validate_expected_pvn(actual, expected),
    do: {:error, {:packet_version_mismatch, actual, expected}}

  defp validate_allowed_pvn(pvn, configuration) do
    if pvn in configuration.valid_packet_version_numbers do
      :ok
    else
      {:error, {:unsupported_packet_version_number, pvn}}
    end
  end

  defp fetch_format(pvn, configuration) do
    case Map.fetch(configuration.formats, pvn) do
      {:ok, format} -> {:ok, format}
      :error -> {:error, {:missing_packet_format, pvn}}
    end
  end

  defp validate_packet_maximum(packet, configuration) do
    if byte_size(packet) <= configuration.maximum_packet_octets do
      :ok
    else
      {:error,
       {:packet_size_exceeds_managed_maximum, byte_size(packet),
        configuration.maximum_packet_octets}}
    end
  end

  defp validate_exact_length(packet, expected_octets) when byte_size(packet) == expected_octets,
    do: :ok

  defp validate_exact_length(packet, expected_octets),
    do: {:error, {:invalid_packet_length, byte_size(packet), expected_octets}}

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}
end
