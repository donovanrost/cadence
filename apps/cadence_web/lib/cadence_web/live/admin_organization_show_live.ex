defmodule CadenceWeb.AdminOrganizationShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"org_id" => org_id}, _session, socket) do
    case Cadence.fetch_organization(org_id) do
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
      <div class="flex items-center justify-between">
        <div>
          <.link navigate={~p"/admin/organizations"} class="text-sm text-primary hover:underline">
            &larr; Organizations
          </.link>
          <h1 class="text-2xl font-bold text-base-content mt-1">{@organization.display_name}</h1>
          <p class="text-sm text-base-content/60 font-mono">{@organization.slug}</p>
        </div>
        <.link
          navigate={~p"/admin/organizations/#{@organization.organization_id}/invite"}
          class="btn btn-primary btn-sm"
        >
          Invite User
        </.link>
      </div>

      <div>
        <h2 class="text-lg font-bold mb-3">Members</h2>
        <%= if @members == [] do %>
          <div class="card bg-base-200">
            <div class="card-body p-6 text-center">
              <p class="text-base-content/50">No members yet. Invite someone to get started.</p>
            </div>
          </div>
        <% else %>
          <div class="card bg-base-200 overflow-hidden">
            <table class="w-full">
              <thead>
                <tr class="border-b border-base-300">
                  <th class="hud-label text-left p-3">User</th>
                  <th class="hud-label text-left p-3">Role</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={member <- @members} class="border-b border-base-300 last:border-0">
                  <td class="p-3">
                    <p class="font-semibold">{member.user.display_name}</p>
                    <p class="text-sm text-base-content/60">{member.user.email}</p>
                  </td>
                  <td class="p-3">
                    <span class="badge badge-sm">
                      {Phoenix.Naming.humanize(member.membership.role)}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <div>
        <h2 class="text-lg font-bold mb-3">Pending Invitations</h2>
        <%= if @invitations == [] do %>
          <p class="text-sm text-base-content/50">No pending invitations.</p>
        <% else %>
          <div class="space-y-2">
            <div :for={inv <- @invitations} class="card bg-base-200">
              <div class="card-body p-3 flex-row items-center justify-between">
                <div>
                  <p class="font-semibold">{inv.email}</p>
                  <p class="text-sm text-base-content/60">
                    Role: {Phoenix.Naming.humanize(inv.membership_role)}
                    <%= if inv.grant_platform_admin do %>
                      &middot; Platform Admin
                    <% end %>
                  </p>
                </div>
                <p class="text-xs text-base-content/40">
                  Expires {Calendar.strftime(inv.expires_at, "%Y-%m-%d")}
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
