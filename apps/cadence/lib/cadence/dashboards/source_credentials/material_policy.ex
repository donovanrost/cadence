defmodule Cadence.Dashboards.SourceCredentials.MaterialPolicy do
  @moduledoc """
  Shared validation for ephemeral dashboard source credential material.
  """

  @allowed_material_keys [
    :http_endpoint,
    :username,
    :password,
    :bearer_token,
    :headers
  ]

  @spec normalize_and_validate(map()) ::
          {:ok, map()}
          | {:error,
             :ambiguous_auth_material
             | :empty_env_material_profile
             | :incomplete_basic_auth_material
             | {:invalid_credential_material_field, atom()}
             | {:invalid_http_endpoint, :http_endpoint}}
  def normalize_and_validate(material) when is_map(material) do
    with {:ok, normalized} <- normalize_material(material),
         :ok <- validate_material(normalized) do
      {:ok, normalized}
    end
  end

  defp normalize_material(material) do
    Enum.reduce_while(@allowed_material_keys, {:ok, %{}}, fn key, {:ok, acc} ->
      put_normalized_value(acc, key, material_value(material, key))
    end)
  end

  defp put_normalized_value(acc, _key, nil), do: {:cont, {:ok, acc}}
  defp put_normalized_value(acc, _key, ""), do: {:cont, {:ok, acc}}
  defp put_normalized_value(acc, _key, []), do: {:cont, {:ok, acc}}

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
  defp normalize_value(_key, value), do: {:ok, to_string(value)}

  defp validate_material(material) when material == %{}, do: {:error, :empty_env_material_profile}

  defp validate_material(%{http_endpoint: http_endpoint} = material) do
    case validate_http_endpoint(http_endpoint) do
      :ok -> validate_auth_material(material)
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_material(material), do: validate_auth_material(material)

  defp validate_auth_material(material) do
    bearer? = non_empty?(Map.get(material, :bearer_token))
    username? = non_empty?(Map.get(material, :username))
    password? = non_empty?(Map.get(material, :password))

    cond do
      bearer? and (username? or password?) -> {:error, :ambiguous_auth_material}
      username? != password? -> {:error, :incomplete_basic_auth_material}
      true -> :ok
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

  defp validate_http_endpoint(_value), do: {:error, {:invalid_http_endpoint, :http_endpoint}}

  defp material_value(material, key) when is_map(material) and is_atom(key) do
    Map.get(material, key, Map.get(material, Atom.to_string(key)))
  end

  defp non_empty?(value), do: is_binary(value) and value != ""
end
