defmodule CadenceWeb.AdministrationPage do
  @moduledoc "Host-selected core administration pages; authorization remains in scoped reads."
  alias Cadence.Auth.Scope
  alias Cadence.Reads.Administration.OrganizationHome

  def load(%Scope{} = scope, %{route: "/"}) do
    envelope = %{version: 1, page: "organization_home", organization_id: scope.organization_id}

    case read(scope) do
      {:ok, data} -> Map.merge(envelope, %{status: "ready", data: data})
      _ -> Map.put(envelope, :status, "unavailable")
    end
  end

  def load(_, _), do: nil

  defp read(scope) do
    OrganizationHome.load(scope)
  rescue
    _ -> {:error, :unavailable}
  end
end
