defmodule Cadence.Auth.ApplicationHostPolicyTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Auth.{Policy, Scope}

  test "application catalog and legacy read admissions require the scoped organization" do
    scope = %Scope{
      actor_kind: :user,
      organization_id: "org-alpha",
      user: %{user_id: "user-alpha"},
      organization_membership: %{lifecycle_state: :active}
    }

    assert :ok =
             Policy.authorize(scope, :read_application_catalog, %{
               organization_id: "org-alpha",
               mission_id: "mission-alpha"
             })

    assert :ok =
             Policy.authorize(scope, :read_legacy_application, %{
               organization_id: "org-alpha",
               mission_id: "mission-alpha"
             })

    assert {:error, :scope_mismatch} =
             Policy.authorize(scope, :read_application_catalog, %{
               organization_id: "org-beta",
               mission_id: "mission-beta"
             })
  end

  test "missing users and unauthorized memberships fail closed before data access" do
    missing_user = %Scope{
      actor_kind: :user,
      organization_id: "org-alpha",
      organization_membership: %{lifecycle_state: :active}
    }

    assert {:error, :authenticated_user_required} =
             Policy.authorize(missing_user, :read_legacy_application, %{
               organization_id: "org-alpha",
               mission_id: "mission-alpha"
             })

    unauthorized = %Scope{
      actor_kind: :user,
      organization_id: "org-alpha",
      user: %{user_id: "user-alpha"}
    }

    assert {:error, :forbidden} =
             Policy.authorize(unauthorized, :read_application_catalog, %{
               organization_id: "org-alpha",
               mission_id: "mission-alpha"
             })
  end
end
