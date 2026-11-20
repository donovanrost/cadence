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

  require Logger

  alias Cadence.SpacecraftTypeStore

  alias Cadence.Configuration.{
    ChangeSetRow,
    ChangeSetStore,
    Document,
    Ledger,
    Pipeline,
    Preview,
    ReviewRow,
    Staging
  }

  alias Cadence.Governance.{Accountability, ActivationLocks, ActivationPolicy}
  alias Cadence.Ids
  alias Cadence.Repo

  # Apply runs the pipeline and, for profile-framed sets, builds a fleet generation inside one
  # transaction; the default 15 s is too short under load (qa #19), as for activations.
  @apply_timeout_ms 120_000
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
      policy = policy(organization_id, mission_id, set)

      apply_transaction(set, fn ->
        submit_transaction(set, actor, reason, policy, preview, params)
      end)
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

      {:error, {:in_use, _uses}} = error ->
        reopen_on_failure(set, error)

      # #262: a blocking hold that appeared since the submit, or a preview that couldn't run. The
      # set stays in review and nothing is written; it can be approved once the cause clears.
      {:error, {:holds_blocking, _preview}} = error ->
        error

      {:error, {:preview_failed, _cause}} = error ->
        error
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
         result = Pipeline.run(org, mission, set.base_revision_number, ops, actor: applier),
         :ok <- clean(result),
         changes = ChangeSetStore.changes(set.change_set_id),
         {:ok, generation} <-
           generation(%{
             set: set,
             applier: applier,
             approvals: approvals,
             entries: result.entries,
             revision: head.revision_number + 1
           }),
         {:ok, revision} <-
           record(head, set, applier, reason, approvals, changes, ops, {result, generation}) do
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
        activation_id: generation && generation.activation.activation_id,
        generation: generation && generation.activation.generation,
        runtime: if(generation, do: :converging, else: :not_applicable),
        activation_payload: generation,
        degraded_partitions: [],
        impacts: MapSet.to_list(result.impacts),
        kinds: result.entries |> Enum.map(& &1.kind) |> Enum.uniq(),
        # For kinds' after_commit/3 (dropped before the response).
        committed: result.entries
      }
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # The composition layer (configured, so this context has no compile-time edge to it) builds
  # a runtime activation for profile-framed applies; it runs inside this transaction.
  defp generation(input) do
    case Application.get_env(:cadence, :configuration_generation) do
      nil -> {:ok, nil}
      module -> module.build(input)
    end
  end

  defp record(head, set, applier, reason, approvals, changes, ops, {result, generation}) do
    Ledger.record(
      head,
      %{
        kind: if(rolls_back_to(changes), do: "rollback", else: "change_set"),
        rolls_back_to: rolls_back_to(changes),
        change_set_id: set.change_set_id,
        applied_by: applier,
        applied_at: DateTime.utc_now(),
        reason: reason,
        approvals: approvals,
        summary: summary(changes),
        content_sha256: content_sha256(ops),
        activation_id: generation && generation.activation.activation_id,
        generation: generation && generation.activation.generation
      },
      result.entries
    )
  end

  # A rollback's single change carries its target in its source (Rollback, change-sets.md §8).
  defp rolls_back_to(changes) do
    Enum.find_value(changes, fn change ->
      case change.source do
        %{"rollback" => %{"to" => to}} when is_integer(to) -> to
        _other -> nil
      end
    end)
  end

  defp clean(%{conflicts: [], errors: [], halted?: false}), do: :ok
  defp clean(result), do: {:error, failure(Preview.summarize(result))}

  # An op refused because what it archives is still in use (ux U82) answers with the uses, the
  # same {:in_use, %{entity, uses}} as at stage, so the console words both moments alike; entity
  # says which archive in the set it is (ux U82: its row carries the mark).
  defp failure(preview) do
    case in_use(preview) do
      nil -> {:checks_failed, preview}
      refusal -> {:in_use, refusal}
    end
  end

  # The first refused op's %{entity, uses}, as its kind put it on the error.
  defp in_use(%{checks: checks}) do
    errors =
      for check <- checks, item <- check.items, error <- Map.get(item, :errors, []), do: error

    Enum.find_value(errors, &Map.get(&1, :in_use))
  end

  defp checks(organization_id, set, params) do
    ops = ChangeSetStore.staged_ops(set.change_set_id)

    case Preview.run(organization_id, set.mission_id, set.base_revision_number, ops) do
      {:ok, %{verdict: :no_go} = preview} ->
        {:error, failure(preview)}

      {:ok, %{verdict: :hold} = preview} ->
        cond do
          Preview.blocked?(preview) -> {:error, {:holds_blocking, preview}}
          Map.get(params, :acknowledged_holds) == true -> {:ok, preview}
          true -> {:error, {:holds_not_acknowledged, preview}}
        end

      {:ok, preview} ->
        {:ok, preview}

      # #262: Cadence couldn't run the checks (Preview.run's database rescue, or its transaction
      # ending in anything but the preview). Logged here, so a preview bug that fails every time
      # shows up and isn't only retried; the caller gets preview_failed, without the cause.
      {:error, reason} ->
        cause = preview_cause(reason)
        Logger.error("change set #{set.change_set_id}: its checks couldn't run: #{cause}")
        {:error, {:preview_failed, cause}}
    end
  end

  # The cause's first line only: a database error's later lines can carry row values.
  defp preview_cause({:preview_failed, message}) when is_binary(message),
    do: message |> String.split("\n", parts: 2) |> hd()

  defp preview_cause(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp preview_cause(_reason), do: "an unexpected transaction result"

  defp locked(set, params, fun) do
    apply_transaction(set, fn ->
      with {:ok, set} <- ChangeSetStore.lock_set(set.mission_id, set.change_set_id),
           :ok <- state(set, "in_review"),
           :ok <- expected(set, params) do
        fun.(set)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # The memo covers the pipeline and the generation build that follows it in the same
  # transaction: both re-read the same profile versions per spacecraft.
  defp apply_transaction(set, fun) do
    SpacecraftTypeStore.with_version_memo(fn -> timed_transaction(set, fun) end)
  rescue
    DBConnection.ConnectionError -> landed(set)
  end

  # [:cadence, :configuration, :apply_transaction]: how long the apply held its transaction, which
  # has a 120 s timeout (step 4, 11-15). Logged too when it is slow.
  defp timed_transaction(set, fun) do
    started = System.monotonic_time()
    # Policy, then generation, BEFORE the set's rows and the configuration lock the pipeline and
    # the generation take: the one lock order (Governance.ActivationLocks), so an apply can't
    # deadlock with an approval or an execute on its mission.
    result =
      Repo.transaction(
        fn ->
          :ok = ActivationLocks.acquire(set.organization_id, set.mission_id)
          fun.()
        end,
        timeout: @apply_timeout_ms
      )

    duration = System.monotonic_time() - started
    ms = System.convert_time_unit(duration, :native, :millisecond)

    :telemetry.execute(
      [:cadence, :configuration, :apply_transaction],
      %{duration: duration},
      %{
        mission_id: set.mission_id,
        change_set_id: set.change_set_id,
        ok?: match?({:ok, _}, result)
      }
    )

    if ms > 10_000,
      do: Logger.warning("change set #{set.change_set_id} held its apply transaction #{ms} ms")

    result
  end

  # The connection dropped mid-transaction (qa #19), so COMMIT may or may not have reached
  # Postgres. The set's own state says which. A landed apply is reported as applied with its
  # runtime degraded: the generation is committed and the mission reconciler converges on it.
  @doc false
  @spec landed(ChangeSetRow.t()) :: {:ok, map()} | {:error, :apply_interrupted}
  def landed(set) do
    case ChangeSetStore.fetch(set.mission_id, set.change_set_id) do
      {:ok, %{state: "applied", applied_revision_number: number} = applied} ->
        {:ok, recovered(applied, number)}

      {:ok, %{state: "in_review"} = frozen} when set.state == "open" ->
        {:ok, %{state: :in_review, change_set_id: frozen.change_set_id, version: frozen.version}}

      {:ok, %{state: "open"} = reopened} when set.state == "in_review" ->
        {:ok, %{state: :open, change_set_id: reopened.change_set_id, version: reopened.version}}

      _rolled_back ->
        {:error, :apply_interrupted}
    end
  end

  defp recovered(set, number) do
    {:ok, revision} = Ledger.fetch_revision(set.mission_id, number)
    kinds = revision.revision_id |> Ledger.entries() |> Enum.map(& &1.kind) |> Enum.uniq()

    %{
      state: :applied,
      change_set_id: set.change_set_id,
      revision: number,
      staged_count: revision.entry_count,
      activation_id: revision.activation_id,
      generation: revision.generation,
      runtime: if(revision.activation_id, do: :degraded, else: :not_applicable),
      activation_payload: nil,
      degraded_partitions: [],
      impacts: [],
      kinds: kinds
    }
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
  defp reopen?({:in_use, _}), do: true
  defp reopen?(:activation_policy_changed), do: true
  defp reopen?(_reason), do: false

  defp failure_document({:checks_failed, preview}),
    do: Document.normalize(%{"reason" => "checks_failed", "checks" => preview.checks})

  defp failure_document({:in_use, %{entity: entity, uses: uses}}),
    do: Document.normalize(%{"reason" => "in_use", "entity" => entity, "uses" => uses})

  defp failure_document(reason), do: %{"reason" => to_string(reason)}

  # A legacy route conversion batch always goes to review, so its stager can't apply it
  # (reviewer_is_author does the refusing; director 11-16).
  defp policy(organization_id, mission_id, set) do
    evidence = ActivationPolicy.evidence(organization_id, mission_id)

    if Enum.any?(ChangeSetStore.changes(set.change_set_id), &Staging.conversion?(&1.source)),
      do: ActivationPolicy.forced_approval(evidence, "legacy_route_conversion"),
      else: evidence
  end

  @doc """
  Why `viewer` can't review (approve or send back) the set, before they try: `:reviewer_is_author`
  when the set needs approval and they submitted it or authored any of its changes (the same test
  as `review/6`), else nil. For the console's disabled Review.
  """
  @spec review_blocked_reason(String.t(), String.t(), String.t(), map()) ::
          :reviewer_is_author | nil
  def review_blocked_reason(organization_id, mission_id, change_set_id, %{} = viewer) do
    with {:ok, set} <- ChangeSetStore.fetch(mission_id, change_set_id),
         true <- needs_approval?(organization_id, set),
         {:error, :reviewer_is_author} <- independent(set, viewer) do
      :reviewer_is_author
    else
      _reviewable -> nil
    end
  end

  @doc """
  Whether submitting `change_set_id` asks for a second person's approval (Request review) rather
  than applying: the set's recorded policy once submitted, else the mission's, with a legacy route
  conversion's forced approval. The same decision the submit makes, so the console's words for a
  refused submit name the right act (fe-setup on #555).
  """
  @spec needs_approval?(String.t(), String.t(), String.t()) :: boolean()
  def needs_approval?(organization_id, mission_id, change_set_id) do
    case ChangeSetStore.fetch(mission_id, change_set_id) do
      {:ok, set} -> needs_approval?(organization_id, set) == true
      {:error, _not_found} -> false
    end
  end

  defp needs_approval?(organization_id, set) do
    case set.policy_document do
      %{"approval_required" => required} -> required
      _not_submitted -> policy(organization_id, set.mission_id, set)["approval_required"]
    end
  end

  # #280: authors are compared as people: a service author counts as its accountable people
  # (issuer and rotators). No console route lets a service stage today, but the domain allows it;
  # an unknown set refuses with its own code (fail closed), never as if the reviewer authored it.
  defp independent(set, %{"kind" => "user", "id" => reviewer_id}) do
    authors =
      set.change_set_id
      |> ChangeSetStore.changes()
      |> Enum.map(&author_actor(&1.author_key))

    case Accountability.separate(set.organization_id, {:user, reviewer_id}, [
           set.submitted_by | authors
         ]) do
      :ok ->
        :ok

      {:error, {:self, _via}} ->
        {:error, :reviewer_is_author}

      {:error, {:unknown, service}} ->
        {:error, {:change_set_approver_authors_unknown, %{service: service}}}
    end
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

  defp author_actor("user:" <> id), do: {:user, id}
  defp author_actor("service:" <> id), do: {:service, id}
  defp author_actor(_other), do: nil
end
