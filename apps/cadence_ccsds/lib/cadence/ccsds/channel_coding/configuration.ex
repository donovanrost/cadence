defmodule Cadence.CCSDS.ChannelCoding.Configuration do
  @moduledoc """
  Managed TC synchronization and channel-coding parameters.

  The selected parameters are fixed for a physical channel and are not
  signaled in the CLTU wire representation.
  """

  @type code :: :bch | :ldpc_128_64 | :ldpc_512_256
  @type bch_decoding_mode :: :detect | :correct

  @type t :: %__MODULE__{
          code: code(),
          randomize?: boolean(),
          bch_decoding_mode: bch_decoding_mode(),
          allowed_start_errors: 0 | 1,
          ldpc_tail?: boolean(),
          max_cltu_octets: pos_integer() | nil
        }

  defstruct code: :bch,
            randomize?: false,
            bch_decoding_mode: :detect,
            allowed_start_errors: 0,
            ldpc_tail?: false,
            max_cltu_octets: nil

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    code = Map.get(attrs, :code, :bch)

    defaults = %{
      randomize?: code != :bch,
      ldpc_tail?: code == :ldpc_128_64
    }

    known_fields = Map.keys(Map.from_struct(%__MODULE__{}))

    with [] <- Map.keys(attrs) -- known_fields,
         configuration = struct(__MODULE__, Map.merge(defaults, attrs)),
         :ok <- validate(configuration) do
      {:ok, configuration}
    else
      [_unknown | _rest] -> {:error, :unknown_channel_coding_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, configuration} ->
        configuration

      {:error, reason} ->
        raise ArgumentError, "invalid channel coding configuration: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <- validate_member(configuration.code, [:bch, :ldpc_128_64, :ldpc_512_256], :code),
         :ok <- validate_boolean(configuration.randomize?, :randomize?),
         :ok <-
           validate_member(
             configuration.bch_decoding_mode,
             [:detect, :correct],
             :bch_decoding_mode
           ),
         :ok <- validate_member(configuration.allowed_start_errors, [0, 1], :allowed_start_errors),
         :ok <- validate_boolean(configuration.ldpc_tail?, :ldpc_tail?),
         :ok <- validate_optional_positive(configuration.max_cltu_octets, :max_cltu_octets) do
      validate_code_constraints(configuration)
    end
  end

  defp validate_code_constraints(%__MODULE__{code: :bch, ldpc_tail?: false}), do: :ok

  defp validate_code_constraints(%__MODULE__{code: :bch}),
    do: {:error, {:invalid_field, :ldpc_tail?, true}}

  defp validate_code_constraints(%__MODULE__{code: :ldpc_128_64, randomize?: true}), do: :ok

  defp validate_code_constraints(%__MODULE__{code: :ldpc_128_64}),
    do: {:error, {:randomization_required, :ldpc_128_64}}

  defp validate_code_constraints(%__MODULE__{
         code: :ldpc_512_256,
         randomize?: true,
         ldpc_tail?: false
       }),
       do: :ok

  defp validate_code_constraints(%__MODULE__{code: :ldpc_512_256, randomize?: false}),
    do: {:error, {:randomization_required, :ldpc_512_256}}

  defp validate_code_constraints(%__MODULE__{code: :ldpc_512_256, ldpc_tail?: true}),
    do: {:error, {:tail_sequence_forbidden, :ldpc_512_256}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_member(value, allowed, field) do
    if value in allowed, do: :ok, else: {:error, {:invalid_field, field, value}}
  end

  defp validate_optional_positive(nil, _field), do: :ok
  defp validate_optional_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_optional_positive(value, field), do: {:error, {:invalid_field, field, value}}
end
