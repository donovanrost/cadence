defmodule Cadence.Auth.Policy do
  @moduledoc """
  Minimal application-layer policy checks for service-backed control-plane API
  access.
  """

  alias Cadence.Auth.{MissionOrganizationCache, Scope}

  # #282: the organization-level actions a service identity may perform. Everything else that goes
  # through authorize_organization_capability/4 is a person's (actor_kind :user). Adding an action
  # here is a security decision: the test pinning this list (OrganizationActionsPersonOnlyTest)
  # makes it a visible diff for review. Mission-level access is separate: :manage_mission (the REST
  # control plane's gate for a mission-scoped service) and :operate_mission don't go through here.
  #
  # #384 (director 11-19) retired the bearer routes that were its only entries
  # (GET /api/organizations/:id, GET/POST /api/organizations/:id/missions), so it is empty: every
  # organization-level action is a person's. If a deployment ever needs organization-level service
  # access, it comes back as a scoped design under Cedar (#284), not as an entry here.
  @service_allowed_organization_actions []

  @doc "The organization-level actions a service identity may perform (#282): none since #384."
  @spec service_allowed_organization_actions() :: [atom()]
  def service_allowed_organization_actions, do: @service_allowed_organization_actions

  @spec authorize(Scope.t(), atom(), map()) :: :ok | {:error, term()}
  def authorize(%Scope{} = current_scope, :read_organization, %{organization_id: organization_id}) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :read_organization
    )
  end

  def authorize(%Scope{} = current_scope, :manage_missions, %{organization_id: organization_id}) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :manage_missions
    )
  end

  def authorize(%Scope{} = scope, action, params)
      when action in [
             :resolve_command_release,
             :resolve_provider_reservation,
             :reconcile_prepared_send
           ] do
    with :ok <- authorize(scope, :operate_mission, params),
         do: authorize(scope, :manage_mission, params)
  end

  @delivery_credential_actions [
    :"provider_delivery_credential.issue",
    :"provider_delivery_credential.rotate",
    :"provider_delivery_credential.revoke",
    :"provider_delivery_credential.downgrade"
  ]

  def authorize(%Scope{actor_kind: :user, user: %{user_id: id}} = scope, action, params)
      when action in @delivery_credential_actions and is_binary(id),
      do: authorize(scope, :manage_mission, params)

  def authorize(%Scope{}, action, _params) when action in @delivery_credential_actions,
    do: {:error, :authenticated_user_required}

  # Settings and activation review use named policy actions. The initial policy
  # admits active human members; customer approval requirements never assign a
  # built-in role. These action boundaries are the future Cedar integration.
  def authorize(%Scope{actor_kind: :user} = scope, action, %{
        organization_id: organization_id,
        mission_id: mission_id
      })
      when action in [:read_settings, :manage_settings] do
    if is_nil(mission_id) do
      authorize(scope, :operate_organization, %{organization_id: organization_id})
    else
      authorize(scope, :operate_mission, %{
        organization_id: organization_id,
        mission_id: mission_id
      })
    end
  end

  def authorize(%Scope{}, action, _params) when action in [:read_settings, :manage_settings],
    do: {:error, :authenticated_user_required}

  def authorize(%Scope{} = current_scope, :operate_organization, %{
        organization_id: organization_id
      }) do
    case current_scope.actor_kind do
      :user ->
        with :ok <- authenticated_user(current_scope) do
          authorized_mission_organization(current_scope, organization_id)
        end

      :service ->
        {:error, :authenticated_user_required}

      _invalid_actor ->
        {:error, :authenticated_user_required}
    end
  end

  def authorize(%Scope{} = current_scope, :manage_organization_members, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :manage_organization_members
    )
  end

  # §11 L4: creating a mission in an organization. todo(authz): Cedar should decide this; today
  # it's the organization's admins and platform admins.
  def authorize(%Scope{} = current_scope, :create_missions, %{organization_id: organization_id}) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :create_missions
    )
  end

  def authorize(%Scope{} = current_scope, :manage_provider_accounts, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :manage_provider_accounts
    )
  end

  def authorize(%Scope{} = current_scope, :approve_provider_changes, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :approve_provider_changes
    )
  end

  # DECISIONS #92 (a): an organization administrator approves a mission-model revision, never a
  # service; the importer/approver separation lives in MissionModels.RevisionDecisions.
  def authorize(%Scope{actor_kind: :service}, :approve_mission_model, _params),
    do: {:error, :human_mission_model_approver_required}

  def authorize(%Scope{} = current_scope, :approve_mission_model, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :approve_mission_model
    )
  end

  def authorize(%Scope{} = current_scope, :approve_contact_plans, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :approve_contact_plans
    )
  end

  def authorize(%Scope{} = current_scope, :manage_fleet_planning_policy, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :manage_fleet_planning_policy
    )
  end

  def authorize(%Scope{} = current_scope, :approve_fleet_planning_policy, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :approve_fleet_planning_policy
    )
  end

  def authorize(%Scope{} = current_scope, :manage_automation_grants, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(
      current_scope,
      organization_id,
      :organization_admin,
      :manage_automation_grants
    )
  end

  # todo(authz): Cedar should decide mission access per user. Today any active member operates
  # every mission of their organization (no mission-level grant is checked here).
  def authorize(%Scope{} = current_scope, :operate_mission, %{
        organization_id: organization_id,
        mission_id: mission_id
      }) do
    case current_scope.actor_kind do
      :user ->
        with :ok <- authenticated_user(current_scope),
             :ok <- authorized_mission_organization(current_scope, organization_id),
             :ok <- valid_mission_id(mission_id) do
          mission_in_organization(organization_id, mission_id)
        end

      :service ->
        authorize_service_mission(current_scope, organization_id, mission_id)

      _invalid_actor ->
        {:error, :authenticated_user_required}
    end
  end

  def authorize(%Scope{} = current_scope, :read_application_catalog, %{
        organization_id: organization_id,
        mission_id: mission_id
      }) do
    authorize(current_scope, :operate_mission, %{
      organization_id: organization_id,
      mission_id: mission_id
    })
  end

  def authorize(%Scope{} = current_scope, :read_legacy_application, %{
        organization_id: organization_id,
        mission_id: mission_id
      }) do
    authorize(current_scope, :operate_mission, %{
      organization_id: organization_id,
      mission_id: mission_id
    })
  end

  # Dashboard authoring deliberately starts with the existing mission-operator
  # population. Keeping this as a named policy action gives the Editor and
  # other mutation routes one enforceable boundary while leaving room for a
  # narrower durable grant later without changing those routes.
  def authorize(%Scope{actor_kind: :user} = current_scope, :author_dashboards, params) do
    authorize(current_scope, :operate_mission, params)
  end

  def authorize(%Scope{}, :author_dashboards, _params),
    do: {:error, :authenticated_user_required}

  def authorize(%Scope{} = current_scope, :request_activation, params) do
    action = if current_scope.actor_kind == :service, do: :manage_mission, else: :operate_mission
    authorize(current_scope, action, params)
  end

  def authorize(%Scope{actor_kind: :service}, :approve_activation, _params),
    do: {:error, :human_activation_approver_required}

  def authorize(%Scope{} = current_scope, :approve_activation, %{
        organization_id: organization_id,
        mission_id: mission_id
      }) do
    authorize(current_scope, :operate_mission, %{
      organization_id: organization_id,
      mission_id: mission_id
    })
  end

  # #281: services never manage service identities (list, create, rotate, revoke). A person only,
  # so a leaked service token can't mint, re-key or revoke others.
  def authorize(
        %Scope{} = current_scope,
        :manage_service_identities,
        %{organization_id: organization_id}
      ) do
    with :ok <- authenticated_user(current_scope) do
      authorize_organization_capability(
        current_scope,
        organization_id,
        :organization_admin,
        :manage_service_identities
      )
    end
  end

  # #1158: administering a mission is checked against the mission itself, like `:operate_mission`:
  # it must exist and belong to the organization being authorized, for every principal (a platform
  # admin included), so the answer never depends on a caller having fetched the mission first.
  def authorize(
        %Scope{} = current_scope,
        :manage_mission,
        %{organization_id: organization_id, mission_id: mission_id}
      ) do
    with :ok <- valid_mission_id(mission_id),
         :ok <- mission_in_organization(organization_id, mission_id) do
      manage_capability(current_scope, organization_id, mission_id)
    end
  end

  # A platform admin administers any organization's mission; otherwise the scope must be the
  # organization's. An organization admin administers every mission of it, except that a service
  # pinned to one mission administers only that one, whatever capability it holds (#1158); a
  # mission admin administers its own mission.
  defp manage_capability(%Scope{} = scope, organization_id, mission_id) do
    cond do
      MapSet.member?(scope.capabilities, :platform_admin) ->
        :ok

      scope.organization_id != organization_id ->
        {:error, :scope_mismatch}

      not pinned_to?(scope, mission_id) ->
        {:error, :forbidden}

      MapSet.member?(scope.capabilities, :organization_admin) ->
        :ok

      MapSet.member?(scope.capabilities, :mission_admin) and scope.mission_id == mission_id ->
        :ok

      true ->
        {:error, :forbidden}
    end
  end

  # A scope with no mission pin (a person, an organization-wide service) isn't restricted to one.
  defp pinned_to?(%Scope{mission_id: nil}, _mission_id), do: true
  defp pinned_to?(%Scope{mission_id: mission_id}, mission_id), do: true
  defp pinned_to?(%Scope{}, _mission_id), do: false

  @doc """
  The actor holds every capability it would hand a service identity, by issuing it or rotating
  its key (a rotator receives a working token, so rotating is issuing; #281). `platform_admin`
  holds every capability and `organization_admin` covers `mission_admin`. Moot while only
  organization admins issue, who hold all a service can get; it binds if issuance ever widens.
  """
  @spec ensure_holds_capabilities(Scope.t(), [atom()]) ::
          :ok | {:error, {:capability_beyond_issuer, [atom()]}}
  def ensure_holds_capabilities(%Scope{capabilities: held}, capabilities)
      when is_list(capabilities) do
    case capabilities |> Enum.uniq() |> Enum.reject(&holds?(held, &1)) do
      [] -> :ok
      missing -> {:error, {:capability_beyond_issuer, missing}}
    end
  end

  defp holds?(held, capability) do
    MapSet.member?(held, :platform_admin) or MapSet.member?(held, capability) or
      (capability == :mission_admin and MapSet.member?(held, :organization_admin))
  end

  # #282: organization-level actions are a person's by default. The check comes first, before any
  # membership or role is read, so every action through here, now or added later, refuses a
  # service identity (even one holding organization_admin or platform_admin) unless it is listed
  # in @service_allowed_organization_actions.
  defp authorize_organization_capability(
         %Scope{} = current_scope,
         organization_id,
         capability,
         action
       ) do
    with :ok <- person_unless_service_allowed(current_scope, action) do
      organization_capability(current_scope, organization_id, capability)
    end
  end

  defp person_unless_service_allowed(%Scope{} = scope, action) do
    if Enum.member?(@service_allowed_organization_actions, action),
      do: :ok,
      else: authenticated_user(scope)
  end

  defp organization_capability(%Scope{} = current_scope, organization_id, capability) do
    cond do
      MapSet.member?(current_scope.capabilities, :platform_admin) ->
        :ok

      current_scope.organization_id != organization_id ->
        {:error, :scope_mismatch}

      MapSet.member?(current_scope.capabilities, capability) ->
        :ok

      true ->
        {:error, :forbidden}
    end
  end

  defp authenticated_user(%Scope{actor_kind: :user, user: user}) when not is_nil(user), do: :ok
  defp authenticated_user(%Scope{}), do: {:error, :authenticated_user_required}

  defp authorized_mission_organization(current_scope, organization_id) do
    if MapSet.member?(current_scope.capabilities, :platform_admin),
      do: :ok,
      else: active_organization_membership(current_scope, organization_id)
  end

  defp active_organization_membership(
         %Scope{
           organization_id: organization_id,
           organization_membership: %{lifecycle_state: :active}
         },
         organization_id
       ),
       do: :ok

  defp active_organization_membership(%Scope{organization_id: scoped}, organization_id)
       when scoped != organization_id,
       do: {:error, :scope_mismatch}

  defp active_organization_membership(%Scope{}, _organization_id), do: {:error, :forbidden}

  # Defense in depth (director): a mission id from the request must be a mission of the
  # organization being authorized, so callers stop relying on every domain query to filter by
  # organization. A service identity's mission is pinned to its own organization by
  # authorize_service_mission/3.
  #
  # operate_mission runs on hot paths (every console request, /session's per-mission capability
  # loops, every dashboard resolve, so every live tick), so a (organization, mission) pair is checked
  # once per node and kept in MissionOrganizationCache (ETS): a mission never changes organization. Only pairs
  # that matched are kept; anything else is asked again every time (and refused).
  # todo(authz): Cedar should own mission membership in the organization.
  defp mission_in_organization(organization_id, mission_id) do
    cond do
      MissionOrganizationCache.confirmed?(organization_id, mission_id) ->
        :ok

      Cadence.Missions.organization_id_for_mission(mission_id) == organization_id ->
        MissionOrganizationCache.confirm(organization_id, mission_id)

      true ->
        {:error, :scope_mismatch}
    end
  end

  defp valid_mission_id(mission_id) when is_binary(mission_id) and mission_id != "", do: :ok
  defp valid_mission_id(_mission_id), do: {:error, :scope_mismatch}

  defp authorize_service_mission(
         %Scope{
           organization_id: organization_id,
           mission_id: mission_id,
           service_identity: %{
             organization_id: organization_id,
             mission_id: mission_id,
             lifecycle_state: :active
           }
         },
         organization_id,
         mission_id
       )
       when is_binary(mission_id) and mission_id != "",
       do: :ok

  defp authorize_service_mission(
         %Scope{organization_id: scoped_organization_id},
         organization_id,
         _mission_id
       )
       when scoped_organization_id != organization_id,
       do: {:error, :scope_mismatch}

  defp authorize_service_mission(%Scope{}, _organization_id, _mission_id),
    do: {:error, :forbidden}
end
