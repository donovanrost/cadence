defmodule CadenceWeb.OrganizationModulePage do
  @moduledoc "Host-selected organization page placement; domain reads remain module-owned."
  alias Cadence.Auth.Scope
  alias Cadence.Reads.Comms.ProviderAccountDirectory

  def load(%Scope{} = scope, %{route: "/provider-accounts"}) do
    envelope = %{
      id: "comms.provider-account-directory",
      slot: "organization.page",
      version: 1,
      context: %{organizationId: scope.organization_id}
    }

    case read(scope) do
      {:ok, data} -> Map.merge(envelope, %{status: "ready", data: data})
      _ -> Map.put(envelope, :status, "unavailable")
    end
  end

  def load(%Scope{}, _info), do: nil

  defp read(scope) do
    ProviderAccountDirectory.load(scope)
  rescue
    _ -> {:error, :unavailable}
  end
end
