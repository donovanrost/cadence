defmodule Cadence.Applications.OrganizationAdminProviders.AdminOrganizationInvite do
  @moduledoc "Compatibility destination and delegate to persisted invitation and delivery outcomes."
  alias Cadence.Administration.OrganizationInvitations
  alias Cadence.Organizations

  def props(organization_id) when is_binary(organization_id) do
    with {:ok, _} <- Organizations.fetch_organization(organization_id),
         do: {:ok, %{organization_id: organization_id}}
  end

  def form(params),
    do: %{
      email: Map.get(params, "email", ""),
      display_name: Map.get(params, "display_name", ""),
      membership_role: Map.get(params, "membership_role", "member"),
      grant_platform_admin: Map.get(params, "grant_platform_admin") in [true, "true"]
    }

  def create(scope, organization_id, params) do
    input = %{
      "email" => Map.get(params, "email", ""),
      "display_name" => Map.get(params, "display_name", ""),
      "membership_role" => Map.get(params, "membership_role", "member"),
      "grant_platform_admin" => Map.get(params, "grant_platform_admin") in [true, "true"]
    }

    case OrganizationInvitations.create(scope, organization_id, input) do
      {:ok, receipt} ->
        {:ok,
         %{
           navigate:
             "/admin/organizations/#{URI.encode(organization_id, &URI.char_unreserved?/1)}",
           invitation: receipt
         }}

      {:invalid, errors} ->
        {:error, errors}

      result ->
        result
    end
  end
end
