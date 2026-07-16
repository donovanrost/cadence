defmodule Cadence.GroundNetworks.CredentialResolver do
  @moduledoc "Provider control-plane adapter for the shared credential registry."

  alias Cadence.GroundNetworks.ProviderCredentials
  alias Cadence.Secrets.{EnvBackend, Resolver}

  @type resolver :: (binary() -> {:ok, binary()} | {:error, term()})

  @spec resolver(keyword()) :: resolver()
  def resolver(opts \\ []) do
    case Keyword.get(opts, :credential_resolver) do
      resolver when is_function(resolver, 1) -> resolver
      _other -> &resolve(&1, opts)
    end
  end

  @spec resolve(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def resolve(reference, opts \\ []) when is_binary(reference) and is_list(opts) do
    case ProviderCredentials.resolve_registered(reference, opts) do
      {:ok, resolved} -> provider_material(resolved.material)
      {:error, :provider_credential_not_found} -> resolve_local_reference(reference, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_local_reference("env://" <> variable = reference, opts) when variable != "" do
    if local_credentials_enabled?(opts) do
      descriptor = %{
        reference: reference,
        registry_version: 1,
        backend_key: variable
      }

      opts =
        opts
        |> Keyword.put(:secret_backend, EnvBackend)
        |> Keyword.put(:allow_env_secret_backend?, true)

      case Resolver.resolve(descriptor, opts) do
        {:ok, resolved} -> provider_material(resolved.material)
        {:error, _reason} -> {:error, {:credential_reference_not_found, reference}}
      end
    else
      {:error, {:unsupported_credential_reference, reference}}
    end
  end

  defp resolve_local_reference("config://" <> name = reference, opts) when name != "" do
    if local_credentials_enabled?(opts) do
      credentials = Application.get_env(:cadence, :ground_network_credentials, %{})

      backend = fn _descriptor, _backend_opts -> configured_material(credentials, name) end

      case Resolver.resolve(%{reference: reference, registry_version: 1},
             secret_backend: backend
           ) do
        {:ok, resolved} -> provider_material(resolved.material)
        {:error, _reason} -> {:error, {:credential_reference_not_found, reference}}
      end
    else
      {:error, {:unsupported_credential_reference, reference}}
    end
  end

  defp resolve_local_reference(reference, _opts),
    do: {:error, {:unsupported_credential_reference, reference}}

  defp provider_material(material) do
    [:value, :bearer_token, :token, :api_key]
    |> Enum.find_value(fn key -> Map.get(material, key) end)
    |> case do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :unsupported_provider_credential_material}
    end
  end

  defp configured_material(credentials, name) do
    case Map.get(credentials, name) do
      value when is_binary(value) and value != "" -> {:ok, %{value: value}}
      _missing -> {:error, :credential_reference_not_found}
    end
  end

  defp local_credentials_enabled?(opts) do
    Keyword.get(opts, :allow_local_provider_credentials?, false) ||
      :cadence
      |> Application.get_env(:provider_local_credentials, [])
      |> Keyword.get(:enabled, false)
  end
end
