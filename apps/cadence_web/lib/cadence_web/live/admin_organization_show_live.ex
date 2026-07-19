defmodule CadenceWeb.AdminOrganizationShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    case Cadence.Organizations.fetch_organization(org_id) do
      {:ok, organization} ->
        members = Cadence.list_organization_members(org_id)
        invitations = Cadence.list_pending_invitations(org_id)

        {:ok,
         socket
         |> assign(:page_title, organization.display_name)
         |> assign(:nav_item, :admin_organizations)
         |> assign(:organization, organization)
         |> assign(:members, members)
         |> assign(:invitations, invitations)}

      {:error, :organization_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Organization not found.")
         |> push_navigate(to: ~p"/admin/organizations")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title={@organization.display_name}
        subtitle={@organization.slug}
        breadcrumbs={[
          {"Platform Admin", ~p"/admin"},
          {"Organizations", ~p"/admin/organizations"},
          {@organization.display_name, nil}
        ]}
      >
        <:actions>
          <.button navigate={~p"/admin/organizations/#{@organization.organization_id}/invite"}>
            Invite User
          </.button>
        </:actions>
      </.page_header>

      <.members_section members={@members} />
      <.invitations_section invitations={@invitations} />
    </div>
    """
  end

  attr :members, :list, required: true

  defp members_section(assigns) do
    ~H"""
    <div>
      <h2 class="text-lg font-bold mb-3">Members</h2>
      <%= if @members == [] do %>
        <.empty_state title="No members yet." description="Invite someone to get started." />
      <% else %>
        <.card padding={:none}>
          <.table id="org-members-table" rows={@members} row_accent={false}>
            <:col :let={member} label="User">
              <p class="font-semibold">{member.user.display_name}</p>
              <p class="text-sm text-base-content/70">{member.user.email}</p>
            </:col>
            <:col :let={member} label="Role">
              <span class="font-mono text-[0.65rem] uppercase tracking-wide bg-base-300 px-2 py-1">
                {Phoenix.Naming.humanize(member.membership.role)}
              </span>
            </:col>
          </.table>
        </.card>
      <% end %>
    </div>
    """
  end

  attr :invitations, :list, required: true

  defp invitations_section(assigns) do
    ~H"""
    <div>
      <h2 class="text-lg font-bold mb-3">Pending Invitations</h2>
      <%= if @invitations == [] do %>
        <.empty_state compact title="No pending invitations." />
      <% else %>
        <div class="space-y-2">
          <.card :for={inv <- @invitations} padding={:none}>
            <div class="flex items-center justify-between p-3">
              <div>
                <p class="font-semibold">{inv.email}</p>
                <p class="text-sm text-base-content/60">
                  Role: {Phoenix.Naming.humanize(inv.membership_role)}
                  <%= if inv.grant_platform_admin do %>
                    &middot; Platform Admin
                  <% end %>
                </p>
              </div>
              <p class="text-xs text-base-content/60">
                Expires {Calendar.strftime(inv.expires_at, "%Y-%m-%d")}
              </p>
            </div>
          </.card>
        </div>
      <% end %>
    </div>
    """
  end
end
