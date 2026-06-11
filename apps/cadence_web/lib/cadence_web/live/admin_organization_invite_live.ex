defmodule CadenceWeb.AdminOrganizationInviteLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    case Cadence.fetch_organization(org_id) do
      {:ok, organization} ->
        {:ok,
         socket
         |> assign(:page_title, "Invite to #{organization.display_name}")
         |> assign(:nav_item, :admin_organizations)
         |> assign(:organization, organization)
         |> assign(:form, to_form(default_invite_params(), as: :invite))}

      {:error, :organization_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Organization not found.")
         |> push_navigate(to: ~p"/admin/organizations")}
    end
  end

  @impl true
  def handle_event("validate", %{"invite" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :invite))}
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
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title="Invite User"
        subtitle={"Invite a user to #{@organization.display_name}. The invited user will see a notification and must accept the invitation to gain access."}
        back_label={@organization.display_name}
        back_navigate={~p"/admin/organizations/#{@organization.organization_id}"}
      />

      <.form for={@form} id="invite-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.input
          field={@form[:email]}
          type="email"
          label="Email"
          placeholder="operator@example.com"
          required
        />
        <.input
          field={@form[:display_name]}
          type="text"
          label="Display Name"
          placeholder="Flight Operator"
        />
        <.input
          field={@form[:membership_role]}
          type="select"
          label="Role"
          options={[{"Organization Admin", "organization_admin"}, {"Member", "member"}]}
        />

        <.platform_admin_checkbox form={@form} />

        <.button type="submit" size={:md}>Send Invitation</.button>
      </.form>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  # Bespoke checkbox-with-description layout; <.input> has no checkbox treatment.
  defp platform_admin_checkbox(assigns) do
    ~H"""
    <div class="fieldset mb-3">
      <label class="flex items-center gap-3 cursor-pointer">
        <input
          type="checkbox"
          name="invite[grant_platform_admin]"
          value="true"
          checked={@form[:grant_platform_admin].value == "true"}
          class="checkbox checkbox-primary checkbox-sm"
        />
        <span>
          <span class="font-semibold text-sm">Grant platform admin</span>
          <span class="block text-xs text-base-content/70">
            Platform admins can manage all organizations and system settings.
          </span>
        </span>
      </label>
    </div>
    """
  end

  defp default_invite_params do
    %{
      "email" => "",
      "display_name" => "",
      "membership_role" => "member",
      "grant_platform_admin" => "false"
    }
  end

  defp normalize_role("organization_admin"), do: :organization_admin
  defp normalize_role(_other), do: :member

  defp error_message({:invalid_param, field, :required}),
    do: "#{Phoenix.Naming.humanize(field)} is required."

  defp error_message(:invalid_organization_role), do: "Select a valid role."
  defp error_message(_reason), do: "Could not process the invitation."
end
