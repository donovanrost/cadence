defmodule CadenceWeb.AdminLive.OrganizationMembers do
  @moduledoc """
  LiveView for managing organization members (admin only).

  Allows system admins to:
  - View all members of an organization
  - Add users to the organization
  - Remove users from the organization
  - Change member roles
  """

  use CadenceWeb, :live_view

  alias Cadence.{Organizations, Accounts}

  @impl true
  def mount(%{"id" => org_id}, _session, socket) do
    organization = Organizations.get_organization!(org_id)
    members = load_members(org_id)
    all_users = Accounts.list_users()

    socket =
      socket
      |> assign(:organization, organization)
      |> assign(:members, members)
      |> assign(:all_users, all_users)
      |> assign(:selected_user_id, nil)
      |> assign(:selected_role, "admin")

    {:ok, socket}
  end

  @impl true
  def handle_event("add_member", %{"user_id" => user_id, "role" => role}, socket) do
    case Organizations.create_organization_membership(%{
           user_id: user_id,
           organization_id: socket.assigns.organization.id,
           role: role
         }) do
      {:ok, _membership} ->
        members = load_members(socket.assigns.organization.id)

        socket =
          socket
          |> assign(:members, members)
          |> put_flash(:info, "Member added successfully")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to add member: #{inspect(changeset.errors)}")}
    end
  end

  def handle_event("remove_member", %{"membership_id" => membership_id}, socket) do
    membership = Organizations.get_organization_membership!(membership_id)

    case Organizations.delete_organization_membership(membership) do
      {:ok, _} ->
        members = load_members(socket.assigns.organization.id)

        socket =
          socket
          |> assign(:members, members)
          |> put_flash(:info, "Member removed successfully")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove member")}
    end
  end

  def handle_event("change_role", %{"membership_id" => membership_id, "role" => role}, socket) do
    membership = Organizations.get_organization_membership!(membership_id)

    case Organizations.update_organization_membership(membership, %{role: role}) do
      {:ok, _} ->
        members = load_members(socket.assigns.organization.id)

        socket =
          socket
          |> assign(:members, members)
          |> put_flash(:info, "Role updated successfully")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update role")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <div class="mb-6">
        <h1 class="text-3xl font-bold">Organization Members</h1>
        <p class="text-gray-600 mt-2">{@organization.name}</p>
      </div>
      
    <!-- Add Member Form -->
      <div class="bg-white shadow rounded-lg p-6 mb-6">
        <h2 class="text-xl font-semibold mb-4">Add Member</h2>
        <form phx-submit="add_member" class="flex gap-4">
          <div class="flex-1">
            <label class="block text-sm font-medium text-gray-700 mb-2">User</label>
            <select name="user_id" class="w-full rounded-md border-gray-300" required>
              <option value="">Select user...</option>
              <%= for user <- available_users(@all_users, @members) do %>
                <option value={user.id}>{user.email}</option>
              <% end %>
            </select>
          </div>
          <div class="w-48">
            <label class="block text-sm font-medium text-gray-700 mb-2">Role</label>
            <select name="role" class="w-full rounded-md border-gray-300">
              <option value="admin">Admin</option>
              <option value="member">Member</option>
              <option value="owner">Owner</option>
            </select>
          </div>
          <div class="flex items-end">
            <button
              type="submit"
              class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700"
            >
              Add Member
            </button>
          </div>
        </form>
      </div>
      
    <!-- Members List -->
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                User
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Role
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Joined
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for member <- @members do %>
              <tr>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="text-sm font-medium text-gray-900">{member.user.email}</div>
                  <%= if member.user.system_admin do %>
                    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-purple-100 text-purple-800">
                      System Admin
                    </span>
                  <% end %>
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <form phx-change="change_role" class="inline">
                    <input type="hidden" name="membership_id" value={member.id} />
                    <select
                      name="role"
                      class="rounded-md border-gray-300 text-sm"
                      value={member.role}
                    >
                      <option value="owner">Owner</option>
                      <option value="admin">Admin</option>
                      <option value="member">Member</option>
                    </select>
                  </form>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {format_date(member.inserted_at)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <button
                    phx-click="remove_member"
                    phx-value-membership_id={member.id}
                    data-confirm="Are you sure you want to remove this member?"
                    class="text-red-600 hover:text-red-900"
                  >
                    Remove
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>

        <%= if Enum.empty?(@members) do %>
          <div class="text-center py-12 text-gray-500">
            No members yet. Add the first member above.
          </div>
        <% end %>
      </div>

      <div class="mt-6">
        <.link
          navigate={~p"/admin/organizations/#{@organization}"}
          class="text-blue-600 hover:text-blue-800"
        >
          ← Back to Organization
        </.link>
      </div>
    </div>
    """
  end

  ## Private Functions

  defp load_members(org_id) do
    Organizations.list_organization_memberships_with_users(org_id)
  end

  defp available_users(all_users, members) do
    member_user_ids = Enum.map(members, & &1.user_id) |> MapSet.new()
    Enum.reject(all_users, fn user -> MapSet.member?(member_user_ids, user.id) end)
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d")
  end
end
