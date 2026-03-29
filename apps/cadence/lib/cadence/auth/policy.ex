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

  defp authorize_platform_admin(%Scope{} = current_scope) do
    if MapSet.member?(current_scope.capabilities, :platform_admin) do
      :ok
    else
      {:error, :forbidden}
    end
  end
end
