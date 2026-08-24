defmodule CadenceWeb.AdminOrganizationShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Auth.ServiceIdentity
  alias Phoenix.LiveView.JS

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    case Cadence.Organizations.fetch_organization(org_id) do
      {:ok, organization} ->
        members = Cadence.Accounts.list_organization_members(org_id)
        invitations = Cadence.Accounts.list_pending_invitations(org_id)
        service_identities = Cadence.Auth.list_service_identities(org_id)

        {:ok,
         socket
         |> assign(:page_title, organization.display_name)
         |> assign(:nav_item, :admin_organizations)
         |> assign(:organization_id, organization.organization_id)
         |> assign(:organization, organization_dto(organization))
         |> assign(:navigation, navigation_dto(organization))
         |> assign(:members, Enum.map(members, &member_dto/1))
         |> assign(:invitations, Enum.map(invitations, &invitation_dto/1))
         |> assign(:service_identities, Enum.map(service_identities, &service_identity_dto/1))
         |> assign(:issued_service_token, nil)
         |> assign(:service_identity_form, service_identity_form_dto(%{}))}

      {:error, :organization_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Organization not found.")
         |> push_navigate(to: ~p"/admin/organizations")}
    end
  end

  @impl true
  def handle_event("issue-service-identity", %{"service_identity" => params}, socket) do
    case service_identity_attrs(socket.assigns.organization_id, params) do
      {:ok, attrs} ->
        service_identity = ServiceIdentity.new(attrs)

        case Cadence.Auth.issue_service_identity(service_identity) do
          {:ok, %{service_identity: issued_identity, api_token: api_token}} ->
            service_identities =
              Cadence.Auth.list_service_identities(socket.assigns.organization_id)

            {:noreply,
             socket
             |> assign(:service_identities, Enum.map(service_identities, &service_identity_dto/1))
             |> assign(
               :issued_service_token,
               issued_service_token_dto(issued_identity, api_token)
             )
             |> assign(:service_identity_form, service_identity_form_dto(%{}))
             |> put_flash(:info, "Service identity created. Copy its token now.")}

          {:error, %Ecto.Changeset{}} ->
            {:noreply, put_flash(socket, :error, "That service identity ID is already in use.")}

          {:error, _reason} ->
            {:noreply,
             put_flash(socket, :error, "Cadence could not create the service identity.")}
        end

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:service_identity_form, service_identity_form_dto(params))
         |> put_flash(:error, message)}
    end
  end

  def handle_event("dismiss-service-token", _params, socket) do
    {:noreply, assign(socket, :issued_service_token, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="admin-organization-show-page">
        <.vue
          id="admin-organization-show-component"
          v-component="AdminOrganizationShow"
          organization={@organization}
          navigation={@navigation}
          members={@members}
          invitations={@invitations}
          service_identities={@service_identities}
          service_identity_form={@service_identity_form}
          issued_service_token={@issued_service_token}
          v-on:issue-service-identity={JS.push("issue-service-identity")}
          v-on:dismiss-service-token={JS.push("dismiss-service-token")}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp organization_dto(organization) do
    %{
      organization_id: organization.organization_id,
      display_name: organization.display_name,
      slug: organization.slug
    }
  end

  defp navigation_dto(organization) do
    %{
      platform_admin_href: ~p"/admin",
      organizations_href: ~p"/admin/organizations",
      invite_href: ~p"/admin/organizations/#{organization.organization_id}/invite",
      open_organization_action: ~p"/session/organization"
    }
  end

  defp member_dto(%{membership: membership, user: user}) do
    %{
      id: "organization-member-#{membership.organization_membership_id}",
      display_name: user.display_name,
      email: user.email,
      role: Atom.to_string(membership.role),
      role_label: Phoenix.Naming.humanize(membership.role)
    }
  end

  defp invitation_dto(invitation) do
    %{
      id: "organization-invitation-#{invitation.organization_invitation_id}",
      invitation_id: invitation.organization_invitation_id,
      email: invitation.email,
      role: Atom.to_string(invitation.membership_role),
      role_label: Phoenix.Naming.humanize(invitation.membership_role),
      grant_platform_admin: invitation.grant_platform_admin,
      expires_on: Calendar.strftime(invitation.expires_at, "%Y-%m-%d")
    }
  end

  defp service_identity_dto(service_identity) do
    %{
      id: "service-identity-#{service_identity.service_identity_id}",
      service_identity_id: service_identity.service_identity_id,
      display_name: service_identity.display_name,
      token_hint: service_identity.token_hint,
      lifecycle_state: Atom.to_string(service_identity.lifecycle_state),
      lifecycle_state_label: Phoenix.Naming.humanize(service_identity.lifecycle_state)
    }
  end

  defp issued_service_token_dto(service_identity, api_token) do
    %{
      service_identity_id: service_identity.service_identity_id,
      display_name: service_identity.display_name,
      api_token: api_token
    }
  end

  defp service_identity_form_dto(params) do
    %{
      display_name: string_param(params, "display_name"),
      service_identity_id: string_param(params, "service_identity_id")
    }
  end

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
