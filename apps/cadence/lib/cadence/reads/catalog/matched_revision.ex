defmodule Cadence.Reads.Catalog.MatchedRevision do
  @moduledoc """
  C3's `matched_revision` (#119, ux U99): when an import's content matched a mission-model
  revision that already existed, which one, its CURRENT status and decision, and why separation of
  duties bars the viewer from approving it. `nil` when the run made a new revision, failed, or
  predates #119.

  `cannot_approve` is `nil` unless separation bars the viewer:
  `%{reason: "self" | "authors_unknown", via_service: %{id, name} | nil, service: %{id, name} | nil}`,
  the same fields as `RevisionDecisions.separation/4`'s refusal (U100). Today only `"self"` with
  both `nil` (they imported it). It is the separation reason ONLY: a viewer who can't approve
  for another reason (no permission) reads `nil`, so it never offers Approve on its own. The
  approval read decides WHETHER separation is the viewer's reason (after permission and status, in
  its order); `RevisionDecisions.separation/4`, the check approval itself runs, says which one, and
  #280's service accountability arrives there. It is per viewer, so this payload is built per
  request and never broadcast or shared.

  Who and when come together or not at all (U29): `decision` is `nil` unless both are recorded.
  `by` carries the display name only (U25), never an id or email.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.ImportRun
  alias Cadence.MissionModels.RevisionDecisions
  alias Cadence.Reads.MissionModelApprovals

  @spec read(Scope.t(), binary(), ImportRun.t()) :: map() | nil
  def read(%Scope{} = scope, mission_id, %ImportRun{status: :completed} = run) do
    with id when is_binary(id) <-
           get_in(run.result_document || %{}, ["mission_model", "matched_existing", "revision_id"]),
         {:ok, approval} <- MissionModelApprovals.read(scope, mission_id, id) do
      %{
        model_revision_id: id,
        revision: catalog_revision(scope.organization_id, mission_id, approval.catalog_revision),
        status: approval.status,
        decision: decision(approval.decision),
        cannot_approve: cannot_approve(scope, mission_id, id, approval.cannot_decide_because)
      }
    else
      _none -> nil
    end
  end

  def read(_scope, _mission_id, _run), do: nil

  defp cannot_approve(scope, mission_id, revision_id, "self_approval") do
    viewer_id = scope.user && scope.user.user_id

    case RevisionDecisions.separation(scope.organization_id, mission_id, revision_id, viewer_id) do
      {:refused, refusal} -> %{refusal | reason: Atom.to_string(refusal.reason)}
      {:ok, _checked} -> nil
    end
  end

  defp cannot_approve(_scope, _mission_id, _revision_id, _not_separation), do: nil

  # The catalog revision the model is named by (the first recorded, U65), with its database.
  defp catalog_revision(organization_id, mission_id, %{id: id, number: number} = revision) do
    %{
      id: id,
      number: number,
      label: Map.get(revision, :label),
      database: database(organization_id, mission_id, Map.get(revision, :database_id))
    }
  end

  defp catalog_revision(_organization_id, _mission_id, _none), do: nil

  defp database(_organization_id, _mission_id, nil), do: nil

  defp database(organization_id, mission_id, database_id) do
    case Catalog.fetch_database(organization_id, mission_id, database_id) do
      {:ok, database} -> %{id: database_id, name: database.name}
      _gone -> %{id: database_id, name: nil}
    end
  end

  defp decision(%{kind: kind, by: %{} = by, at: %DateTime{} = at} = decision),
    do: %{kind: kind, by: %{name: by[:name]}, at: at, reason: decision[:reason]}

  defp decision(_incomplete), do: nil
end
