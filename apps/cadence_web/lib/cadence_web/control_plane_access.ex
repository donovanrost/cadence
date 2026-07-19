defmodule CadenceWeb.ControlPlaneAccess do
  @moduledoc false

  alias Cadence.Auth.Policy
  alias Cadence.Auth.Scope

  @spec authorize_organization(Scope.t(), binary(), atom()) :: {:ok, term()} | {:error, term()}
  def authorize_organization(%Scope{} = current_scope, organization_id, action)
      when is_binary(organization_id) and is_atom(action) do
    with :ok <- Policy.authorize(current_scope, action, %{organization_id: organization_id}) do
      Cadence.Organizations.fetch_organization(organization_id)
    end
  end

  @spec authorize_mission(Scope.t(), binary(), binary()) :: {:ok, term()} | {:error, term()}
  def authorize_mission(%Scope{} = current_scope, organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    with :ok <-
           Policy.authorize(current_scope, :manage_mission, %{
             organization_id: organization_id,
             mission_id: mission_id
           }) do
      Cadence.Missions.fetch_mission(organization_id, mission_id)
    end
  end

  @spec authorize_spacecraft(Scope.t(), binary(), binary(), binary()) ::
          {:ok, term()} | {:error, term()}
  def authorize_spacecraft(%Scope{} = current_scope, organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    with {:ok, _mission} <- authorize_mission(current_scope, organization_id, mission_id) do
      Cadence.fetch_spacecraft(organization_id, mission_id, spacecraft_id)
    end
  end

  @spec actor_document(Scope.t()) :: map()
  def actor_document(%Scope{} = current_scope) do
    base = %{
      "actor_kind" => Atom.to_string(current_scope.actor_kind),
      "organization_id" => current_scope.organization_id,
      "mission_id" => current_scope.mission_id
    }

    case current_scope.actor_kind do
      :service ->
        Map.merge(base, %{
          "service_identity_id" => current_scope.service_identity.service_identity_id,
          "service_identity_display_name" => current_scope.service_identity.display_name
        })

      :user ->
        Map.merge(base, %{
          "user_id" => current_scope.user.user_id,
          "user_email" => current_scope.user.email,
          "user_display_name" => current_scope.user.display_name
        })
    end
  end
end
