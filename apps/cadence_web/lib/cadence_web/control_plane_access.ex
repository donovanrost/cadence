defmodule CadenceWeb.ControlPlaneAccess do
  @moduledoc false

  alias Cadence.Auth.Scope

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
          "user_display_name" => current_scope.user.display_name
        })
    end
  end
end
