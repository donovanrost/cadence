defmodule Cadence.Applications.OrganizationAdminProviders.AdminOrganizationShow do
  @moduledoc "Compatibility destination and delegate to the authorized issuance effect."
  alias Cadence.Administration.ServiceIdentityIssuance
  alias Cadence.Organizations

  def props(organization_id) when is_binary(organization_id) do
    with {:ok, _} <- Organizations.fetch_organization(organization_id),
         do: {:ok, %{organization_id: organization_id}}
  end

  def issue_service_identity(scope, organization_id, params) do
    input = %{
      "display_name" => Map.get(params, "display_name", ""),
      "service_identity_id" => Map.get(params, "service_identity_id", "")
    }

    case ServiceIdentityIssuance.issue(scope, organization_id, input) do
      {:ok, identity} ->
        {:ok,
         %{
           issued_service_token: %{
             service_identity_id: identity["id"],
             display_name: identity["name"],
             api_token: identity["api_token"]
           },
           service_identity_form: %{display_name: "", service_identity_id: ""}
         }}

      {:invalid, errors} ->
        {:error, errors}

      result ->
        result
    end
  end
end
