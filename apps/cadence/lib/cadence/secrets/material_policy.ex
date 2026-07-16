defmodule Cadence.Secrets.MaterialPolicy do
  @moduledoc "Normalization and validation for ephemeral secret material."

  @dashboard_keys [:http_endpoint, :username, :password, :bearer_token, :headers]

  @provider_keys [
    :value,
    :api_key,
    :token,
    :access_key_id,
    :secret_access_key,
    :session_token,
    :username,
    :password,
    :bearer_token,
    :headers
  ]

  @spec dashboard_keys() :: [atom()]
  def dashboard_keys, do: @dashboard_keys

  @spec provider_keys() :: [atom()]
  def provider_keys, do: @provider_keys

  @spec normalize_and_validate(map() | binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def normalize_and_validate(material, opts \\ [])

  def normalize_and_validate(material, opts) when is_binary(material) do
    normalize_and_validate(%{value: material}, opts)
  end

  def normalize_and_validate(material, opts) when is_map(material) and is_list(opts) do
    allowed_keys = Keyword.get(opts, :allowed_material_keys, @provider_keys)

    with {:ok, normalized} <- normalize_material(material, allowed_keys),
         :ok <- validate_material(normalized, opts) do
      {:ok, normalized}
    end
  end

  def normalize_and_validate(_material, _opts),
    do: {:error, :invalid_secret_material}

  defp normalize_material(material, allowed_keys) do
    Enum.reduce_while(allowed_keys, {:ok, %{}}, fn key, {:ok, acc} ->
      put_normalized_value(acc, key, material_value(material, key))
    end)
  end

  defp put_normalized_value(acc, _key, value) when value in [nil, "", []],
    do: {:cont, {:ok, acc}}

  defp put_normalized_value(acc, key, value) do
    case normalize_value(key, value) do
      {:ok, normalized_value} -> {:cont, {:ok, Map.put(acc, key, normalized_value)}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp normalize_value(:headers, headers) when is_map(headers) do
    {:ok, Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)}
  end

  defp normalize_value(:headers, headers) when is_list(headers) do
    if Enum.all?(headers, &match?({_key, _value}, &1)) do
      {:ok, Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)}
    else
      {:error, {:invalid_credential_material_field, :headers}}
    end
  end

  defp normalize_value(:headers, _headers),
    do: {:error, {:invalid_credential_material_field, :headers}}

  defp normalize_value(_key, value) when is_binary(value), do: {:ok, value}
  defp normalize_value(key, _value), do: {:error, {:invalid_credential_material_field, key}}

  defp validate_material(material, opts) when material == %{} do
    if Keyword.get(opts, :allow_empty?, false),
      do: :ok,
      else: {:error, :empty_env_material_profile}
  end

  defp validate_material(%{http_endpoint: endpoint} = material, opts) do
    with :ok <- validate_http_endpoint(endpoint), do: validate_auth_material(material, opts)
  end

  defp validate_material(material, opts), do: validate_auth_material(material, opts)

  defp validate_auth_material(material, opts) do
    if Keyword.get(opts, :validate_auth_shape?, true) do
      bearer? = non_empty?(Map.get(material, :bearer_token))
      username? = non_empty?(Map.get(material, :username))
      password? = non_empty?(Map.get(material, :password))

      cond do
        bearer? and (username? or password?) -> {:error, :ambiguous_auth_material}
        username? != password? -> {:error, :incomplete_basic_auth_material}
        true -> :ok
      end
    else
      :ok
    end
  end

  defp validate_http_endpoint(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host, userinfo: nil}
      when scheme in ["http", "https"] and is_binary(host) ->
        :ok

      _other ->
        {:error, {:invalid_http_endpoint, :http_endpoint}}
    end
  end

  defp material_value(material, key),
    do: Map.get(material, key, Map.get(material, Atom.to_string(key)))

  defp non_empty?(value), do: is_binary(value) and value != ""
end
