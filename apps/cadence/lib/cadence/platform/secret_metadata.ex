defmodule Cadence.Platform.SecretMetadata do
  @moduledoc false

  @sensitive_keys ~w[
    access_key
    api_key
    api_token
    apikey
    bearer_token
    credential
    credentials
    password
    passwd
    secret
    secret_key
    token
  ]

  @spec contains_secret?(term()) :: boolean()
  def contains_secret?(metadata) when is_map(metadata) do
    Enum.any?(metadata, fn {key, value} ->
      sensitive_key?(key) or contains_secret?(value)
    end)
  end

  def contains_secret?(values) when is_list(values), do: Enum.any?(values, &contains_secret?/1)
  def contains_secret?(_value), do: false

  defp sensitive_key?(key) do
    key
    |> to_string()
    |> String.downcase()
    |> then(&(&1 in @sensitive_keys))
  end
end
