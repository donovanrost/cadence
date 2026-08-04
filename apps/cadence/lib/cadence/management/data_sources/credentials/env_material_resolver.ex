defmodule Cadence.Management.DataSources.Credentials.EnvMaterialResolver do
  @moduledoc """
  Compatibility resolver for env-backed data-source credential material.

  New deployments should configure `SecretMaterialResolver` with
  `EnvSecretBackend`. This module remains a stable resolver entry point for
  tests, local tooling, and older configuration.
  """

  alias Cadence.DataSources.ResolvedSourceCredential
  alias Cadence.Management.DataSources.Credentials.{EnvSecretBackend, SecretMaterialResolver}

  @spec resolve(ResolvedSourceCredential.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def resolve(%ResolvedSourceCredential{} = credential, opts \\ []) when is_list(opts) do
    opts = Keyword.put(opts, :credential_secret_backend, {EnvSecretBackend, :fetch_material})
    SecretMaterialResolver.resolve(credential, opts)
  end
end
