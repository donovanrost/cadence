defmodule Cadence.Dashboards.SourceCredentials.EnvSecretBackend do
  @moduledoc """
  Secret backend that resolves dashboard source credential material from env vars.

  This backend is intended for local deployments and simple customer-managed
  installs. It keeps durable credential rows limited to profile names or env-var
  names while reading actual values only on the adapter execution path.
  """

  @behaviour Cadence.Dashboards.SourceCredentials.SecretBackend

  alias Cadence.Dashboards.ResolvedSourceCredential

  @material_env_keys %{
    http_endpoint_env: :http_endpoint,
    username_env: :username,
    password_env: :password,
    bearer_token_env: :bearer_token
  }

  @profile_metadata_keys [:material_env_profile, :material_profile]

  @impl true
  @spec fetch_material(ResolvedSourceCredential.t(), keyword()) ::
          {:ok, map()}
          | {:error,
             {:env_material_profile_not_configured, binary()}
             | {:invalid_env_material_profile, term()}
             | {:missing_env, binary(), atom()}
             | {:missing_header_env, binary(), binary()}}
  def fetch_material(%ResolvedSourceCredential{} = credential, opts \\ [])
      when is_list(opts) do
    profile_key = profile_key(credential)

    with {:ok, profile} <- fetch_profile(profile_key, credential, opts) do
      material_from_profile(profile, opts)
    end
  end

  defp fetch_profile(profile_key, credential, opts) do
    profiles =
      Keyword.get(opts, :env_material_profiles) ||
        :cadence
        |> Application.get_env(:dashboard_source_credentials, [])
        |> Keyword.get(:env_material_profiles, %{})

    case map_value(profiles, profile_key) do
      nil -> fetch_inline_profile(profile_key, credential)
      profile when is_map(profile) -> {:ok, profile}
      profile -> {:error, {:invalid_env_material_profile, profile}}
    end
  end

  defp fetch_inline_profile(profile_key, %ResolvedSourceCredential{} = credential) do
    profile =
      credential.metadata
      |> Map.take(
        Map.keys(@material_env_keys) ++ Enum.map(Map.keys(@material_env_keys), &to_string/1)
      )
      |> normalize_profile_keys()

    case profile do
      profile when profile == %{} -> {:error, {:env_material_profile_not_configured, profile_key}}
      profile -> {:ok, profile}
    end
  end

  defp normalize_profile_keys(profile) do
    profile
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      normalized_key =
        if is_binary(key) do
          Enum.find(Map.keys(@material_env_keys), &(Atom.to_string(&1) == key))
        else
          key
        end

      if normalized_key in Map.keys(@material_env_keys) do
        Map.put(acc, normalized_key, value)
      else
        acc
      end
    end)
  end

  defp material_from_profile(profile, opts) do
    env_reader = Keyword.get(opts, :env_reader, &System.get_env/1)

    Enum.reduce_while(@material_env_keys, {:ok, %{}}, fn mapping, {:ok, material} ->
      resolve_material_env(mapping, material, profile, env_reader)
    end)
    |> with_headers(profile, env_reader)
  end

  defp resolve_material_env({profile_field, material_field}, material, profile, env_reader) do
    case map_value(profile, profile_field) do
      nil ->
        {:cont, {:ok, material}}

      env_var when is_binary(env_var) ->
        put_material_env(material, env_reader, env_var, material_field)

      _other ->
        {:halt, {:error, {:invalid_env_material_profile, profile}}}
    end
  end

  defp put_material_env(material, env_reader, env_var, material_field) do
    case read_required_env(env_reader, env_var, material_field) do
      {:ok, value} -> {:cont, {:ok, Map.put(material, material_field, value)}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp with_headers({:error, reason}, _profile, _env_reader), do: {:error, reason}

  defp with_headers({:ok, material}, profile, env_reader) do
    case map_value(profile, :headers_env) do
      nil -> {:ok, material}
      headers when is_map(headers) -> resolve_headers(material, headers, env_reader)
      _other -> {:error, {:invalid_env_material_profile, profile}}
    end
  end

  defp resolve_headers(material, headers, env_reader) do
    Enum.reduce_while(headers, {:ok, []}, fn {header_name, env_var}, {:ok, resolved} ->
      header_name = to_string(header_name)
      resolve_header_env(header_name, env_var, resolved, headers, env_reader)
    end)
    |> case do
      {:ok, []} ->
        {:ok, material}

      {:ok, resolved_headers} ->
        {:ok, Map.put(material, :headers, Enum.reverse(resolved_headers))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_header_env(header_name, env_var, resolved, _headers, env_reader)
       when is_binary(env_var) do
    case read_env(env_reader, env_var) do
      value when is_binary(value) and value != "" ->
        {:cont, {:ok, [{header_name, value} | resolved]}}

      _missing ->
        {:halt, {:error, {:missing_header_env, header_name, env_var}}}
    end
  end

  defp resolve_header_env(_header_name, _env_var, _resolved, headers, _env_reader) do
    {:halt, {:error, {:invalid_env_material_profile, headers}}}
  end

  defp read_required_env(env_reader, env_var, material_field) do
    case read_env(env_reader, env_var) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:missing_env, env_var, material_field}}
    end
  end

  defp read_env(env_reader, env_var) when is_function(env_reader, 1), do: env_reader.(env_var)

  defp profile_key(%ResolvedSourceCredential{} = credential) do
    Enum.find_value(@profile_metadata_keys, fn key -> metadata_value(credential.metadata, key) end) ||
      credential.credentials_ref
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
end
