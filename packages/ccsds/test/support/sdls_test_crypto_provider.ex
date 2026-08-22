defmodule CCSDS.TestSupport.SDLSTestCryptoProvider do
  @moduledoc false

  @behaviour CCSDS.SDLS.CryptoProvider

  import Bitwise

  @impl true
  def padding_length(data, operation, state) do
    padding =
      if operation.association.encryption_algorithm == :xor_padded,
        do: Integer.mod(-byte_size(data), 4),
        else: 0

    {:ok, padding, bump(state, :padding_length)}
  end

  @impl true
  def encrypt(data, operation, state) do
    padded = data <> :binary.copy(<<0>>, operation.pad_length)
    encrypted = xor(padded)
    {:ok, encrypted, next_iv(operation.initialization_vector), bump(state, :encrypt)}
  end

  @impl true
  def decrypt(data, operation, state) do
    decrypted = xor(data)

    if valid_padding?(decrypted, operation.pad_length) do
      {:ok, decrypted, next_iv(operation.initialization_vector), bump(state, :decrypt)}
    else
      {:error, :padding_error}
    end
  end

  @impl true
  def authenticate(payload, operation, state) do
    key_ref = :erlang.term_to_binary(operation.association.authentication_key_ref)
    {:ok, :crypto.hash(:sha512, payload <> key_ref), bump(state, :authenticate)}
  end

  defp xor(binary) do
    for <<byte <- binary>>, into: <<>>, do: <<bxor(byte, 0xA5)>>
  end

  defp next_iv(<<>>), do: <<>>

  defp next_iv(iv) do
    bits = byte_size(iv) * 8
    next = Integer.mod(:binary.decode_unsigned(iv) + 1, 1 <<< bits)
    <<next::unsigned-big-integer-size(bits)>>
  end

  defp valid_padding?(_data, 0), do: true

  defp valid_padding?(data, length) when length <= byte_size(data) do
    binary_part(data, byte_size(data) - length, length) == :binary.copy(<<0>>, length)
  end

  defp valid_padding?(_data, _length), do: false

  defp bump(nil, operation), do: %{operation => 1}
  defp bump(state, operation), do: Map.update(state, operation, 1, &(&1 + 1))
end
