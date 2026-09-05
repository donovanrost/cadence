defmodule CadenceWeb.ApplicationContributions.OrganizationAdminProviders.AdminHome do
  @moduledoc false

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  @spec props() :: map()
  def props do
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
      organizations: %{title: "Organizations", action_label: "Manage Organizations"},
      users: %{title: "Users", action_label: "Manage Users", coming_soon: "(Coming Soon)"},
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
