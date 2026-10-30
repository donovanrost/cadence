defmodule Cadence.Runtime.RecoveryExchange do
  @moduledoc "An exact, separately permitted recovery exchange; never an ordinary command."
  alias Cadence.Platform.ContentHash

  @enforce_keys [
    :operation_id,
    :purpose,
    :provider_binding_id,
    :provider_adapter_key,
    :payloads_base64
  ]
  defstruct @enforce_keys

  def basis(%__MODULE__{} = exchange), do: Map.from_struct(exchange)
  def digest(%__MODULE__{} = exchange), do: ContentHash.term_sha256(basis(exchange))

  def valid?(%__MODULE__{} = exchange) do
    text?(exchange.operation_id) and text?(exchange.purpose) and
      is_binary(exchange.provider_binding_id) and is_atom(exchange.provider_adapter_key) and
      payloads?(exchange.payloads_base64)
  end

  defp text?(value), do: is_binary(value) and byte_size(value) in 1..255

  defp payloads?(values) when is_list(values) and length(values) in 1..256 do
    byte_size(:erlang.term_to_binary(values)) <= 65_536 and
      Enum.all?(values, fn value ->
        is_binary(value) and match?({:ok, _}, Base.decode64(value))
      end)
  end

  defp payloads?(_), do: false
end
