defmodule Cadence.Management.ProviderAccountWrites do
  @moduledoc """
  PA1 add and edit for the console. Cadence never receives provider secret
  values: an account's credential is a **reference** into the external secret
  manager (`backend: "external"`, `key` like `providers/<org>/<account>`) or,
  in development, an environment variable (`backend: "env"`). Saving
  registers the reference without calling the provider; `test` checks it.
  """

  alias Cadence.Auth.Scope

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountRetirement,
    ProviderAccounts,
    ProviderCredentials
  }

  alias Cadence.Missions
  alias Cadence.Secrets.ResolverConfiguration

  @backends %{"external" => :external, "env" => :env}

  @doc "The add/edit form for an adapter (kind-schema fields)."
  @spec schema(binary()) :: {:ok, [map()]} | {:error, :provider_adapter_not_found}
  def schema(key) do
    if key in Enum.map(MissionProvider.provider_types(), &to_string/1),
      do: {:ok, fields()},
      else: {:error, :provider_adapter_not_found}
  end

  @doc "`%{\"provider_key\", \"name\", \"settings\", \"credential\"}` → `{:ok, %{id, version}}`."
  @spec create(Scope.t(), map()) :: {:ok, map()} | {:error, term()}
  def create(%Scope{} = scope, params) do
    account_id = Cadence.Ids.new("provider_account")

    with {:ok, provider_type} <- provider_type(params["provider_key"]),
         {:ok, credential_ref} <- register_credential(scope, account_id, params["credential"]),
         {:ok, _account, version} <-
           ProviderAccounts.create(
             scope,
             params
             |> settings()
             |> Map.merge(%{
               provider_account_id: account_id,
               display_name: params["name"],
               provider_type: provider_type,
               credential_ref: credential_ref
             }),
             validate_credential?: false
           ) do
      {:ok, %{id: account_id, version: version.version}}
    end
  end

  @doc "A new account version from the changed settings (and credential reference, if sent)."
  @spec update(Scope.t(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def update(%Scope{} = scope, account_id, params) do
    with :ok <- no_rename(params["name"]),
         {:ok, credential} <- maybe_credential(scope, account_id, params["credential"]),
         attrs = params |> settings() |> Map.merge(credential),
         {:ok, _account, version} <-
           ProviderAccounts.version(scope, account_id, attrs, validate_credential?: false) do
      {:ok, %{id: account_id, version: version.version}}
    end
  end

  @doc """
  Retires the account (domain `ProviderAccountRetirement`). While missions use it:
  `{:error, {:in_use, [%{id, name}]}}`, naming the missions.
  """
  @spec retire(Scope.t(), binary(), binary() | nil) :: {:ok, map()} | {:error, term()}
  def retire(%Scope{} = scope, account_id, reason) do
    case ProviderAccountRetirement.retire(scope, account_id, reason || "Removed in the console") do
      {:ok, account} ->
        {:ok, %{id: account.provider_account_id, state: account.lifecycle_state}}

      {:error, {:in_use, uses}} ->
        names =
          scope.organization_id
          |> Missions.list_missions()
          |> Map.new(&{&1.mission_id, &1.display_name})

        missions =
          uses
          |> Enum.map(& &1.mission_id)
          |> Enum.uniq()
          |> Enum.map(&%{id: &1, name: Map.get(names, &1)})

        {:error, {:in_use, missions}}

      {:error, reason} ->
        {:error, reason}
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

  defp settings(params) do
    settings = params["settings"] || %{}

    [:base_url, :environment_ref, :region_ref]
    |> Enum.flat_map(fn key ->
      case Map.fetch(settings, Atom.to_string(key)) do
        {:ok, value} -> [{key, value}]
        :error -> []
      end
    end)
    |> Map.new()
  end

  # The name lives on the account, which the domain can't rename yet; refuse rather than ignore.
  defp no_rename(nil), do: :ok

  defp no_rename(_name),
    do: {:error, {:invalid_params, %{"name" => "Renaming an account isn't supported yet."}}}

  defp maybe_credential(_scope, _account_id, nil), do: {:ok, %{}}

  defp maybe_credential(scope, account_id, credential) do
    with {:ok, ref} <- register_credential(scope, account_id, credential),
         do: {:ok, %{credential_ref: ref}}
  end

  defp register_credential(scope, account_id, %{"backend" => backend, "key" => key})
       when is_map_key(@backends, backend) and is_binary(key) and key != "" do
    ref = Cadence.Ids.new("provider_credential")

    with :ok <- backend_allowed(@backends[backend]),
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

  defp provider_type(key) do
    case Enum.find(MissionProvider.provider_types(), &(to_string(&1) == key)) do
      nil -> {:error, {:invalid_params, %{"provider_key" => "is not a known adapter"}}}
      type -> {:ok, type}
    end
  end
end
