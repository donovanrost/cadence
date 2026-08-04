defmodule Cadence.Management.DataSources.Credentials.EnvSecretBackend do
  @moduledoc "Compatibility adapter for the shared local environment backend."

  @behaviour Cadence.Management.DataSources.Credentials.SecretBackend

  alias Cadence.DataSources.ResolvedSourceCredential
  alias Cadence.Secrets.EnvBackend

  @impl true
  def fetch_material(%ResolvedSourceCredential{} = credential, opts \\ []) do
    opts = Keyword.put(opts, :allow_env_secret_backend?, true)

    case EnvBackend.resolve(credential, opts) do
      {:ok, %{material: material}} -> {:ok, material}
      {:error, reason} -> {:error, reason}
    end
  end
end
