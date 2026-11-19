defmodule Cadence.Management.ProviderAccountWrites do
  @moduledoc """
  PA1 add and edit for the console. Cadence never receives provider secret
  values: an account's credential is a **reference** into the external secret
  manager (`backend: "external"`, `key` like `providers/<org>/<account>`) or,
  in development, an environment variable (`backend: "env"`). Saving
  registers the reference without calling the provider; `test` checks it.
  """

  alias Cadence.Auth.Scope

  alias Cadence.GroundNetworks.{MissionProvider, ProviderAccounts, ProviderCredentials}
  alias Cadence.Secrets.{EnvBackend, ResolverConfiguration}

  @backends %{"external" => :external, "env" => :env}
  # ProviderAccountVersion's modes, as the API sends them.
  @ingestion_modes ~w(polling webhook hybrid disabled)
  @mode_help "Use polling, webhook, hybrid or disabled."

  @doc "The add/edit form for an adapter (kind-schema fields)."
  @spec schema(binary()) :: {:ok, [map()]} | {:error, :provider_adapter_not_found}
  def schema(key) do
    if key in Enum.map(MissionProvider.provider_types(), &to_string/1),
      do: {:ok, fields()},
      else: {:error, :provider_adapter_not_found}
  end

  @doc ~S|`%{"provider_key", "name", "settings", "credential"}` → `{:ok, %{id, version}}`.|
  @spec create(Scope.t(), map()) :: {:ok, map()} | {:error, term()}
  def create(%Scope{} = scope, params) do
    account_id = Cadence.Ids.new("provider_account")

    # Name and address are checked before the credential is registered, so a refused create
    # leaves nothing behind.
    with {:ok, name} <- create_name(params["name"]),
         :ok <- base_url(params["settings"]),
         {:ok, settings} <- settings(params),
         {:ok, provider_type} <- provider_type(params["provider_key"]),
         {:ok, credential_ref} <- register_credential(scope, account_id, params["credential"]),
         {:ok, _account, version} <-
           ProviderAccounts.create(
             scope,
             Map.merge(settings, %{
               provider_account_id: account_id,
               display_name: name,
               provider_type: provider_type,
               credential_ref: credential_ref
             }),
             validate_credential?: false
           ) do
      {:ok, %{id: account_id, version: version.version}}
    end
  end

  @doc """
  A new account version from the changed settings (and credential reference, if sent). The
  name is renamed separately (the web layer calls `ProviderAccountRename`); with nothing else
  to change, no version is written.
  """
  @spec update(Scope.t(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def update(%Scope{} = _scope, account_id, params)
      when not is_map_key(params, "settings") and not is_map_key(params, "credential"),
      do: {:ok, %{id: account_id, version: nil}}

  def update(%Scope{} = scope, account_id, params) do
    with {:ok, settings} <- settings(params),
         {:ok, credential} <- maybe_credential(scope, account_id, params["credential"]),
         attrs = Map.merge(settings, credential),
         {:ok, _account, version} <-
           ProviderAccounts.version(scope, account_id, attrs, validate_credential?: false) do
      {:ok, %{id: account_id, version: version.version}}
    end
  end

  defp fields do
    [
      text("base_url", "Provider API address", required: true),
      text("environment_ref", "Environment",
        required: true,
        help: "The provider's environment, for example production."
      ),
      text("region_ref", "Region"),
      # The console offers polling or off; webhook and hybrid need the provider set up to post to
      # Cadence, which the console doesn't configure (the API still takes them). Words: ux.
      %{
        path: "event_ingestion_mode",
        label: "Contact events",
        type: :enum,
        enum: [
          %{value: "polling", label: "Fetch from the provider"},
          %{value: "disabled", label: "Off"}
        ],
        required: true,
        default: "polling",
        unit: nil,
        range: nil,
        help:
          "Whether Cadence asks the provider for contact events. Turn it off for an account " <>
            "you only test with.",
        visible_when: nil
      },
      %{
        path: "credential.backend",
        label: "Credential stored in",
        type: :enum,
        enum: [
          %{value: "external", label: "Secret manager"},
          %{value: "env", label: "Environment variable (development)"}
        ],
        required: true,
        default: "external",
        unit: nil,
        range: nil,
        help: "Cadence keeps only a reference; the secret never passes through it.",
        visible_when: nil
      },
      text("credential.key", "Secret reference",
        required: true,
        help: "The secret manager key (or variable name) holding the provider credential."
      )
    ]
  end

  defp text(path, label, opts \\ []) do
    %{
      path: path,
      label: label,
      type: :string,
      enum: nil,
      required: Keyword.get(opts, :required, false),
      default: nil,
      unit: nil,
      range: nil,
      help: Keyword.get(opts, :help),
      visible_when: nil
    }
  end

  # As a rename (ProviderAccountRename): trimmed, 1 to 120 bytes.
  defp create_name(value) when is_binary(value) do
    case String.trim(value) do
      trimmed when byte_size(trimmed) in 1..120 -> {:ok, trimmed}
      _invalid -> {:error, {:invalid_params, %{"name" => "Use 1 to 120 characters."}}}
    end
  end

  defp create_name(_value),
    do: {:error, {:invalid_params, %{"name" => "Use 1 to 120 characters."}}}

  # The account's own check (ProviderAccounts), answered on the field.
  defp base_url(%{"base_url" => url}) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> :ok
      _other -> {:error, :invalid_provider_account_base_url}
    end
  end

  defp base_url(_settings), do: {:error, :invalid_provider_account_base_url}

  # The settings a version takes from the request. `event_ingestion_mode` is one of the account's
  # modes (ProviderAccountVersion); absent, a create polls and an update keeps the current mode.
  defp settings(params) do
    settings = params["settings"] || %{}

    taken =
      [:base_url, :environment_ref, :region_ref, :event_ingestion_mode]
      |> Enum.flat_map(fn key ->
        case Map.fetch(settings, Atom.to_string(key)) do
          {:ok, value} -> [{key, value}]
          :error -> []
        end
      end)
      |> Map.new()

    case Map.fetch(taken, :event_ingestion_mode) do
      :error ->
        {:ok, taken}

      {:ok, mode} when mode in @ingestion_modes ->
        {:ok, taken}

      {:ok, _other} ->
        {:error, {:invalid_params, %{"settings.event_ingestion_mode" => @mode_help}}}
    end
  end

  defp maybe_credential(_scope, _account_id, nil), do: {:ok, %{}}

  defp maybe_credential(scope, account_id, credential) do
    with {:ok, ref} <- register_credential(scope, account_id, credential),
         do: {:ok, %{credential_ref: ref}}
  end

  defp register_credential(scope, account_id, %{"backend" => backend, "key" => key})
       when is_map_key(@backends, backend) and is_binary(key) and key != "" do
    ref = Cadence.Ids.new("provider_credential")

    with :ok <- backend_allowed(@backends[backend]),
         :ok <- key_allowed(@backends[backend], key, scope.organization_id),
         {:ok, _credential} <-
           ProviderCredentials.create(
             scope,
             account_id,
             %{provider_credential_ref: ref, backend_type: @backends[backend], backend_key: key},
             manage_backend?: false
           ),
         do: {:ok, ref}
  end

  defp register_credential(_scope, _account_id, _credential),
    do: {:error, {:invalid_params, %{"credential" => "needs backend (external or env) and key"}}}

  # Environment-variable references only work where local provider credentials are enabled
  # (development); the resolver would refuse them anyway, so say so on save (ux).
  defp backend_allowed(:env) do
    if ResolverConfiguration.provider_options()[:allow_local_provider_credentials?],
      do: :ok,
      else:
        {:error,
         {:invalid_params,
          %{
            "credential.backend" =>
              "Environment variables are for development only here; use the secret manager."
          }}}
  end

  defp backend_allowed(_backend), do: :ok

  # An environment variable is read only if this environment allows that name (EnvBackend), so a
  # credential can't name the platform's own secrets.
  defp key_allowed(:env, key, organization_id) do
    if EnvBackend.allowed_name?(key, organization_id),
      do: :ok,
      else:
        {:error,
         {:invalid_params,
          %{
            "credential.key" =>
              "Use a variable starting with #{EnvBackend.tenant_prefix(organization_id)}, or ask a platform admin."
          }}}
  end

  defp key_allowed(_backend, _key, _organization_id), do: :ok

  defp provider_type(key) do
    case Enum.find(MissionProvider.provider_types(), &(to_string(&1) == key)) do
      nil -> {:error, {:invalid_params, %{"provider_key" => "is not a known adapter"}}}
      type -> {:ok, type}
    end
  end
end
