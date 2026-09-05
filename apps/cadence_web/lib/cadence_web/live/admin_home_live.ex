defmodule CadenceWeb.AdminHomeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Platform Admin")
     |> assign(:nav_item, :admin_dashboard)
     |> assign(:org_count, Cadence.Organizations.count_organizations())
     |> assign(:user_count, Cadence.Accounts.count_users())
     |> assign(:presentation, presentation_dto())
     |> assign(:navigation, navigation_dto())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="admin-home-page">
        <.vue
          id="admin-home-component"
          v-component="AdminHome"
          organization_count={@org_count}
          user_count={@user_count}
          presentation={@presentation}
          navigation={@navigation}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  @doc false
  def federated_props do
    %{
      organization_count: Cadence.Organizations.count_organizations(),
      user_count: Cadence.Accounts.count_users(),
      presentation: presentation_dto(),
      navigation: navigation_dto()
    }
  end

  defp presentation_dto do
    %{
      title: "Platform Administration",
      subtitle: "Manage organizations, users, and system settings",
      organizations: %{
        title: "Organizations",
        action_label: "Manage Organizations"
      },
      users: %{
        title: "Users",
        action_label: "Manage Users",
        coming_soon: "(Coming Soon)"
      },
      runtime: %{
        title: "Runtime",
        description:
          "Inspect process-local runtime diagnostics and dashboard invalidation decisions.",
        action_label: "View Runtime"
      },
      quick_actions: %{
        title: "Quick Actions",
        create_organization_title: "Create New Organization",
        create_organization_description: "Add a new organization to the system"
      }
    }
  end

  defp navigation_dto do
    %{
      organizations_href: ~p"/admin/organizations",
      runtime_href: ~p"/admin/runtime",
      create_organization_href: ~p"/admin/organizations/new"
    }
  end
end
