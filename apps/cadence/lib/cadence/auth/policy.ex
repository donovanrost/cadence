defmodule Cadence.Auth.Policy do
  @moduledoc """
  Minimal application-layer policy checks for service-backed control-plane API
  access.
  """

  alias Cadence.Auth.Scope

  @spec authorize(Scope.t(), atom(), map()) :: :ok | {:error, term()}
  def authorize(%Scope{} = current_scope, :bootstrap_platform, _params) do
    authorize_platform_admin(current_scope)
  end

  def authorize(%Scope{} = current_scope, :read_organization, %{organization_id: organization_id}) do
    authorize_organization_capability(current_scope, organization_id, :organization_admin)
  end

  def authorize(%Scope{} = current_scope, :manage_missions, %{organization_id: organization_id}) do
    authorize_organization_capability(current_scope, organization_id, :organization_admin)
  end

  def authorize(%Scope{} = current_scope, :manage_provider_accounts, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(current_scope, organization_id, :organization_admin)
  end

  def authorize(%Scope{} = current_scope, :approve_provider_changes, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(current_scope, organization_id, :organization_admin)
  end

  def authorize(%Scope{} = current_scope, :approve_contact_plans, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(current_scope, organization_id, :organization_admin)
  end

  def authorize(%Scope{} = current_scope, :manage_fleet_planning_policy, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(current_scope, organization_id, :organization_admin)
  end

  def authorize(%Scope{} = current_scope, :approve_fleet_planning_policy, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(current_scope, organization_id, :organization_admin)
  end

  def authorize(%Scope{} = current_scope, :manage_automation_grants, %{
        organization_id: organization_id
      }) do
    authorize_organization_capability(current_scope, organization_id, :organization_admin)
  end

  def authorize(%Scope{} = current_scope, :operate_mission, %{
        organization_id: organization_id,
        mission_id: mission_id
      }) do
    case current_scope.actor_kind do
      :user ->
        with :ok <- authenticated_user(current_scope),
             :ok <- authorized_mission_organization(current_scope, organization_id) do
          valid_mission_id(mission_id)
        end

      :service ->
        authorize_service_mission(current_scope, organization_id, mission_id)
    end
  end

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
    authorize(current_scope, :manage_mission, %{
      organization_id: organization_id,
      mission_id: mission_id
    })
  end

  def authorize(
        %Scope{} = current_scope,
        :manage_service_identities,
        %{organization_id: organization_id}
      ) do
    authorize_organization_capability(current_scope, organization_id, :organization_admin)
  end

  def authorize(
        %Scope{} = current_scope,
        :manage_mission,
        %{organization_id: organization_id, mission_id: mission_id}
      ) do
    cond do
      MapSet.member?(current_scope.capabilities, :platform_admin) ->
        :ok

      current_scope.organization_id != organization_id ->
        {:error, :scope_mismatch}

      MapSet.member?(current_scope.capabilities, :organization_admin) ->
        :ok

      MapSet.member?(current_scope.capabilities, :mission_admin) and
          current_scope.mission_id == mission_id ->
        :ok

      true ->
        {:error, :forbidden}
    end
  end

  defp authorize_organization_capability(
         %Scope{} = current_scope,
         organization_id,
         capability
       ) do
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

  defp authorize_platform_admin(%Scope{} = current_scope) do
    if MapSet.member?(current_scope.capabilities, :platform_admin) do
      :ok
    else
      {:error, :forbidden}
    end
  end
end
