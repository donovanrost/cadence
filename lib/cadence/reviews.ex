defmodule Cadence.Reviews do
  @moduledoc """
  Context for global review inbox queries.

  This module provides cross-mission queries for users to see all their
  review-related activity in one place, similar to GitHub's pull request inbox.

  ## Sections

  - **Requested Reviews** - Versions where user has a pending review request
  - **Awaiting Re-review** - Versions where user requested changes and author has resubmitted
  - **Your Submissions** - Versions authored by the user
  - **Recent Activity** - Past reviews the user participated in
  """

  import Ecto.Query

  alias Cadence.Procedures.{
    ProcedureReview,
    ProcedureReviewRequest,
    ProcedureVersion
  }

  alias Cadence.Repo
  alias Cadence.Time, as: CadenceTime

  # ============================================================================
  # Approval Progress
  # ============================================================================

  @doc """
  Gets approval progress for multiple version IDs at once.

  Returns a map of version_id => %{approved: count, total_reviews: count}

  This is useful for displaying approval badges on procedure cards.
  """
  def get_approval_progress_for_versions(version_ids) when is_list(version_ids) do
    if Enum.empty?(version_ids) do
      %{}
    else
      from(r in ProcedureReview,
        where: r.procedure_version_id in ^version_ids and r.superseded == false,
        group_by: r.procedure_version_id,
        select: {
          r.procedure_version_id,
          %{
            approved: count(fragment("CASE WHEN ? = 'approve' THEN 1 END", r.decision)),
            changes_requested:
              count(fragment("CASE WHEN ? = 'request_changes' THEN 1 END", r.decision)),
            total_reviews: count()
          }
        }
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  # ============================================================================
  # Inbox Queries
  # ============================================================================

  @doc """
  Lists versions where the user has a pending review request.

  Returns versions with procedure and requester preloaded.

  ## Options

  - `:organization_id` - Filter to specific organization
  - `:mission_id` - Filter to specific mission
  - `:limit` - Maximum records to return (default: 50)
  """
  def list_requested_reviews(user_id, opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)
    limit = Keyword.get(opts, :limit, 50)

    query =
      from rr in ProcedureReviewRequest,
        where: rr.reviewer_id == ^user_id and rr.status == :pending,
        join: v in ProcedureVersion,
        on: v.id == rr.procedure_version_id,
        join: p in assoc(v, :procedure),
        where: v.status in [:in_review, :changes_requested],
        order_by: [asc: rr.inserted_at],
        limit: ^limit,
        select: %{
          request: rr,
          version: v,
          procedure: p
        }

    query =
      if organization_id do
        where(query, [rr, v, p], p.organization_id == ^organization_id)
      else
        query
      end

    query =
      if mission_id do
        where(query, [rr, v, p], p.mission_id == ^mission_id)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(fn %{request: request, version: version, procedure: procedure} ->
      request = Repo.preload(request, :requester)

      %{
        request: request,
        version: %{version | procedure: procedure},
        wait_time: DateTime.diff(CadenceTime.now(), request.inserted_at, :second)
      }
    end)
  end

  @doc """
  Lists versions where the user previously requested changes and the author has resubmitted.

  These are versions awaiting re-review from this user.

  ## Options

  - `:organization_id` - Filter to specific organization
  - `:mission_id` - Filter to specific mission
  - `:limit` - Maximum records to return (default: 50)
  """
  def list_awaiting_rereview(user_id, opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)
    limit = Keyword.get(opts, :limit, 50)

    # Find versions where:
    # 1. User has a superseded request_changes review
    # 2. Version is now in_review (was resubmitted)
    query =
      from r in ProcedureReview,
        where:
          r.user_id == ^user_id and
            r.decision == :request_changes and
            r.superseded == true,
        join: v in ProcedureVersion,
        on: v.id == r.procedure_version_id,
        join: p in assoc(v, :procedure),
        where: v.status == :in_review,
        # Make sure user hasn't already reviewed the new submission
        left_join: new_review in ProcedureReview,
        on:
          new_review.procedure_version_id == v.id and
            new_review.user_id == ^user_id and
            new_review.superseded == false,
        where: is_nil(new_review.id),
        order_by: [desc: v.submitted_at],
        limit: ^limit,
        select: %{
          previous_review: r,
          version: v,
          procedure: p
        }

    query =
      if organization_id do
        where(query, [r, v, p], p.organization_id == ^organization_id)
      else
        query
      end

    query =
      if mission_id do
        where(query, [r, v, p], p.mission_id == ^mission_id)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(fn %{previous_review: review, version: version, procedure: procedure} ->
      %{
        previous_review: review,
        version: %{version | procedure: procedure},
        resubmitted_at: version.submitted_at
      }
    end)
    |> Enum.uniq_by(& &1.version.id)
  end

  @doc """
  Lists versions authored/submitted by the user.

  ## Options

  - `:organization_id` - Filter to specific organization
  - `:mission_id` - Filter to specific mission
  - `:status` - Filter by version status (e.g., :in_review, :changes_requested)
  - `:limit` - Maximum records to return (default: 50)
  """
  def list_user_submissions(user_id, opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    query =
      from v in ProcedureVersion,
        join: p in assoc(v, :procedure),
        where: v.created_by_id == ^user_id or v.submitted_by_id == ^user_id,
        where: v.status not in [:deprecated],
        order_by: [desc: v.updated_at],
        limit: ^limit,
        preload: [procedure: p]

    query =
      if organization_id do
        where(query, [v, p], p.organization_id == ^organization_id)
      else
        query
      end

    query =
      if mission_id do
        where(query, [v, p], p.mission_id == ^mission_id)
      else
        query
      end

    query =
      if status do
        where(query, [v], v.status == ^status)
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.map(fn version ->
      review_status = get_review_summary(version)

      %{
        version: version,
        status: version.status,
        review_summary: review_status
      }
    end)
  end

  @doc """
  Lists recent review activity the user participated in.

  Includes both reviews submitted by the user and versions they authored.

  ## Options

  - `:organization_id` - Filter to specific organization
  - `:mission_id` - Filter to specific mission
  - `:limit` - Maximum records to return (default: 50)
  """
  def list_recent_activity(user_id, opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)
    limit = Keyword.get(opts, :limit, 50)

    # Get versions where user submitted a review
    reviewed_query =
      from r in ProcedureReview,
        where: r.user_id == ^user_id,
        join: v in ProcedureVersion,
        on: v.id == r.procedure_version_id,
        join: p in assoc(v, :procedure),
        order_by: [desc: r.inserted_at],
        limit: ^limit,
        select: %{
          type: "review",
          review: r,
          version: v,
          procedure: p,
          timestamp: r.inserted_at
        }

    reviewed_query =
      if organization_id do
        where(reviewed_query, [r, v, p], p.organization_id == ^organization_id)
      else
        reviewed_query
      end

    reviewed_query =
      if mission_id do
        where(reviewed_query, [r, v, p], p.mission_id == ^mission_id)
      else
        reviewed_query
      end

    reviewed = Repo.all(reviewed_query)

    # Get versions authored by user that received reviews
    authored_query =
      from v in ProcedureVersion,
        join: p in assoc(v, :procedure),
        join: r in ProcedureReview,
        on: r.procedure_version_id == v.id,
        where: v.created_by_id == ^user_id or v.submitted_by_id == ^user_id,
        where: r.user_id != ^user_id,
        order_by: [desc: r.inserted_at],
        limit: ^limit,
        select: %{
          type: "received_review",
          review: r,
          version: v,
          procedure: p,
          timestamp: r.inserted_at
        }

    authored_query =
      if organization_id do
        where(authored_query, [v, p], p.organization_id == ^organization_id)
      else
        authored_query
      end

    authored_query =
      if mission_id do
        where(authored_query, [v, p], p.mission_id == ^mission_id)
      else
        authored_query
      end

    authored = Repo.all(authored_query)

    # Combine and sort by timestamp
    (reviewed ++ authored)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(fn item ->
      review = Repo.preload(item.review, :user)

      %{
        type: item.type,
        review: review,
        version: %{item.version | procedure: item.procedure},
        timestamp: item.timestamp
      }
    end)
  end

  # ============================================================================
  # Statistics
  # ============================================================================

  @doc """
  Gets inbox counts for a user.

  Returns a map with counts for each inbox section.

  ## Options

  - `:organization_id` - Filter to specific organization
  - `:mission_id` - Filter to specific mission
  """
  def get_inbox_counts(user_id, opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)

    # Count pending review requests
    pending_requests =
      from(rr in ProcedureReviewRequest,
        where: rr.reviewer_id == ^user_id and rr.status == :pending,
        join: v in ProcedureVersion,
        on: v.id == rr.procedure_version_id,
        join: p in Cadence.Procedures.Procedure,
        on: p.id == v.procedure_id,
        where: v.status in [:in_review, :changes_requested]
      )
      |> maybe_filter_by_org_on_procedure(organization_id)
      |> maybe_filter_by_mission_on_procedure(mission_id)
      |> Repo.aggregate(:count)

    # Count awaiting re-review (simplified - may have false positives)
    awaiting_rereview =
      from(r in ProcedureReview,
        where:
          r.user_id == ^user_id and
            r.decision == :request_changes and
            r.superseded == true,
        join: v in ProcedureVersion,
        on: v.id == r.procedure_version_id,
        join: p in Cadence.Procedures.Procedure,
        on: p.id == v.procedure_id,
        where: v.status == :in_review
      )
      |> maybe_filter_by_org_on_procedure(organization_id)
      |> maybe_filter_by_mission_on_procedure(mission_id)
      |> Repo.aggregate(:count)

    # Count user's active submissions
    active_submissions =
      from(v in ProcedureVersion,
        join: p in Cadence.Procedures.Procedure,
        on: p.id == v.procedure_id,
        where:
          (v.created_by_id == ^user_id or v.submitted_by_id == ^user_id) and
            v.status in [:in_review, :changes_requested]
      )
      |> maybe_filter_by_org_on_procedure(organization_id)
      |> maybe_filter_by_mission_on_procedure(mission_id)
      |> Repo.aggregate(:count)

    %{
      pending_requests: pending_requests,
      awaiting_rereview: awaiting_rereview,
      active_submissions: active_submissions,
      total: pending_requests + awaiting_rereview
    }
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp get_review_summary(version) do
    reviews =
      from(r in ProcedureReview,
        where: r.procedure_version_id == ^version.id and r.superseded == false
      )
      |> Repo.all()

    approved = Enum.count(reviews, &(&1.decision == :approve))
    changes_requested = Enum.count(reviews, &(&1.decision == :request_changes))

    %{
      approved_count: approved,
      changes_requested_count: changes_requested,
      total_reviews: length(reviews)
    }
  end

  # Filter by organization when the procedure is already joined in the query
  # Expects the procedure to be the last binding in the query
  defp maybe_filter_by_org_on_procedure(query, nil), do: query

  defp maybe_filter_by_org_on_procedure(query, organization_id) do
    where(query, [..., p], p.organization_id == ^organization_id)
  end

  # Filter by mission when the procedure is already joined in the query
  # Expects the procedure to be the last binding in the query
  defp maybe_filter_by_mission_on_procedure(query, nil), do: query

  defp maybe_filter_by_mission_on_procedure(query, mission_id) do
    where(query, [..., p], p.mission_id == ^mission_id)
  end
end
