defmodule Cadence.Secrets.EnvBackend do
  @moduledoc """
  Local-only environment-backed secret resolver.

  Provider credentials use it only where the environment enables local credentials
  (`allow_env_secret_backend?`); data sources use it only where a deployment configures
  `CADENCE_DATA_SOURCE_CREDENTIAL_ENV_PROFILES` (that configuration is their gate).

  Even then, what a TENANT names is scoped to its organization (api-ops' security sweep, api's
  review, 11-15), checked on save and again before anything is read:

  - A variable a tenant names (a provider credential's key, a data-source descriptor's `*_env`
    fields) must be listed in `config :cadence, :env_credentials, allow: [names]` (the operator's
    explicit names), start with one of its `allow_prefixes` (operator-wide), or start with the
    organization's own prefix `CADENCE_TENANT_<ORG>_` (`tenant_prefix/1`), so one tenant can't
    read the platform's secrets or another tenant's.
  - A configured material profile (`env_material_profiles`) is the operator's: a profile with
    `organization_id`/`organization_ids` serves only those organizations; one without serves only
    platform sources (no organization). A tenant can't select another organization's profile.

  Errors carry a variable's name at most, never its value.
  """

  @behaviour Cadence.Secrets.Backend

  @material_env_keys %{
    http_endpoint_env: :http_endpoint,
    username_env: :username,
    password_env: :password,
    bearer_token_env: :bearer_token
  }

  @profile_metadata_keys [:material_env_profile, :material_profile]

  @tenant_prefix "CADENCE_TENANT_"

  @impl true
  def capabilities(_opts), do: [:resolve]

  @doc "The variable prefix an organization's own credentials use: `CADENCE_TENANT_<ORG>_`."
  @spec tenant_prefix(binary()) :: binary()
  def tenant_prefix(organization_id) when is_binary(organization_id) and organization_id != "" do
    token =
      organization_id
      |> String.upcase()
      |> String.replace(~r/[^A-Z0-9]/, "_")

    @tenant_prefix <> token <> "_"
  end

  @doc """
  Whether `organization_id` (nil for a platform record) may name `env_var` as a credential: an
  operator-listed name or prefix (`config :cadence, :env_credentials`; `opts` override, for
  tests), or the organization's own `tenant_prefix/1`.
  """
  @spec allowed_name?(term(), binary() | nil, keyword()) :: boolean()
  def allowed_name?(env_var, organization_id, opts \\ [])

  def allowed_name?(env_var, organization_id, opts) when is_binary(env_var) and env_var != "" do
    config = Application.get_env(:cadence, :env_credentials, [])
    names = Keyword.get(opts, :env_allow, Keyword.get(config, :allow, []))
    prefixes = Keyword.get(opts, :env_allow_prefixes, Keyword.get(config, :allow_prefixes, []))

    env_var in names or Enum.any?(prefixes, &String.starts_with?(env_var, &1)) or
      (is_binary(organization_id) and organization_id != "" and
         String.starts_with?(env_var, tenant_prefix(organization_id)) and
         byte_size(env_var) > byte_size(tenant_prefix(organization_id)))
  end

  def allowed_name?(_env_var, _organization_id, _opts), do: false

  @doc """
  Whether a descriptor of `organization_id` may use the configured material profile `key`. A key
  that names no configured profile isn't a profile selection (`true`; any inline names are
  checked on their own).
  """
  @spec profile_allowed?(term(), binary() | nil, keyword()) :: boolean()
  def profile_allowed?(key, organization_id, opts \\ [])

  def profile_allowed?(key, organization_id, opts) when is_binary(key) and key != "" do
    case map_value(configured_profiles(opts), key) do
      nil -> true
      profile when is_map(profile) -> profile_owner?(profile, organization_id)
      _invalid -> false
    end
  end

  def profile_allowed?(_key, _organization_id, _opts), do: true

  defp profile_owner?(profile, organization_id) do
    owners =
      List.wrap(map_value(profile, :organization_id)) ++
        List.wrap(map_value(profile, :organization_ids))

    case owners do
      [] -> is_nil(organization_id)
      owners -> is_binary(organization_id) and organization_id in owners
    end
  end

  defp configured_profiles(opts) do
    Keyword.get(opts, :env_material_profiles) ||
      :cadence
      |> Application.get_env(:data_source_credentials, [])
      |> Keyword.get(:env_material_profiles, %{})
  end

  @impl true
  @spec resolve(struct() | map(), keyword()) :: {:ok, map()} | {:error, term()}
  def resolve(descriptor, opts \\ []) when is_map(descriptor) and is_list(opts) do
    with :ok <- require_local_mode(opts) do
      case descriptor_value(descriptor, :backend_key) do
        env_var when is_binary(env_var) and env_var != "" ->
          resolve_provider_env(env_var, descriptor_value(descriptor, :organization_id), opts)

        _missing ->
          resolve_profile(descriptor, opts)
      end
    end
  end

  defp require_local_mode(opts) do
    if Keyword.get(opts, :allow_env_secret_backend?, false),
      do: :ok,
      else: {:error, :env_secret_backend_local_only}
  end

  defp resolve_provider_env(env_var, organization_id, opts) do
    env_reader = Keyword.get(opts, :env_reader, &System.get_env/1)

    case allowed_name?(env_var, organization_id, opts) && read_env(env_reader, env_var) do
      false ->
        {:error, :env_credential_name_not_allowed}

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
    organization_id = descriptor_value(descriptor, :organization_id)

    case map_value(configured_profiles(opts), profile_key) do
      nil ->
        profile_key
        |> fetch_inline_profile(descriptor)
        |> inline_names_allowed(organization_id, opts)

      profile when is_map(profile) ->
        if profile_owner?(profile, organization_id),
          do: {:ok, profile},
          else: {:error, :env_material_profile_not_allowed}

      profile ->
        {:error, {:invalid_env_material_profile, profile}}
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

  # An inline profile comes from the tenant's own descriptor: every variable it names must be one
  # this organization may use, before any is read. (Inline profiles carry only @material_env_keys;
  # if they ever take headers_env, its names must be checked here too.)
  defp inline_names_allowed({:ok, profile}, organization_id, opts) do
    if Enum.all?(Map.values(profile), &allowed_name?(&1, organization_id, opts)),
      do: {:ok, profile},
      else: {:error, :env_credential_name_not_allowed}
  end

  defp inline_names_allowed(error, _organization_id, _opts), do: error

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
