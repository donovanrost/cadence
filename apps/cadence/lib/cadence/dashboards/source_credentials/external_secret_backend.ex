defmodule Cadence.Dashboards.SourceCredentials.ExternalSecretBackend do
  @moduledoc "Compatibility adapter for the shared Req-backed secret backend."

  @behaviour Cadence.Dashboards.SourceCredentials.SecretBackend

  alias Cadence.Dashboards.ResolvedSourceCredential
  alias Cadence.Secrets.ExternalBackend

  @dashboard_path "/v1/dashboard-source-credentials/material"

  @impl true
  def fetch_material(%ResolvedSourceCredential{} = credential, opts \\ []) do
    opts = Keyword.put_new(opts, :secret_manager_path, @dashboard_path)

    case ExternalBackend.resolve(credential, opts) do
      {:ok, %{material: material}} -> {:ok, material}
      {:error, reason} -> {:error, reason}
    end
  end
end
