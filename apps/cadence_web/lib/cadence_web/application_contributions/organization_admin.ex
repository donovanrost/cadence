defmodule CadenceWeb.ApplicationContributions.OrganizationAdmin do
  @moduledoc "Contribution descriptor for the post-auth organization/admin federated remote."

  alias CadenceWeb.ApplicationContributions.OrganizationAdminAction
  alias CadenceWeb.ApplicationContributions.OrganizationAdminQuery

  alias Cadence.Applications.{
    ActionDefinition,
    ApplicationDefinition,
    CatalogContribution,
    ReleaseContribution,
    SurfaceDefinition
  }

  @application_key "organization_admin"
  @remote_name "cadence_organization_admin"
  @version 1
  @package_id "cadence.organization-admin"
  @manifest_path "/assets/application-host/organization-admin/mf-manifest.json"

  @surface_contracts [
    %{
      id: "organization_home",
      scope: :organization,
      component: "OrganizationHome",
      query: "cadence.organization.home",
      actions: []
    },
    %{
      id: "provider_accounts",
      scope: :organization,
      component: "ProviderAccountListPage",
      query: "cadence.organization.provider_accounts.list",
      actions: []
    },
    %{
      id: "provider_account_new",
      scope: :organization,
      component: "ProviderAccountNew",
      query: "cadence.organization.provider_accounts.new",
      actions: ["validate_provider_account_form", "register_provider_account"]
    },
    %{
      id: "provider_account_show",
      scope: :organization,
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
      scope: :user,
      component: "NotificationsPage",
      query: "cadence.organization.notifications",
      actions: ["accept_invitation", "mark_notification_read"]
    },
    %{
      id: "notifications_bell",
      scope: :user,
      component: "NotificationsBell",
      query: "cadence.organization.notifications_bell",
      actions: ["mark_notification_read"]
    },
    %{
      id: "admin_home",
      scope: :admin,
      component: "AdminHome",
      query: "cadence.platform_admin.home",
      actions: []
    },
    %{
      id: "admin_runtime",
      scope: :admin,
      component: "AdminRuntime",
      query: "cadence.platform_admin.runtime",
      actions: ["refresh_runtime", "filter_runtime_decisions"]
    },
    %{
      id: "admin_organizations",
      scope: :admin,
      component: "AdminOrganizationListPage",
      query: "cadence.platform_admin.organizations",
      actions: []
    },
    %{
      id: "admin_organization_new",
      scope: :admin,
      component: "AdminOrganizationNew",
      query: "cadence.platform_admin.organization.new",
      actions: ["validate_organization", "create_organization"]
    },
    %{
      id: "admin_organization_show",
      scope: :admin,
      component: "AdminOrganizationShow",
      query: "cadence.platform_admin.organization.show",
      actions: ["issue_service_identity", "dismiss_service_token", "open_organization"]
    },
    %{
      id: "admin_organization_invite",
      scope: :admin,
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
    %{
      application_key: @application_key,
      application_version: @version,
      version: @version,
      package_id: @package_id,
      package_version: @version,
      remote_name: @remote_name,
      manifest_path: @manifest_path
    }
  end

  @doc "Returns the Phoenix-owned application definition for the organization domain."
  @spec definition() :: ApplicationDefinition.t()
  def definition do
    %ApplicationDefinition{
      application_key: @application_key,
      version: @version,
      display_name: "Organization Administration",
      description:
        "Manage organization membership, providers, notifications, and administration.",
      trust: :first_party,
      availability: :available,
      installable_scopes: [:organization, :user, :admin],
      actions: action_definitions(),
      surfaces: Enum.map(@surface_contracts, &surface_definition/1)
    }
  end

  @doc "Returns the catalog contribution for the organization domain."
  @spec catalog_contributions() :: [CatalogContribution.t()]
  def catalog_contributions do
    [
      %CatalogContribution{
        definition: definition(),
        package_id: @package_id,
        package_version: @version
      }
    ]
  end

  @doc "Returns one immutable release coordinate for every organization surface."
  @spec release_contributions() :: [ReleaseContribution.t()]
  def release_contributions do
    Enum.map(@surface_contracts, fn surface ->
      %ReleaseContribution{
        application_key: @application_key,
        application_version: @version,
        surface_id: surface.id,
        surface_version: @version,
        federation: :module_federation,
        release_id: "organization-admin-v1",
        remote_name: @remote_name,
        manifest_path: @manifest_path,
        exposed_module: "./Application"
      }
    end)
  end

  @doc "Returns the complete post-auth surface contribution set."
  @spec surfaces() :: [map()]
  def surfaces, do: @surface_contracts

  @doc "Stable application identity used by the central optional registries."
  @spec application_key() :: binary()
  def application_key, do: @application_key

  @doc "Returns the executable query contributions for every declared surface."
  @spec surface_query_contributions() :: [Cadence.Applications.SurfaceQueryContribution.t()]
  def surface_query_contributions, do: OrganizationAdminQuery.contributions()

  @doc "Returns the executable action provider for this optional web contribution."
  @spec action_provider() :: module()
  def action_provider, do: OrganizationAdminAction

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
         :ok <- validate_surface_ids() do
      validate_queries_and_actions()
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

  defp action_definitions do
    @surface_contracts
    |> Enum.flat_map(& &1.actions)
    |> Enum.uniq()
    |> Enum.map(fn action_id ->
      scope = action_scope(action_id)

      %ActionDefinition{
        action_id: action_id,
        version: @version,
        scope: scope,
        input_contract: %{schema_id: "cadence.organization_admin.#{action_id}.input", version: 1},
        result_contract: %{
          schema_id: "cadence.organization_admin.#{action_id}.result",
          version: 1
        },
        required_permission: action_permission(action_id),
        effect: action_effect(action_id),
        intent: action_intent(action_id),
        execution: :immediate,
        concurrency: %{strategy: :expected_version}
      }
    end)
  end

  defp action_permission("validate_provider_account_form"), do: "manage_provider_accounts"
  defp action_permission("validate_provider_account"), do: "manage_provider_accounts"
  defp action_permission("register_provider_account"), do: "manage_provider_accounts"

  defp action_permission(action_id)
       when action_id in [
              "rotate_provider_credential",
              "revoke_provider_credential",
              "grant_provider_account_mission",
              "revoke_provider_account_mission"
            ],
       do: "manage_provider_accounts"

  defp action_permission("accept_invitation"), do: "accept_invitation"
  defp action_permission("mark_notification_read"), do: "read_notifications"

  defp action_permission(action_id)
       when action_id in ["refresh_runtime", "filter_runtime_decisions"],
       do: "view_runtime"

  defp action_permission(action_id)
       when action_id in ["validate_organization", "create_organization"],
       do: "manage_organizations"

  defp action_permission("issue_service_identity"), do: "manage_service_identities"
  defp action_permission("dismiss_service_token"), do: "dismiss_service_token"
  defp action_permission("open_organization"), do: "open_organization"
  defp action_permission("validate_invitation"), do: "manage_organizations"
  defp action_permission("invite_organization_member"), do: "manage_organizations"

  defp action_effect(action_id)
       when action_id in [
              "validate_provider_account_form",
              "refresh_runtime",
              "filter_runtime_decisions",
              "validate_organization",
              "dismiss_service_token",
              "validate_invitation"
            ],
       do: :none

  defp action_effect("accept_invitation"), do: :durable
  defp action_effect("open_organization"), do: :external
  defp action_effect("validate_provider_account"), do: :external
  defp action_effect(_action_id), do: :durable

  defp action_intent(action_id)
       when action_id in [
              "refresh_runtime",
              "filter_runtime_decisions",
              "validate_provider_account_form",
              "validate_organization",
              "validate_invitation",
              "dismiss_service_token"
            ],
       do: :diagnostic

  defp action_intent("accept_invitation"), do: :operation
  defp action_intent("open_organization"), do: :operation
  defp action_intent("validate_provider_account"), do: :maintenance
  defp action_intent(_action_id), do: :configuration

  defp surface_definition(surface) do
    %SurfaceDefinition{
      surface_id: surface.id,
      version: @version,
      purpose: surface_purpose(surface.id),
      scope: surface.scope,
      placement: :application_workspace,
      navigation: %{label: surface.id, order: surface_order(surface.id)},
      data_contract: %{query_id: surface.query, version: @version},
      actions: surface.actions,
      refresh: :after_action,
      renderer: {:trusted, "cadence.organization_admin.#{surface.id}"}
    }
  end

  defp surface_order(surface_id),
    do: Enum.find_index(@surface_contracts, &(&1.id == surface_id)) + 1

  defp surface_purpose(surface_id)
       when surface_id in ["notifications", "notifications_bell", "admin_runtime"],
       do: :activity

  defp surface_purpose(surface_id)
       when surface_id in [
              "provider_account_new",
              "admin_organization_new",
              "admin_organization_invite"
            ],
       do: :configuration

  defp surface_purpose(_surface_id), do: :overview

  defp action_scope(action_id) do
    @surface_contracts
    |> Enum.find(&Enum.member?(&1.actions, action_id))
    |> Map.fetch!(:scope)
  end
end
