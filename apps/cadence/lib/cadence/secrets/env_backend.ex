defmodule Cadence.Secrets.EnvBackend do
  @moduledoc "Local-only environment-backed secret resolver."

  @behaviour Cadence.Secrets.Backend

  @material_env_keys %{
    http_endpoint_env: :http_endpoint,
    username_env: :username,
    password_env: :password,
    bearer_token_env: :bearer_token
  }

  @profile_metadata_keys [:material_env_profile, :material_profile]

  @impl true
  def capabilities(_opts), do: [:resolve]

  @impl true
  @spec resolve(struct() | map(), keyword()) :: {:ok, map()} | {:error, term()}
  def resolve(descriptor, opts \\ []) when is_map(descriptor) and is_list(opts) do
    with :ok <- require_local_mode(opts) do
      case descriptor_value(descriptor, :backend_key) do
        env_var when is_binary(env_var) and env_var != "" -> resolve_provider_env(env_var, opts)
        _missing -> resolve_profile(descriptor, opts)
      end
    end
  end

  defp require_local_mode(opts) do
    if Keyword.get(opts, :allow_env_secret_backend?, false),
      do: :ok,
      else: {:error, :env_secret_backend_local_only}
  end

  defp resolve_provider_env(env_var, opts) do
    env_reader = Keyword.get(opts, :env_reader, &System.get_env/1)

    case read_env(env_reader, env_var) do
      value when is_binary(value) and value != "" ->
        {:ok,
         %{
           material: %{value: value},
           fingerprint: fingerprint(value)
         }}

      _missing ->
        {:error, {:secret_reference_not_found, :env}}
    end
  end

  defp resolve_profile(descriptor, opts) do
    profile_key = profile_key(descriptor)

    with {:ok, profile} <- fetch_profile(profile_key, descriptor, opts),
         {:ok, material} <- material_from_profile(profile, opts) do
      {:ok, %{material: material, fingerprint: fingerprint(material)}}
    end
  end

  defp fetch_profile(profile_key, descriptor, opts) do
    profiles =
      Keyword.get(opts, :env_material_profiles) ||
        :cadence
        |> Application.get_env(:data_source_credentials, [])
        |> Keyword.get(:env_material_profiles, %{})

    case map_value(profiles, profile_key) do
      nil -> fetch_inline_profile(profile_key, descriptor)
      profile when is_map(profile) -> {:ok, profile}
      profile -> {:error, {:invalid_env_material_profile, profile}}
    end
  end

  defp fetch_inline_profile(profile_key, descriptor) do
    profile =
      descriptor
      |> descriptor_value(:metadata, %{})
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
    Enum.reduce(profile, %{}, fn {key, value}, acc ->
      normalized_key =
        if is_binary(key) do
          Enum.find(Map.keys(@material_env_keys), &(Atom.to_string(&1) == key))
        else
          key
        end

      if normalized_key in Map.keys(@material_env_keys),
        do: Map.put(acc, normalized_key, value),
        else: acc
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

  defp resolve_header_env(_header_name, _env_var, _resolved, headers, _env_reader),
    do: {:halt, {:error, {:invalid_env_material_profile, headers}}}

  defp read_required_env(env_reader, env_var, material_field) do
    case read_env(env_reader, env_var) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, {:missing_env, env_var, material_field}}
    end
  end

  defp read_env(env_reader, env_var) when is_function(env_reader, 1), do: env_reader.(env_var)

  defp profile_key(descriptor) do
    metadata = descriptor_value(descriptor, :metadata, %{})

    Enum.find_value(@profile_metadata_keys, fn key -> map_value(metadata, key) end) ||
      descriptor_value(descriptor, :credentials_ref)
  end

  defp descriptor_value(descriptor, key, default \\ nil),
    do: Map.get(descriptor, key, Map.get(descriptor, Atom.to_string(key), default))

  defp map_value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp map_value(map, key) when is_map(map), do: Map.get(map, key)

  defp fingerprint(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
