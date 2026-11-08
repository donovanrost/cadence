defmodule Cadence.Configuration.Submission do
  @moduledoc """
  Submit, review and apply of a change set (ADR-004 governance).

  The approval requirement comes from `Cadence.Governance.ActivationPolicy`. With direct
  approval, submitting applies at once. With independent approval, the set freezes `in_review`
  until a reviewer who is **none of its authors** (and not its submitter) approves it or sends it
  back. The policy evidence captured at submit is re-validated when the set is applied.

  Apply is one transaction: lock the head, re-run the pipeline against live state (conflicts and
  validation are re-checked), write the revision and its entries, and close the set. Any failure
  rolls everything back. This module does no publishing: the caller runs the after-commit tail
  using the returned `impacts`.
  """

  alias Cadence.Configuration.{ChangeSetStore, Document, Ledger, Pipeline, Preview, ReviewRow}
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Ids
  alias Cadence.Repo

  @reason_bytes 10..2_000
  @comment_bytes 1..2_000

  @spec submit(String.t(), String.t(), String.t(), map(), map()) ::
          {:ok, map()} | {:error, term()}
  def submit(organization_id, mission_id, change_set_id, actor, params) do
    with {:ok, reason} <- text(params, :reason, @reason_bytes, :reason_required),
         {:ok, set} <- ChangeSetStore.fetch(mission_id, change_set_id),
         :ok <- state(set, "open"),
         :ok <- expected(set, params),
         {:ok, preview} <- checks(organization_id, set, params) do
      policy = ActivationPolicy.evidence(organization_id, mission_id)
      Repo.transaction(fn -> submit_transaction(set, actor, reason, policy, preview, params) end)
    end
  end

  defp submit_transaction(set, actor, reason, policy, preview, params) do
    with {:ok, set} <- ChangeSetStore.lock_set(set.mission_id, set.change_set_id),
         :ok <- state(set, "open"),
         :ok <- expected(set, params),
         :ok <- something_staged(set) do
      submit_locked(set, actor, reason, policy, preview)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @spec review(String.t(), String.t(), String.t(), map(), :approve | :send_back, map()) ::
          {:ok, map()} | {:error, term()}
  def review(organization_id, mission_id, change_set_id, reviewer, decision, params)
      when decision in [:approve, :send_back] do
    with {:ok, comment} <- text(params, :comment, @comment_bytes, :comment_required),
         {:ok, set} <- ChangeSetStore.fetch(mission_id, change_set_id),
         :ok <- state(set, "in_review"),
         :ok <- expected(set, params),
         :ok <- independent(set, reviewer) do
      decide(organization_id, set, reviewer, decision, comment, params)
    end
  end

  def review(_org, _mission, _set, _reviewer, _decision, _params), do: {:error, :invalid_decision}

  defp decide(_organization_id, set, reviewer, :send_back, comment, params) do
    locked(set, params, fn set ->
      insert_review(set, reviewer, "sent_back", comment)
      set = ChangeSetStore.update_set(set, state: "open", policy_document: nil)
      %{state: :open, change_set_id: set.change_set_id, version: set.version}
    end)
  end

  defp decide(organization_id, set, reviewer, :approve, comment, params) do
    case checks(organization_id, set, %{acknowledged_holds: true}) do
      {:ok, _preview} ->
        result =
          locked(set, params, fn set ->
            review = insert_review(set, reviewer, "approved", comment)

            execute_locked(set, set.submitted_by, set.reason, set.policy_document, [
              approval(review)
            ])
          end)

        reopen_on_failure(set, result)

      {:error, {:checks_failed, _preview}} = error ->
        reopen_on_failure(set, error)
    end
  end

  defp submit_locked(set, actor, reason, %{"approval_required" => true} = policy, _preview) do
    set =
      ChangeSetStore.update_set(set,
        state: "in_review",
        submitted_by: actor,
        submitted_at: DateTime.utc_now(),
        reason: reason,
        policy_document: policy
      )

    %{state: :in_review, change_set_id: set.change_set_id, version: set.version}
  end

  defp submit_locked(set, actor, reason, policy, _preview) do
    set = %{set | submitted_by: actor, reason: reason}
    execute_locked(set, actor, reason, policy, [])
  end

  # Runs inside the caller's transaction; rolls it back on any failure.
  defp execute_locked(set, applier, reason, policy, approvals) do
    org = set.organization_id
    mission = set.mission_id

    with :ok <- ActivationPolicy.validate(org, mission, policy),
         head = Ledger.lock_head(org, mission),
         ops = ChangeSetStore.staged_ops(set.change_set_id),
         result = Pipeline.run(org, mission, set.base_revision_number, ops),
         :ok <- clean(result),
         changes = ChangeSetStore.changes(set.change_set_id),
         {:ok, revision} <- record(head, set, applier, reason, approvals, changes, ops, result) do
      ChangeSetStore.set_change_states(
        set.change_set_id,
        Enum.map(changes, & &1.change_id),
        "applied"
      )

      now = DateTime.utc_now()

      ChangeSetStore.update_set(set,
        state: "applied",
        applied_revision_number: revision.revision_number,
        submitted_by: set.submitted_by || applier,
        submitted_at: set.submitted_at || now,
        reason: reason,
        failure_document: nil,
        closed_at: now
      )

      %{
        state: :applied,
        change_set_id: set.change_set_id,
        revision: revision.revision_number,
        staged_count: length(changes),
        activation_id: nil,
        generation: nil,
        runtime: :not_applicable,
        degraded_partitions: [],
        impacts: MapSet.to_list(result.impacts),
        kinds: result.entries |> Enum.map(& &1.kind) |> Enum.uniq()
      }
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp record(head, set, applier, reason, approvals, changes, ops, result) do
    Ledger.record(
      head,
      %{
        kind: "change_set",
        change_set_id: set.change_set_id,
        applied_by: applier,
        applied_at: DateTime.utc_now(),
        reason: reason,
        approvals: approvals,
        summary: summary(changes),
        content_sha256: content_sha256(ops)
      },
      result.entries
    )
  end

  defp clean(%{conflicts: [], errors: [], halted?: false}), do: :ok
  defp clean(result), do: {:error, {:checks_failed, Preview.summarize(result)}}

  defp checks(organization_id, set, params) do
    ops = ChangeSetStore.staged_ops(set.change_set_id)

    case Preview.run(organization_id, set.mission_id, set.base_revision_number, ops) do
      {:ok, %{verdict: :no_go} = preview} ->
        {:error, {:checks_failed, preview}}

      {:ok, %{verdict: :hold} = preview} ->
        if Map.get(params, :acknowledged_holds) == true,
          do: {:ok, preview},
          else: {:error, {:holds_not_acknowledged, preview}}

      {:ok, preview} ->
        {:ok, preview}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp locked(set, params, fun) do
    Repo.transaction(fn ->
      with {:ok, set} <- ChangeSetStore.lock_set(set.mission_id, set.change_set_id),
           :ok <- state(set, "in_review"),
           :ok <- expected(set, params) do
        fun.(set)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # A reviewed set that can't be applied goes back to its authors, with the reason recorded.
  defp reopen_on_failure(_set, {:ok, _} = result), do: result

  defp reopen_on_failure(set, {:error, reason} = error) do
    if reopen?(reason), do: Repo.transaction(fn -> reopen(set, reason) end)
    error
  end

  defp reopen(set, reason) do
    case ChangeSetStore.lock_set(set.mission_id, set.change_set_id) do
      {:ok, %{state: "in_review"} = locked} ->
        ChangeSetStore.update_set(locked,
          state: "open",
          policy_document: nil,
          failure_document: failure_document(reason)
        )

      _other ->
        :ok
    end
  end

  defp reopen?({:checks_failed, _}), do: true
  defp reopen?(:activation_policy_changed), do: true
  defp reopen?(_reason), do: false

  defp failure_document({:checks_failed, preview}),
    do: Document.normalize(%{"reason" => "checks_failed", "checks" => preview.checks})

  defp failure_document(reason), do: %{"reason" => to_string(reason)}

  defp independent(set, %{"kind" => "user"} = reviewer) do
    reviewer_key = key(reviewer)

    authors =
      set.change_set_id
      |> ChangeSetStore.changes()
      |> Enum.map(& &1.author_key)

    if reviewer_key in [key(set.submitted_by) | authors],
      do: {:error, :reviewer_is_author},
      else: :ok
  end

  defp independent(_set, _reviewer), do: {:error, :forbidden}

  defp insert_review(set, reviewer, decision, comment) do
    Repo.insert!(%ReviewRow{
      review_id: Ids.new("config_review"),
      change_set_id: set.change_set_id,
      organization_id: set.organization_id,
      mission_id: set.mission_id,
      decision: decision,
      actor: reviewer,
      comment: comment,
      decided_at: DateTime.utc_now()
    })
  end

  defp approval(%ReviewRow{} = review) do
    %{
      "actor" => review.actor,
      "comment" => review.comment,
      "decided_at" => DateTime.to_iso8601(review.decided_at)
    }
  end

  defp summary(changes) do
    summaries = Enum.map(changes, & &1.summary)

    case summaries do
      [one] -> one
      [a, b] -> a <> "; " <> b
      [a, b | rest] -> "#{a}; #{b} + #{length(rest)} more"
    end
  end

  defp content_sha256(ops),
    do:
      ops |> Enum.map(&Map.take(&1, [:kind, :entity_id, :action, :payload])) |> Document.sha256()

  defp something_staged(set) do
    if ChangeSetStore.changes(set.change_set_id) == [], do: {:error, :nothing_staged}, else: :ok
  end

  defp state(%{state: state}, state), do: :ok
  defp state(%{state: "in_review"}, "open"), do: {:error, :frozen_in_review}
  defp state(%{state: "open"}, "in_review"), do: {:error, :not_in_review}
  defp state(_set, _state), do: {:error, :change_set_not_found}

  defp expected(%{version: version}, %{expected_version: version}), do: :ok
  defp expected(_set, _params), do: {:error, :change_set_changed}

  defp text(params, field, range, error) do
    case params |> Map.get(field) |> to_string() |> String.trim() do
      value when byte_size(value) >= range.first and byte_size(value) <= range.last ->
        {:ok, value}

      _ ->
        {:error, error}
    end
  end

  defp key(nil), do: nil
  defp key(%{"kind" => kind, "id" => id}), do: kind <> ":" <> id
end
