defmodule Cadence.Commanding.ReleaseResolutionTest do
  use Cadence.ProcessDataCase, async: false
  alias Cadence.{CommandReviewFixtures, ExactCommandAuthoringFixtures}

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandVerifierInstanceRow,
    ReleaseStore,
    RequestQueueStore
  }

  alias Cadence.Control.Commanding
  alias Cadence.MissionModels.RuntimePlanRow

  setup do
    c = CommandReviewFixtures.scope!()

    model =
      ExactCommandAuthoringFixtures.activate!(c.org, c.mission, """
        - name: VERIFIED
          opcode: 4
          parameters: []
          verifiers:
            - name: Started
              phase: start
              timeout_ms: 5000
              success_criteria:
                criteria_type: comparison
                subject_ref: transport:started
                comparison: equal
                value: true
      """)

    request =
      CommandReviewFixtures.request!(c, %{
        lifecycle_state: :validated,
        hazardous: false,
        critical: false,
        mission_model_revision_id: model.revision_id,
        command_id: model.commands_by_name["VERIFIED"]
      })

    {:ok, %{queue_entry: entry}} =
      RequestQueueStore.enqueue_request(
        c.org,
        c.mission,
        request.command_request_id,
        %{"user_id" => c.user.user_id},
        []
      )

    queue = Repo.get!(CommandQueueEntryRow, entry.command_queue_entry_id)
    request = Repo.get!(CommandRequestRow, request.command_request_id)

    attempt =
      CommandReleaseAttempt.new(%{
        organization_id: c.org,
        mission_id: c.mission,
        command_queue_entry_id: queue.command_queue_entry_id,
        command_request_id: request.command_request_id,
        source_endpoint_ref: request.source_endpoint_ref,
        realized_contact_id: "resolution-contact",
        mission_model_revision_id: request.mission_model_revision_id,
        command_id: request.command_id,
        encoded_binary_base64: Base.encode64(<<1>>),
        encoded_size_bytes: 1,
        released_by: %{},
        attempted_at: DateTime.utc_now()
      })

    {:ok, %{attempt: attempt}} = ReleaseStore.claim(queue, request, attempt)

    {:ok, review} =
      Commanding.review_release_resolution(c.scope, c.mission, attempt.command_release_attempt_id)

    {:ok, Map.merge(c, %{attempt: attempt, queue: queue, request: request, review: review})}
  end

  test "unknown is durably audited and keeps the exact lane claim across repeated resolution",
       c do
    attrs = evidence(c, "unknown")
    assert {:ok, result} = resolve(c, attrs)
    assert result.lane_held?
    assert result.release_attempt.lifecycle_state == :release_uncertain

    assert {:error, {:command_queue_lane_release_pending, _}} =
             RequestQueueStore.ensure_lane_not_in_flight(c.org, c.mission, c.queue.queue_lane_key)

    assert {:ok, replay} = resolve(c, attrs)
    assert [entry] = replay.release_attempt.resolution_evidence["entries"]
    assert entry["actor"] == %{"kind" => "user", "id" => c.user.user_id}
    assert is_binary(entry["recorded_at"])
    assert entry["basis_sha256"] == c.review.basis_sha256
    assert entry["disposition"] == "held_unknown"
    assert RequestQueueStore.requeue_release_pending() == 0
    assert {:error, :resolution_id_conflict} = resolve(c, %{attrs | "outcome" => "not_sent"})
  end

  test "accepted evidence completes the original release with its immutable verifiers once", c do
    # Active configuration may move on; recovery uses the stored revision.
    ExactCommandAuthoringFixtures.activate!(c.org, c.mission)
    assert {:ok, result} = resolve(c, evidence(c, "accepted"))
    refute result.lane_held?
    assert result.release_attempt.lifecycle_state == :released
    assert result.release_attempt.verification_state == :pending
    assert result.command_request.verification_state == :pending
    assert [verifier] = Repo.all(CommandVerifierInstanceRow)
    assert verifier.command_release_attempt_id == c.attempt.command_release_attempt_id
    assert {:ok, _} = resolve(c, evidence(c, "accepted"))
    assert [_] = Repo.all(CommandVerifierInstanceRow)
    conflicting = evidence(c, "not_sent", "contradiction")

    assert {:ok, %{disposition: "contradictory", release_attempt: %{lifecycle_state: :released}}} =
             resolve(c, conflicting)

    assert length(
             Repo.get!(CommandReleaseAttemptRow, c.attempt.command_release_attempt_id).resolution_evidence[
               "entries"
             ]
           ) == 2
  end

  test "definitive non-delivery closes the original records without authorizing resend", c do
    assert {:ok, result} = resolve(c, evidence(c, "not_sent"))
    assert result.disposition == "closed_without_resend"
    refute result.lane_held?
    assert result.release_attempt.lifecycle_state == :release_failed
    assert result.queue_entry.lifecycle_state == :canceled
    assert result.command_request.lifecycle_state == :canceled
    assert result.queue_entry.command_queue_entry_id == c.queue.command_queue_entry_id

    assert {:error, _} =
             RequestQueueStore.enqueue_request(
               c.org,
               c.mission,
               c.request.command_request_id,
               %{},
               []
             )

    assert {:ok,
            %{disposition: "contradictory", release_attempt: %{lifecycle_state: :release_failed}}} =
             resolve(c, evidence(c, "accepted", "late-ack"))
  end

  test "stale wire basis, forged actors and unqualified acceptance cannot resolve a claim", c do
    assert {:error, :command_resolution_basis_changed} =
             resolve(c, %{evidence(c, "unknown") | "basis_sha256" => String.duplicate("0", 64)})

    assert {:error, :invalid_resolution_evidence} =
             resolve(c, Map.put(evidence(c, "unknown"), "actor", %{"id" => "forged"}))

    assert {:error, :invalid_resolution_evidence} =
             resolve(c, %{evidence(c, "accepted") | "acceptance_stage" => "socket_send"})

    assert {:error, :invalid_resolution_evidence} =
             resolve(c, %{evidence(c, "not_sent") | "source" => "timeout"})

    assert {:error, :invalid_resolution_evidence} =
             resolve(c, %{evidence(c, "unknown") | "observed_at" => %{}})

    Repo.update!(
      Ecto.Changeset.change(
        Repo.get!(CommandReleaseAttemptRow, c.attempt.command_release_attempt_id),
        encoded_binary_base64: Base.encode64(<<2>>)
      )
    )

    assert {:error, :command_resolution_basis_changed} = resolve(c, evidence(c, "unknown"))

    assert Repo.get!(CommandReleaseAttemptRow, c.attempt.command_release_attempt_id).resolution_evidence ==
             %{}
  end

  test "resolution requires mission authority and cannot cross organization scope", c do
    restricted = %{c.scope | capabilities: MapSet.new()}

    assert {:error, :forbidden} =
             Commanding.resolve_release_attempt(
               restricted,
               c.mission,
               c.attempt.command_release_attempt_id,
               evidence(c, "unknown")
             )

    foreign = CommandReviewFixtures.scope!()

    # L4: another organization's mission is refused by the policy before the attempt is looked up.
    assert {:error, :scope_mismatch} =
             Commanding.resolve_release_attempt(
               foreign.scope,
               c.mission,
               c.attempt.command_release_attempt_id,
               evidence(c, "unknown")
             )
  end

  test "missing original verification basis retains the lane and accepted evidence", c do
    Repo.get_by!(RuntimePlanRow,
      revision_id: c.attempt.mission_model_revision_id,
      target: "command"
    )
    |> Repo.delete!()

    assert {:ok, result} = resolve(c, evidence(c, "accepted"))
    assert result.disposition == "held_verification_basis_unavailable"
    assert result.lane_held?
    assert result.release_attempt.lifecycle_state == :release_pending
    assert [%{"outcome" => "accepted"}] = result.release_attempt.resolution_evidence["entries"]
    assert Repo.all(CommandVerifierInstanceRow) == []
  end

  test "audit capacity failure rolls back completion and verifier creation", c do
    row = Repo.get!(CommandReleaseAttemptRow, c.attempt.command_release_attempt_id)
    entries = Enum.map(1..200, &%{"resolution_id" => "prior-#{&1}"})
    Repo.update!(Ecto.Changeset.change(row, resolution_evidence: %{"entries" => entries}))

    assert {:error, :resolution_evidence_limit} = resolve(c, evidence(c, "accepted"))

    assert Repo.get!(CommandQueueEntryRow, c.queue.command_queue_entry_id).lifecycle_state ==
             "release_pending"

    assert Repo.get!(CommandReleaseAttemptRow, row.command_release_attempt_id).lifecycle_state ==
             "release_pending"

    assert Repo.all(CommandVerifierInstanceRow) == []
  end

  test "audited unknown evidence does not invalidate an original in-flight claim", c do
    assert {:ok, _} = resolve(c, evidence(c, "unknown"))

    assert {:ok, :completed} =
             ReleaseStore.with_claim(c.queue, c.request, c.attempt, fn _queue, _request, row ->
               assert [%{"outcome" => "unknown"}] = row.resolution_evidence["entries"]
               {:ok, :completed}
             end)
  end

  test "audit fields cannot be forged through ordinary attempt persistence", c do
    row = Repo.get!(CommandReleaseAttemptRow, c.attempt.command_release_attempt_id)

    changed =
      CommandReleaseAttemptRow.update_changeset(row, %{
        c.attempt
        | resolution_evidence: %{"entries" => [%{"fake" => true}]}
      })

    assert {:ok, persisted} = Repo.update(changed)
    assert persisted.resolution_evidence == %{}
  end

  defp resolve(c, attrs),
    do:
      Commanding.resolve_release_attempt(
        c.scope,
        c.mission,
        c.attempt.command_release_attempt_id,
        attrs
      )

  defp evidence(c, outcome, id \\ "resolution-1"),
    do: %{
      "resolution_id" => id,
      "basis_sha256" => c.review.basis_sha256,
      "outcome" => outcome,
      "source" => "operator_evidence",
      "reference" => "incident/123",
      "observed_at" => "2026-10-26T00:00:00Z",
      "session_ref" => "original-session",
      "acceptance_stage" => "provider_acceptance"
    }
end
