defmodule Cadence.Management.DataSources.Credentials.ExternalSecretBackend do
  @moduledoc "Compatibility adapter for the shared Req-backed secret backend."

  @behaviour Cadence.Management.DataSources.Credentials.SecretBackend

  alias Cadence.DataSources.ResolvedSourceCredential
  alias Cadence.Secrets.ExternalBackend

  # Keep the deployed secret-manager endpoint stable while internal ownership moves.
  @credential_material_path "/v1/dashboard-source-credentials/material"

  @impl true
  def fetch_material(%ResolvedSourceCredential{} = credential, opts \\ []) do
    opts = Keyword.put_new(opts, :secret_manager_path, @credential_material_path)

    case ExternalBackend.resolve(credential, opts) do
      {:ok, %{material: material}} -> {:ok, material}
      {:error, reason} -> {:error, reason}
    end
  end
end
