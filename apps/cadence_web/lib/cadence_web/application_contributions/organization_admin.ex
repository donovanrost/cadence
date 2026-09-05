defmodule CadenceWeb.ApplicationContributions.OrganizationAdmin do
  @moduledoc "Contribution descriptor for the post-auth organization/admin federated remote."

  alias CadenceWeb.ApplicationContributions.OrganizationAdminAction
  alias CadenceWeb.ApplicationContributions.OrganizationAdminQuery

  @application_key "organization_admin"
  @remote_name "cadence_organization_admin"
  @version 1

  @surface_contracts [
    %{
      id: "organization_home",
      component: "OrganizationHome",
      query: "cadence.organization.home",
      actions: []
    },
    %{
      id: "provider_accounts",
      component: "ProviderAccountListPage",
      query: "cadence.organization.provider_accounts.list",
      actions: []
    },
    %{
      id: "provider_account_new",
      component: "ProviderAccountNew",
      query: "cadence.organization.provider_accounts.new",
      actions: ["validate_provider_account", "register_provider_account"]
    },
    %{
      id: "provider_account_show",
      component: "ProviderAccountShow",
      query: "cadence.organization.provider_account.show",
      actions: [
        "validate_provider_account",
        "rotate_provider_credential",
        "revoke_provider_credential",
        "grant_provider_account_mission",
        "revoke_provider_account_mission"
      ]
    },
    %{
      id: "notifications",
      component: "NotificationsPage",
      query: "cadence.organization.notifications",
      actions: ["accept_invitation", "mark_notification_read"]
    },
    %{
      id: "notifications_bell",
      component: "NotificationsBell",
      query: "cadence.organization.notifications_bell",
      actions: ["mark_notification_read"]
    },
    %{
      id: "admin_home",
      component: "AdminHome",
      query: "cadence.platform_admin.home",
      actions: []
    },
    %{
      id: "admin_runtime",
      component: "AdminRuntime",
      query: "cadence.platform_admin.runtime",
      actions: ["refresh_runtime", "filter_runtime_decisions"]
    },
    %{
      id: "admin_organizations",
      component: "AdminOrganizationListPage",
      query: "cadence.platform_admin.organizations",
      actions: []
    },
    %{
      id: "admin_organization_new",
      component: "AdminOrganizationNew",
      query: "cadence.platform_admin.organization.new",
      actions: ["validate_organization", "create_organization"]
    },
    %{
      id: "admin_organization_show",
      component: "AdminOrganizationShow",
      query: "cadence.platform_admin.organization.show",
      actions: ["issue_service_identity", "dismiss_service_token", "open_organization"]
    },
    %{
      id: "admin_organization_invite",
      component: "AdminOrganizationInvite",
      query: "cadence.platform_admin.organization.invite",
      actions: ["validate_invitation", "invite_organization_member"]
    }
  ]

  @host_owned_flows %{
    sign_in: "Phoenix authentication and session establishment",
    invitation_acceptance: "Phoenix validates and persists membership acceptance",
    no_organization_bootstrap: "Phoenix establishes the first organization scope",
    admin_mode_transition: "Phoenix owns admin-mode reauthentication and session transition"
  }

  @compatibility_wrappers [
    %{
      surface_id: "organization_home",
      live_view: "CadenceWeb.OrganizationHomeLive",
      component: "OrganizationHome"
    },
    %{
      surface_id: "provider_accounts",
      live_view: "CadenceWeb.ProviderAccountListLive",
      component: "ProviderAccountListPage"
    },
    %{
      surface_id: "provider_account_new",
      live_view: "CadenceWeb.ProviderAccountNewLive",
      component: "ProviderAccountNew"
    },
    %{
      surface_id: "provider_account_show",
      live_view: "CadenceWeb.ProviderAccountShowLive",
      component: "ProviderAccountShow"
    },
    %{
      surface_id: "notifications",
      live_view: "CadenceWeb.NotificationsLive",
      component: "NotificationsPage"
    },
    %{
      surface_id: "notifications_bell",
      live_view: "CadenceWeb.NotificationsBell",
      component: "NotificationsBell"
    },
    %{surface_id: "admin_home", live_view: "CadenceWeb.AdminHomeLive", component: "AdminHome"},
    %{
      surface_id: "admin_runtime",
      live_view: "CadenceWeb.AdminRuntimeLive",
      component: "AdminRuntime"
    },
    %{
      surface_id: "admin_organizations",
      live_view: "CadenceWeb.AdminOrganizationListLive",
      component: "AdminOrganizationListPage"
    },
    %{
      surface_id: "admin_organization_new",
      live_view: "CadenceWeb.AdminOrganizationNewLive",
      component: "AdminOrganizationNew"
    },
    %{
      surface_id: "admin_organization_show",
      live_view: "CadenceWeb.AdminOrganizationShowLive",
      component: "AdminOrganizationShow"
    },
    %{
      surface_id: "admin_organization_invite",
      live_view: "CadenceWeb.AdminOrganizationInviteLive",
      component: "AdminOrganizationInvite"
    }
  ]

  @doc "Identity used by the remote and its eventual central composition."
  @spec identity() :: map()
  def identity do
    %{application_key: @application_key, remote_name: @remote_name, version: @version}
  end

  @doc "Returns the complete post-auth surface contribution set."
  @spec surfaces() :: [map()]
  def surfaces, do: @surface_contracts

  @doc "Returns the Phoenix-owned transitions intentionally outside this remote."
  @spec host_owned_flows() :: map()
  def host_owned_flows, do: @host_owned_flows

  @doc "Maps each remote surface to its existing LiveView compatibility wrapper."
  @spec compatibility_wrappers() :: [map()]
  def compatibility_wrappers, do: @compatibility_wrappers

  @doc "Fetches a surface by its stable identifier."
  @spec fetch_surface(binary()) :: {:ok, map()} | {:error, :unknown_surface}
  def fetch_surface(surface_id) when is_binary(surface_id) do
    case Enum.find(@surface_contracts, &(&1.id == surface_id)) do
      nil -> {:error, :unknown_surface}
      surface -> {:ok, surface}
    end
  end

  def fetch_surface(_surface_id), do: {:error, :unknown_surface}

  @doc false
  @spec validate() :: :ok | {:error, term()}
  def validate do
    with :ok <- OrganizationAdminQuery.validate(),
         :ok <- OrganizationAdminAction.validate(),
         :ok <- validate_surface_ids(),
         :ok <- validate_queries_and_actions() do
      :ok
    end
  end

  defp validate_surface_ids do
    ids = Enum.map(@surface_contracts, & &1.id)

    if length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: {:error, :duplicate_surface_contracts}
  end

  defp validate_queries_and_actions do
    Enum.reduce_while(@surface_contracts, :ok, fn surface, :ok ->
      with {:ok, _query} <- OrganizationAdminQuery.fetch(surface.query),
           :ok <- validate_actions(surface) do
        {:cont, :ok}
      else
        _error -> {:halt, {:error, {:invalid_surface_contract, surface.id}}}
      end
    end)
  end

  defp validate_actions(%{id: surface_id, actions: actions}) do
    if Enum.all?(actions, fn action_id ->
         match?({:ok, _}, OrganizationAdminAction.fetch(surface_id, action_id))
       end) do
      :ok
    else
      {:error, :invalid_surface_actions}
    end
  end
end
