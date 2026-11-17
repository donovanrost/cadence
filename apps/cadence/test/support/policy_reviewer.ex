defmodule Cadence.PolicyReviewer do
  @moduledoc """
  A second administrator for approving what a test's administrator wrote: whoever wrote a fleet
  planning policy version can't decide it (`:reviewer_is_author`, approval sweep 11-15).
  """

  alias Cadence.Auth.Scope

  @doc "`scope` as another user with the same organization role."
  def reviewer(%Scope{user: user} = scope) do
    id = user.user_id <> "-reviewer"
    membership = scope.organization_membership

    %{
      scope
      | user: %{user | user_id: id},
        organization_membership: membership && %{membership | user_id: id}
    }
  end
end
