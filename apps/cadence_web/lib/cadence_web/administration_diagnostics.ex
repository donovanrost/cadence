defmodule CadenceWeb.AdministrationDiagnostics do
  @moduledoc "Host composition of compiled, independently contained diagnostic contributions."

  alias Cadence.Auth.Scope
  alias Cadence.Reads.Dashboards.RuntimeDiagnostics

  @contributions [{"dashboards.runtime-diagnostics", RuntimeDiagnostics}]

  def load(%Scope{} = scope, params) do
    if Scope.admin_mode?(scope) do
      Enum.map(@contributions, fn {id, provider} ->
        load_contribution(id, provider, scope, params)
      end)
    else
      []
    end
  end

  def load(_scope, _params), do: []

  defp load_contribution(id, provider, scope, params) do
    case provider.contribution(scope, params) do
      {:ok, %{id: ^id, version: 1, status: "ready"} = snapshot} -> snapshot
      _unavailable -> unavailable(id)
    end
  rescue
    # Domain diagnostics may be unavailable; the host shell must remain usable.
    _error -> unavailable(id)
  end

  defp unavailable(id), do: %{id: id, version: 1, status: "unavailable"}
end
