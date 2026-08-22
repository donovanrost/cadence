defmodule Cadence.Auth.DashboardAuthorPolicyTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.{Policy, Scope}

  test "ratifies active human mission operators as dashboard authors" do
    assert :ok =
             Policy.authorize(scope(:active), :author_dashboards, %{
               organization_id: "org-author",
               mission_id: "mission-author"
             })
  end

  test "denies revoked and cross-organization membership" do
    assert {:error, :forbidden} =
             Policy.authorize(scope(:revoked), :author_dashboards, %{
               organization_id: "org-author",
               mission_id: "mission-author"
             })

    assert {:error, :scope_mismatch} =
             Policy.authorize(scope(:active), :author_dashboards, %{
               organization_id: "other-org",
               mission_id: "mission-author"
             })
  end

  defp scope(lifecycle_state) do
    user =
      User.new(%{
        user_id: "user-author",
        email: "author@example.com",
        display_name: "Dashboard Author"
      })

    membership =
      OrganizationMembership.new(%{
        organization_membership_id: "membership-author",
        user_id: user.user_id,
        organization_id: "org-author",
        lifecycle_state: lifecycle_state,
        role: :member
      })

    Scope.new(%{
      user: user,
      organization_id: "org-author",
      organization: nil,
      organization_membership: membership
    })
  end
end
