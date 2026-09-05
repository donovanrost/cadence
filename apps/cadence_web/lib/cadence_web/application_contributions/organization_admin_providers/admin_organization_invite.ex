defmodule CadenceWeb.ApplicationContributions.OrganizationAdminProviders.AdminOrganizationInvite do
  @moduledoc false

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  @spec props(binary()) :: map() | {:error, term()}
  def props(org_id) when is_binary(org_id) do
    case Cadence.Organizations.fetch_organization(org_id) do
      {:ok, organization} ->
        {:ok, %{page: page_dto(organization), form: form_dto(default_invite_params())}}

      {:error, _reason} ->
        {:error, :organization_not_found}
    end
  end

  @spec form(map()) :: map()
  def form(params) when is_map(params), do: form_dto(params)

  @spec create(Cadence.Auth.Scope.t(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def create(%Cadence.Auth.Scope{} = scope, org_id, params)
      when is_binary(org_id) and is_map(params) do
    result =
      Cadence.Accounts.establish_organization_access(params["email"], org_id,
        membership_role: normalize_role(params["membership_role"]),
        grant_platform_admin: params["grant_platform_admin"] in [true, "true"],
        invited_by_user_id: scope.user.user_id,
        display_name: params["display_name"],
        force_invitation: true
      )

    case result do
      {:ok, %{mode: :granted}} ->
        {:ok, %{navigate: ~p"/admin/organizations/#{org_id}"}}

      {:ok, %{mode: :invited, invitation: invitation, invitation_token: token}} ->
        with {:ok, organization} <- Cadence.Organizations.fetch_organization(org_id) do
          CadenceWeb.UserNotifier.deliver_organization_invitation(
            invitation,
            organization,
            invitation_url(token)
          )

          {:ok, %{navigate: ~p"/admin/organizations/#{org_id}"}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp page_dto(organization) do
    %{
      title: "Invite User",
      subtitle:
        "Invite a user to #{organization.display_name}. The invited user will see a notification and must accept the invitation to gain access.",
      breadcrumbs: [
        %{label: "Platform Admin", href: ~p"/admin"},
        %{label: "Organizations", href: ~p"/admin/organizations"},
        %{
          label: organization.display_name,
          href: ~p"/admin/organizations/#{organization.organization_id}"
        },
        %{label: "Invite User", href: nil}
      ],
      role_options: [
        %{label: "Organization Admin", value: "organization_admin"},
        %{label: "Member", value: "member"}
      ],
      submit_label: "Send invitation",
      cancel_label: "Cancel",
      cancel_href: ~p"/admin/organizations/#{organization.organization_id}"
    }
  end

  defp form_dto(params),
    do: %{
      email: string_param(params, "email"),
      display_name: string_param(params, "display_name"),
      membership_role: string_param(params, "membership_role", "member"),
      grant_platform_admin: boolean_param(params, "grant_platform_admin")
    }

  defp default_invite_params,
    do: %{
      "email" => "",
      "display_name" => "",
      "membership_role" => "member",
      "grant_platform_admin" => "false"
    }

  defp string_param(params, key, default \\ "") when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> default
    end
  end

  defp boolean_param(params, key) when is_map(params), do: Map.get(params, key) in [true, "true"]
  defp normalize_role("organization_admin"), do: :organization_admin
  defp normalize_role(_other), do: :member
  defp invitation_url(token), do: CadenceWeb.Endpoint.url() <> ~p"/invitations/#{token}"
end
