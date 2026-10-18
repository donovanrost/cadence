defmodule Cadence.ContactPlanning.OpportunityCapability do
  @moduledoc "Core-owned, expiring capability for a provider opportunity reservation."

  @salt "cadence-contact-opportunity-v1"
  @signature_bytes 32
  @default_max_age 15 * 60
  @minimum_secret_bytes 32

  @spec sign(map()) :: binary()
  def sign(payload) when is_map(payload) do
    issued_at = System.system_time(:second)
    body = canonical_json!(Map.put(payload, "issued_at", issued_at))
    signature = authenticate(body)

    Base.url_encode64(body <> signature, padding: false)
  end

  @spec verify(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def verify(token, opts \\ [])

  def verify(token, opts) when is_binary(token) do
    with {:ok, encoded} <- Base.url_decode64(token, padding: false),
         true <- byte_size(encoded) > @signature_bytes,
         {body, signature} <- split_signature(encoded),
         true <- :crypto.hash_equals(signature, authenticate(body)),
         {:ok, payload} <- Jason.decode(body),
         true <- is_map(payload),
         :ok <- valid_age(payload, Keyword.get(opts, :max_age, @default_max_age)) do
      {:ok, payload}
    else
      _invalid -> {:error, :invalid_opportunity_capability}
    end
  end

  def verify(_token, _opts), do: {:error, :invalid_opportunity_capability}

  defp split_signature(encoded) do
    :erlang.split_binary(encoded, byte_size(encoded) - @signature_bytes)
  end

  defp authenticate(body), do: :crypto.mac(:hmac, :sha256, secret!(), @salt <> body)

  defp valid_age(%{"issued_at" => issued_at}, max_age)
       when is_integer(issued_at) and is_integer(max_age) and max_age >= 0 do
    now = System.system_time(:second)

    if issued_at <= now and now - issued_at <= max_age do
      :ok
    else
      {:error, :expired_opportunity_capability}
    end
  end

  defp valid_age(_payload, _max_age), do: {:error, :invalid_opportunity_capability}

  defp canonical_json!(value) when is_map(value) do
    if Enum.all?(Map.keys(value), &is_binary/1) do
      entries =
        value
        |> Enum.sort_by(fn {key, _value} -> key end)
        |> Enum.map_join(",", fn {key, item} ->
          Jason.encode!(key) <> ":" <> canonical_json!(item)
        end)

      "{" <> entries <> "}"
    else
      raise ArgumentError, "opportunity capability payload keys must be binaries"
    end
  end

  defp canonical_json!(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json!/1) <> "]"
  end

  defp canonical_json!(value)
       when is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value) or
              is_nil(value) do
    Jason.encode!(value)
  end

  defp canonical_json!(_value), do: raise(ArgumentError, "invalid opportunity capability payload")

  defp secret! do
    case Application.get_env(:cadence, :opportunity_capability_secret) do
      secret when is_binary(secret) and byte_size(secret) >= @minimum_secret_bytes -> secret
      _missing_or_short -> raise "Cadence opportunity capability secret is not configured"
    end
  end
end
