defmodule Cadence.Dashboards.SourceCredentials.SecretMaterialResolver do
  @moduledoc """
  Resolves source credential material through a configured secret backend.

  This module is the production-shaped material resolver for dashboard source
  credentials. It keeps the dashboard contract stable while allowing deployments
  to swap the secret backend behind the resolver.
  """

  alias Cadence.Dashboards.ResolvedSourceCredential
  alias Cadence.Dashboards.SourceCredentials.MaterialPolicy

  @spec resolve(ResolvedSourceCredential.t(), keyword()) ::
          {:ok, map()}
          | {:error,
             :credential_secret_backend_not_configured
             | {:unsupported_credential_secret_backend, term()}
             | term()}
  def resolve(%ResolvedSourceCredential{} = credential, opts \\ []) when is_list(opts) do
    case secret_backend(opts) do
      nil ->
        {:error, :credential_secret_backend_not_configured}

      backend ->
        credential
        |> call_secret_backend(opts, backend)
        |> normalize_backend_result()
    end
  end

  @spec configured?() :: boolean()
  def configured? do
    :cadence
    |> Application.get_env(:dashboard_source_credentials, [])
    |> Keyword.has_key?(:secret_backend)
  end

  @spec secret_backend(keyword()) :: term()
  def secret_backend(opts) do
    Keyword.get(opts, :credential_secret_backend) ||
      Keyword.get(opts, :secret_backend) ||
      :cadence
      |> Application.get_env(:dashboard_source_credentials, [])
      |> Keyword.get(:secret_backend)
  end

  defp call_secret_backend(%ResolvedSourceCredential{} = credential, opts, backend)
       when is_function(backend, 2) do
    backend.(credential, opts)
  end

  defp call_secret_backend(%ResolvedSourceCredential{} = credential, _opts, backend)
       when is_function(backend, 1) do
    backend.(credential)
  end

  defp call_secret_backend(%ResolvedSourceCredential{} = credential, opts, {module, function})
       when is_atom(module) and is_atom(function) do
    apply(module, function, [credential, opts])
  end

  defp call_secret_backend(
         %ResolvedSourceCredential{} = credential,
         opts,
         {module, function, extra_args}
       )
       when is_atom(module) and is_atom(function) and is_list(extra_args) do
    apply(module, function, [credential, opts | extra_args])
  end

  defp call_secret_backend(_credential, _opts, backend) do
    {:error, {:unsupported_credential_secret_backend, backend}}
  end

  defp normalize_backend_result({:ok, material}) when is_map(material) do
    MaterialPolicy.normalize_and_validate(material)
  end

  defp normalize_backend_result(material) when is_map(material) do
    MaterialPolicy.normalize_and_validate(material)
  end

  defp normalize_backend_result({:error, reason}), do: {:error, reason}
  defp normalize_backend_result(other), do: {:error, other}
end
