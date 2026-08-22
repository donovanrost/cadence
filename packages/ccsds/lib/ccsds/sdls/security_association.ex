defmodule CCSDS.SDLS.SecurityAssociation do
  @moduledoc """
  Algorithm-neutral CCSDS 355.0-B-2 Security Association.

  Algorithm identifiers and key references are opaque values interpreted by a
  caller-supplied crypto provider. The struct stores protocol parameters and
  initial pure state, never key material or persistence policy.
  """

  import Bitwise

  alias CCSDS.SDLS.Channel

  @type service_type :: :authentication | :encryption | :authenticated_encryption
  @type sequence_number_source :: :sequence_number | :initialization_vector | nil

  @type t :: %__MODULE__{
          spi: 1..65_534,
          channels: [Channel.t()],
          service_type: service_type(),
          active?: boolean(),
          initialization_vector_length: 0..32,
          sequence_number_length: 0..8,
          pad_length_length: 0..2,
          mac_length: 0..64,
          authentication_algorithm: term(),
          authentication_key_ref: term(),
          authentication_mask: binary() | nil,
          sequence_number: non_neg_integer(),
          sequence_window: pos_integer() | nil,
          sequence_number_source: sequence_number_source(),
          encryption_algorithm: term(),
          encryption_key_ref: term(),
          initialization_vector: binary()
        }

  defstruct spi: nil,
            channels: [],
            service_type: nil,
            active?: false,
            initialization_vector_length: 0,
            sequence_number_length: 0,
            pad_length_length: 0,
            mac_length: 0,
            authentication_algorithm: nil,
            authentication_key_ref: nil,
            authentication_mask: nil,
            sequence_number: 0,
            sequence_window: nil,
            sequence_number_source: nil,
            encryption_algorithm: nil,
            encryption_key_ref: nil,
            initialization_vector: <<>>

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> normalize_channels()
    known_fields = Map.keys(Map.from_struct(%__MODULE__{}))

    with [] <- Map.keys(attrs) -- known_fields,
         association = struct(__MODULE__, attrs),
         :ok <- validate(association) do
      {:ok, association}
    else
      [_unknown | _rest] -> {:error, :unknown_security_association_attribute}
      {:error, _reason} = error -> error
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, association} -> association
      {:error, reason} -> raise ArgumentError, "invalid SDLS association: #{inspect(reason)}"
    end
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = association) do
    with :ok <- validate_range(association.spi, 1, 65_534, :spi),
         :ok <- validate_channels(association.channels),
         :ok <- validate_service_type(association.service_type),
         :ok <- validate_boolean(association.active?, :active?),
         :ok <- validate_optional_length(association.initialization_vector_length, 32, :iv),
         :ok <- validate_sequence_length(association.sequence_number_length),
         :ok <- validate_pad_length(association.pad_length_length),
         :ok <- validate_mac_length(association.mac_length),
         :ok <- validate_header_length(association),
         :ok <- validate_initialization_vector(association),
         :ok <- validate_service_parameters(association) do
      validate_initial_sequence(association)
    end
  end

  def validate(value), do: {:error, {:invalid_security_association, value}}

  @spec authentication?(t()) :: boolean()
  def authentication?(%__MODULE__{service_type: type}),
    do: type in [:authentication, :authenticated_encryption]

  @spec encryption?(t()) :: boolean()
  def encryption?(%__MODULE__{service_type: type}),
    do: type in [:encryption, :authenticated_encryption]

  @spec header_length(t()) :: pos_integer()
  def header_length(%__MODULE__{} = association) do
    2 + association.initialization_vector_length + association.sequence_number_length +
      association.pad_length_length
  end

  @spec physical_channel(t()) :: binary()
  def physical_channel(%__MODULE__{channels: [channel | _rest]}),
    do: channel.physical_channel

  defp normalize_channels(%{channels: channels} = attrs) when is_list(channels) do
    normalized =
      Enum.map(channels, fn
        %Channel{} = channel ->
          channel

        channel_attrs when is_map(channel_attrs) or is_list(channel_attrs) ->
          struct(Channel, Map.new(channel_attrs))

        value ->
          value
      end)

    %{attrs | channels: normalized}
  end

  defp normalize_channels(attrs), do: attrs

  defp validate_channels([%Channel{} | _rest] = channels) do
    with :ok <- validate_each_channel(channels),
         :ok <- validate_unique_channels(channels),
         :ok <- validate_common_link(channels) do
      validate_protocol_channel_scope(channels)
    end
  end

  defp validate_channels(value), do: {:error, {:invalid_field, :channels, value}}

  defp validate_each_channel(channels) do
    Enum.reduce_while(channels, :ok, fn channel, :ok ->
      case Channel.validate(channel) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_channel, reason}}}
      end
    end)
  end

  defp validate_unique_channels(channels) do
    keys = Enum.map(channels, &Channel.key/1)
    if keys == Enum.uniq(keys), do: :ok, else: {:error, :duplicate_security_channel}
  end

  defp validate_common_link([first | rest]) do
    if Enum.all?(rest, &same_link?(&1, first)) do
      :ok
    else
      {:error, :security_association_spans_physical_links}
    end
  end

  defp same_link?(left, right) do
    left.physical_channel == right.physical_channel and left.protocol == right.protocol
  end

  defp validate_protocol_channel_scope([%Channel{protocol: :tc} | _rest] = channels),
    do: validate_single_virtual_channel(channels, :tc)

  defp validate_protocol_channel_scope([%Channel{protocol: :uslp} | _rest] = channels) do
    if Enum.any?(channels, & &1.cop_in_use?),
      do: validate_single_virtual_channel(channels, :uslp_cop),
      else: :ok
  end

  defp validate_protocol_channel_scope(_channels), do: :ok

  defp validate_single_virtual_channel(channels, context) do
    virtual_channels =
      channels
      |> Enum.map(&{&1.transfer_frame_version, &1.scid, &1.vcid})
      |> Enum.uniq()

    if length(virtual_channels) == 1,
      do: :ok,
      else: {:error, {:security_association_spans_virtual_channels, context, virtual_channels}}
  end

  defp validate_service_type(value)
       when value in [:authentication, :encryption, :authenticated_encryption],
       do: :ok

  defp validate_service_type(value), do: {:error, {:invalid_field, :service_type, value}}

  defp validate_sequence_length(0), do: :ok
  defp validate_sequence_length(value), do: validate_range(value, 2, 8, :sequence_number_length)

  defp validate_pad_length(0), do: :ok
  defp validate_pad_length(value), do: validate_range(value, 1, 2, :pad_length_length)

  defp validate_mac_length(0), do: :ok
  defp validate_mac_length(value), do: validate_range(value, 8, 64, :mac_length)

  defp validate_optional_length(0, _maximum, _field), do: :ok

  defp validate_optional_length(value, maximum, field),
    do: validate_range(value, 1, maximum, field)

  defp validate_header_length(association) do
    length = header_length(association)
    if length <= 64, do: :ok, else: {:error, {:security_header_too_long, length}}
  end

  defp validate_initialization_vector(association) do
    value = association.initialization_vector
    expected = association.initialization_vector_length

    if is_binary(value) and byte_size(value) == expected,
      do: :ok,
      else: {:error, {:initialization_vector_length_mismatch, byte_size_safe(value), expected}}
  end

  defp validate_service_parameters(%__MODULE__{service_type: :authentication} = association) do
    with :ok <- validate_authentication_parameters(association),
         :ok <- validate_absent(association.encryption_algorithm, :encryption_algorithm) do
      validate_absent(association.encryption_key_ref, :encryption_key_ref)
    end
  end

  defp validate_service_parameters(%__MODULE__{service_type: :encryption} = association) do
    with :ok <- validate_encryption_parameters(association),
         :ok <- validate_zero(association.mac_length, :mac_length),
         :ok <- validate_zero(association.sequence_number_length, :sequence_number_length),
         :ok <- validate_absent(association.sequence_number_source, :sequence_number_source),
         :ok <- validate_absent(association.authentication_algorithm, :authentication_algorithm),
         :ok <- validate_absent(association.authentication_key_ref, :authentication_key_ref) do
      validate_absent(association.authentication_mask, :authentication_mask)
    end
  end

  defp validate_service_parameters(%__MODULE__{service_type: :authenticated_encryption} = assoc) do
    with :ok <- validate_authentication_parameters(assoc) do
      validate_encryption_parameters(assoc)
    end
  end

  defp validate_authentication_parameters(association) do
    with :ok <- validate_present(association.authentication_algorithm, :authentication_algorithm),
         :ok <- validate_present(association.authentication_key_ref, :authentication_key_ref),
         :ok <- validate_binary(association.authentication_mask, :authentication_mask),
         :ok <- validate_range(association.mac_length, 8, 64, :mac_length),
         :ok <- validate_positive(association.sequence_window, :sequence_window) do
      validate_sequence_source(association)
    end
  end

  defp validate_encryption_parameters(association) do
    with :ok <- validate_present(association.encryption_algorithm, :encryption_algorithm) do
      validate_present(association.encryption_key_ref, :encryption_key_ref)
    end
  end

  defp validate_sequence_source(%__MODULE__{sequence_number_source: :sequence_number} = assoc) do
    validate_range(assoc.sequence_number_length, 2, 8, :sequence_number_length)
  end

  defp validate_sequence_source(
         %__MODULE__{sequence_number_source: :initialization_vector} = assoc
       ) do
    with :ok <- validate_zero(assoc.sequence_number_length, :sequence_number_length) do
      validate_range(assoc.initialization_vector_length, 1, 32, :initialization_vector_length)
    end
  end

  defp validate_sequence_source(association),
    do: {:error, {:invalid_field, :sequence_number_source, association.sequence_number_source}}

  defp validate_initial_sequence(association) do
    cond do
      not is_integer(association.sequence_number) or association.sequence_number < 0 ->
        {:error, {:invalid_field, :sequence_number, association.sequence_number}}

      association.sequence_number_source == :sequence_number ->
        validate_integer_capacity(
          association.sequence_number,
          association.sequence_number_length,
          :sequence_number
        )

      association.sequence_number_source == :initialization_vector ->
        expected = :binary.decode_unsigned(association.initialization_vector)

        if association.sequence_number == expected,
          do: :ok,
          else: {:error, {:sequence_number_iv_mismatch, association.sequence_number, expected}}

      true ->
        validate_zero(association.sequence_number, :sequence_number)
    end
  end

  defp validate_integer_capacity(value, octets, field) do
    if value < 1 <<< (octets * 8), do: :ok, else: {:error, {:field_overflow, field, value}}
  end

  defp validate_present(nil, field), do: {:error, {:missing_field, field}}
  defp validate_present(_value, _field), do: :ok

  defp validate_absent(nil, _field), do: :ok
  defp validate_absent(value, field), do: {:error, {:unexpected_field, field, value}}

  defp validate_binary(value, _field) when is_binary(value), do: :ok
  defp validate_binary(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok
  defp validate_boolean(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_positive(value, _field) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_zero(0, _field), do: :ok
  defp validate_zero(value, field), do: {:error, {:field_must_be_zero, field, value}}

  defp validate_range(value, minimum, maximum, _field)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: :ok

  defp validate_range(value, _minimum, _maximum, field),
    do: {:error, {:invalid_field, field, value}}

  defp byte_size_safe(value) when is_binary(value), do: byte_size(value)
  defp byte_size_safe(_value), do: :invalid
end
