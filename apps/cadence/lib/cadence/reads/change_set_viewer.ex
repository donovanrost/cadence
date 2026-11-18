defmodule Cadence.Reads.ChangeSetViewer do
  @moduledoc """
  `viewer: %{can_review, review_blocked_reason}` on a change set (ux U79): whether the person
  looking may approve or send back this set, computed up front with the same test the review
  applies (`reviewer_is_author`: they submitted it or authored one of its changes, on a set that
  needs approval). For every set. (The conversion's `legacy_conversion` marker is added by the
  console's config controller, which may call `Control`.)
  """

  alias Cadence.Auth.Scope
  alias Cadence.Configuration.{Access, Submission}

  @doc "The change set map with `viewer` added; nil stays nil."
  @spec annotate(Scope.t(), binary(), map() | nil) :: map() | nil
  def annotate(_scope, _mission_id, nil), do: nil

  def annotate(%Scope{} = scope, mission_id, %{id: change_set_id} = change_set) do
    reason =
      Submission.review_blocked_reason(
        scope.organization_id,
        mission_id,
        change_set_id,
        Access.actor(scope)
      )

    Map.put(change_set, :viewer, %{can_review: is_nil(reason), review_blocked_reason: reason})
  end
end
