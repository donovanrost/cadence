defmodule CadenceWeb.AdminOrganizationInviteLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Phoenix.LiveView.JS

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    case Cadence.Organizations.fetch_organization(org_id) do
      {:ok, organization} ->
        {:ok,
         socket
         |> assign(:page_title, "Invite to #{organization.display_name}")
         |> assign(:nav_item, :admin_organizations)
         |> assign(:organization, organization)
         |> assign(:page, page_dto(organization))
         |> assign(:form, form_dto(default_invite_params()))}

      {:error, :organization_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Organization not found.")
         |> push_navigate(to: ~p"/admin/organizations")}
    end
  end

  @impl true
  def handle_event("validate", %{"invite" => params}, socket) do
    {:noreply, assign(socket, :form, form_dto(params))}
  end

  @impl true
  def handle_event("save", %{"invite" => params}, socket) do
    org = socket.assigns.organization
    scope = socket.assigns.current_scope

    result =
      Cadence.Accounts.establish_organization_access(
        params["email"],
        org.organization_id,
        membership_role: normalize_role(params["membership_role"]),
        grant_platform_admin: params["grant_platform_admin"] == "true",
        invited_by_user_id: scope.user.user_id,
        display_name: params["display_name"],
        force_invitation: true
      )

    case result do
      {:ok, %{mode: :granted, user: user}} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{user.email} granted access directly.")
         |> push_navigate(to: ~p"/admin/organizations/#{org.organization_id}")}

      {:ok, %{mode: :invited, invitation: invitation, invitation_token: token}} ->
        CadenceWeb.UserNotifier.deliver_organization_invitation(
          invitation,
          org,
          url(~p"/invitations/#{token}")
        )

        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{invitation.email}.")
         |> push_navigate(to: ~p"/admin/organizations/#{org.organization_id}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:form, form_dto(params))
         |> put_flash(:error, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="admin-organization-invite-component"
        v-component="AdminOrganizationInvite"
        page={@page}
        form={@form}
        v-on:validate={JS.push("validate")}
        v-on:save={JS.push("save")}
        v-ssr={false}
      />
    </Layouts.app>
    """
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

  defp form_dto(params) do
    %{
      email: string_param(params, "email"),
      display_name: string_param(params, "display_name"),
      membership_role: string_param(params, "membership_role", "member"),
      grant_platform_admin: boolean_param(params, "grant_platform_admin")
    }
  end

  defp default_invite_params do
    %{
      "email" => "",
      "display_name" => "",
      "membership_role" => "member",
      "grant_platform_admin" => "false"
    }
  end

  defp string_param(params, key, default \\ "") when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> default
    end
  end

  defp boolean_param(params, key) when is_map(params) do
    Map.get(params, key) in [true, "true"]
  end

  defp normalize_role("organization_admin"), do: :organization_admin
  defp normalize_role(_other), do: :member

  defp error_message({:invalid_param, field, :required}),
    do: "#{Phoenix.Naming.humanize(field)} is required."

  defp error_message(:invalid_organization_role), do: "Select a valid role."
  defp error_message(_reason), do: "Could not process the invitation."
end
