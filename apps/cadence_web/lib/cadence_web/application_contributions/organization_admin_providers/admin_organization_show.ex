defmodule CadenceWeb.ApplicationContributions.OrganizationAdminProviders.AdminOrganizationShow do
  @moduledoc false

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Auth.ServiceIdentity

  @spec props(binary()) :: map() | {:error, term()}
  def props(org_id) when is_binary(org_id) do
    with {:ok, organization} <- Cadence.Organizations.fetch_organization(org_id) do
      {:ok,
       %{
         organization: organization_dto(organization),
         navigation: navigation_dto(organization),
         members: Cadence.Accounts.list_organization_members(org_id) |> Enum.map(&member_dto/1),
         invitations:
           Cadence.Accounts.list_pending_invitations(org_id) |> Enum.map(&invitation_dto/1),
         service_identities:
           Cadence.Auth.list_service_identities(org_id) |> Enum.map(&service_identity_dto/1),
         service_identity_form: service_identity_form_dto(%{}),
         issued_service_token: nil
       }}
    else
      {:error, _reason} -> {:error, :organization_not_found}
    end
  end

  @spec issue_service_identity(binary(), map()) :: {:ok, map()} | {:error, term()}
  def issue_service_identity(org_id, params) when is_binary(org_id) and is_map(params) do
    with {:ok, attrs} <- service_identity_attrs(org_id, params),
         {:ok, %{service_identity: identity, api_token: api_token}} <-
           Cadence.Auth.issue_service_identity(ServiceIdentity.new(attrs)) do
      {:ok,
       %{
         service_identities:
           Cadence.Auth.list_service_identities(org_id) |> Enum.map(&service_identity_dto/1),
         issued_service_token: issued_service_token_dto(identity, api_token),
         service_identity_form: service_identity_form_dto(%{})
       }}
    end
  end

  defp organization_dto(organization),
    do: %{
      organization_id: organization.organization_id,
      display_name: organization.display_name,
      slug: organization.slug
    }

  defp navigation_dto(organization),
    do: %{
      platform_admin_href: ~p"/admin",
      organizations_href: ~p"/admin/organizations",
      invite_href: ~p"/admin/organizations/#{organization.organization_id}/invite",
      open_organization_action: ~p"/session/organization"
    }

  defp member_dto(%{membership: membership, user: user}),
    do: %{
      id: "organization-member-#{membership.organization_membership_id}",
      display_name: user.display_name,
      email: user.email,
      role: Atom.to_string(membership.role),
      role_label: Phoenix.Naming.humanize(membership.role)
    }

  defp invitation_dto(invitation),
    do: %{
      id: "organization-invitation-#{invitation.organization_invitation_id}",
      invitation_id: invitation.organization_invitation_id,
      email: invitation.email,
      role: Atom.to_string(invitation.membership_role),
      role_label: Phoenix.Naming.humanize(invitation.membership_role),
      grant_platform_admin: invitation.grant_platform_admin,
      expires_on: Calendar.strftime(invitation.expires_at, "%Y-%m-%d")
    }

  defp service_identity_dto(service_identity),
    do: %{
      id: "service-identity-#{service_identity.service_identity_id}",
      service_identity_id: service_identity.service_identity_id,
      display_name: service_identity.display_name,
      token_hint: service_identity.token_hint,
      lifecycle_state: Atom.to_string(service_identity.lifecycle_state),
      lifecycle_state_label: Phoenix.Naming.humanize(service_identity.lifecycle_state)
    }

  defp issued_service_token_dto(service_identity, api_token),
    do: %{
      service_identity_id: service_identity.service_identity_id,
      display_name: service_identity.display_name,
      api_token: api_token
    }

  defp service_identity_form_dto(params),
    do: %{
      display_name: string_param(params, "display_name"),
      service_identity_id: string_param(params, "service_identity_id")
    }

  defp string_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp service_identity_attrs(organization_id, params) do
    case normalize_param(params["display_name"]) do
      nil ->
        {:error, "A service identity display name is required."}

      display_name ->
        attrs = %{
          organization_id: organization_id,
          display_name: display_name,
          capabilities: [:organization_admin],
          lifecycle_state: :active,
          metadata: %{}
        }

        attrs =
          case normalize_param(params["service_identity_id"]) do
            nil -> attrs
            service_identity_id -> Map.put(attrs, :service_identity_id, service_identity_id)
          end

        {:ok, attrs}
    end
  end

  defp normalize_param(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_param(_value), do: nil
end
