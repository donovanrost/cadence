defmodule Cadence.Management.DataSources.Credentials.SecretMaterialResolver do
  @moduledoc "Compatibility resolver backed by the shared secret subsystem."

  alias Cadence.DataSources.ResolvedSourceCredential
  alias Cadence.Secrets.{MaterialPolicy, Resolver}
  alias Cadence.Secrets.ResolverConfiguration

  @spec resolve(ResolvedSourceCredential.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def resolve(%ResolvedSourceCredential{} = credential, opts \\ []) when is_list(opts) do
    opts =
      opts
      |> ResolverConfiguration.data_source_options()
      |> Keyword.put(:secret_backend, secret_backend(opts))
      |> Keyword.put(:allowed_material_keys, MaterialPolicy.dashboard_keys())
      |> Keyword.put(:sanitize_secret_errors?, false)

    case Resolver.resolve(credential, opts) do
      {:ok, resolved} ->
        {:ok, resolved.material}

      {:error, :secret_backend_not_configured} ->
        {:error, :credential_secret_backend_not_configured}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec configured?(keyword()) :: boolean()
  def configured?(opts \\ []), do: ResolverConfiguration.data_source_configured?(opts)

  @spec secret_backend(keyword()) :: term()
  def secret_backend(opts) do
    opts = ResolverConfiguration.data_source_options(opts)
    Keyword.get(opts, :credential_secret_backend) || Keyword.get(opts, :secret_backend)
  end
end
