defmodule CCSDS.Time.CDS.Codec do
  @moduledoc """
  Strict CDS P-field and T-field codec.

  Explicit P-fields are used by default. For an implicit P-field, pass
  `preamble: false` and the managed `configuration` when decoding.
  """

  alias CCSDS.Time.CDS
  alias CCSDS.Time.CDS.{Configuration, Preamble}

  @spec encode(CDS.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%CDS{} = value, opts \\ []) when is_list(opts) do
    with :ok <- CDS.validate(value),
         {:ok, preamble} <- encode_preamble(value.configuration, opts),
         {:ok, submilliseconds} <- encode_submilliseconds(value) do
      configuration = value.configuration

      {:ok,
       preamble <>
         <<value.day_count::unsigned-big-integer-size(configuration.day_octets * 8),
           value.milliseconds_of_day::32, submilliseconds::binary>>}
    end
  end

  @spec decode(binary(), keyword()) :: {:ok, CDS.t()} | {:error, term()}
  def decode(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    case decode_prefix(binary, opts) do
      {:ok, value, <<>>} -> {:ok, value}
      {:ok, _value, rest} -> {:error, {:trailing_cds_data, byte_size(rest)}}
      {:incomplete, _buffer} -> {:error, :truncated_cds}
      {:error, _reason} = error -> error
    end
  end

  @spec decode_prefix(binary(), keyword()) ::
          {:ok, CDS.t(), binary()} | {:incomplete, binary()} | {:error, term()}
  def decode_prefix(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    case Keyword.get(opts, :preamble, true) do
      true -> decode_explicit(binary, opts)
      false -> decode_implicit(binary, opts)
      value -> {:error, {:invalid_preamble_presence, value}}
    end
  end

  defp encode_preamble(configuration, opts) do
    case Keyword.get(opts, :preamble, true) do
      true -> Preamble.encode(configuration)
      false -> {:ok, <<>>}
      value -> {:error, {:invalid_preamble_presence, value}}
    end
  end

  defp encode_submilliseconds(%CDS{configuration: %{submillisecond_octets: 0}}),
    do: {:ok, <<>>}

  defp encode_submilliseconds(%CDS{} = value) do
    bits = value.configuration.submillisecond_octets * 8
    {:ok, <<value.submilliseconds::unsigned-big-integer-size(bits)>>}
  end

  defp decode_explicit(binary, opts) do
    case Preamble.decode_prefix(binary, day_length: Keyword.get(opts, :day_length, :unknown)) do
      {:ok, configuration, time_field, _encoded} ->
        decode_time_field(binary, time_field, configuration)

      {:incomplete, _buffer} ->
        {:incomplete, binary}

      {:error, _reason} = error ->
        error
    end
  end

  defp decode_implicit(binary, opts) do
    case Keyword.fetch(opts, :configuration) do
      {:ok, %Configuration{} = configuration} ->
        with :ok <- Configuration.validate(configuration) do
          decode_time_field(binary, binary, configuration)
        end

      {:ok, value} ->
        {:error, {:invalid_cds_configuration, value}}

      :error ->
        {:error, :cds_configuration_required}
    end
  end

  defp decode_time_field(original, binary, configuration) do
    expected = Configuration.time_octets(configuration)

    if byte_size(binary) >= expected do
      day_bits = configuration.day_octets * 8
      submillisecond_bits = configuration.submillisecond_octets * 8

      <<days::unsigned-big-integer-size(^day_bits), milliseconds::32,
        submilliseconds::unsigned-big-integer-size(^submillisecond_bits), rest::binary>> = binary

      with {:ok, value} <-
             CDS.new(
               day_count: days,
               milliseconds_of_day: milliseconds,
               submilliseconds: submilliseconds,
               configuration: configuration
             ) do
        {:ok, value, rest}
      end
    else
      {:incomplete, original}
    end
  end
end
