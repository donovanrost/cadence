defmodule CCSDS.Time.CUC.Codec do
  @moduledoc """
  Strict CUC P-field and T-field codec.

  Explicit P-fields are used by default. For an implicit P-field, pass
  `preamble: false` and the managed `configuration` when decoding.
  """

  alias CCSDS.Time.CUC
  alias CCSDS.Time.CUC.{Configuration, Preamble}

  @spec encode(CUC.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%CUC{} = value, opts \\ []) when is_list(opts) do
    with :ok <- CUC.validate(value),
         {:ok, preamble} <- encode_preamble(value.configuration, opts) do
      configuration = value.configuration

      {:ok,
       preamble <>
         <<value.coarse_time::unsigned-big-integer-size(configuration.coarse_octets * 8),
           value.fine_time::unsigned-big-integer-size(configuration.fine_octets * 8)>>}
    end
  end

  @spec decode(binary(), keyword()) :: {:ok, CUC.t()} | {:error, term()}
  def decode(binary, opts \\ []) when is_binary(binary) and is_list(opts) do
    case decode_prefix(binary, opts) do
      {:ok, value, <<>>} -> {:ok, value}
      {:ok, _value, rest} -> {:error, {:trailing_cuc_data, byte_size(rest)}}
      {:incomplete, _buffer} -> {:error, :truncated_cuc}
      {:error, _reason} = error -> error
    end
  end

  @spec decode_prefix(binary(), keyword()) ::
          {:ok, CUC.t(), binary()} | {:incomplete, binary()} | {:error, term()}
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

  defp decode_explicit(binary, opts) do
    case Preamble.decode_prefix(binary, basic_unit: Keyword.get(opts, :basic_unit, {1, 1})) do
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
        {:error, {:invalid_cuc_configuration, value}}

      :error ->
        {:error, :cuc_configuration_required}
    end
  end

  defp decode_time_field(original, binary, configuration) do
    expected = Configuration.time_octets(configuration)

    if byte_size(binary) >= expected do
      coarse_bits = configuration.coarse_octets * 8
      fine_bits = configuration.fine_octets * 8

      <<coarse::unsigned-big-integer-size(^coarse_bits),
        fine::unsigned-big-integer-size(^fine_bits), rest::binary>> = binary

      with {:ok, value} <-
             CUC.new(
               coarse_time: coarse,
               fine_time: fine,
               configuration: configuration
             ) do
        {:ok, value, rest}
      end
    else
      {:incomplete, original}
    end
  end
end
