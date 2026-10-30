defmodule Cadence.Runtime.PreparedSendReconciliationTest do
  use Cadence.ProcessDataCase, async: false
  alias Cadence.{CommandReviewFixtures, Ids}

  alias Cadence.Auth.{Scope, ServiceIdentity}

  alias Cadence.Commanding.{
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandRequestRow,
    ReleaseStore,
    RequestQueueStore,
    VerifierTransportSignals
  }

  alias Cadence.Control.Commanding
  alias Cadence.GroundNetworks.ProviderEvidenceStore
  alias Cadence.Platform.ContentHash
  alias Cadence.Runtime.{TransportActionRequest, TransportRecords}
  alias Cadence.Runtime.TransportRecords.TransportActionRequestRow

  setup do
    c = CommandReviewFixtures.scope!()

    request =
      CommandReviewFixtures.request!(c, %{
        lifecycle_state: :validated,
        hazardous: false,
        critical: false
      })

    {:ok, %{queue_entry: entry}} =
      RequestQueueStore.enqueue_request(c.org, c.mission, request.command_request_id, %{}, [])

    queue = Repo.get!(CommandQueueEntryRow, entry.command_queue_entry_id)
    request = Repo.get!(CommandRequestRow, request.command_request_id)

    attempt =
      CommandReleaseAttempt.new(%{
        organization_id: c.org,
        mission_id: c.mission,
        command_queue_entry_id: queue.command_queue_entry_id,
        command_request_id: request.command_request_id,
        source_endpoint_ref: request.source_endpoint_ref,
        realized_contact_id: "contact",
        mission_model_revision_id: request.mission_model_revision_id,
        command_id: request.command_id,
        encoded_binary_base64: "AQ==",
        encoded_size_bytes: 1,
        released_by: %{},
        attempted_at: DateTime.utc_now()
      })

    {:ok, %{attempt: attempt}} = ReleaseStore.claim(queue, request, attempt)
    c = Map.merge(c, %{attempt: attempt, queue: queue, resource: Ids.new("resource")})
    row = insert_send(c)
    {:ok, review} = Commanding.review_prepared_send(c.scope, c.mission, row.action_request_id)
    Map.merge(c, %{row: row, review: review})
  end

  test "unknown is audited idempotently and preserves original lane and stream holds", c do
    attrs = evidence(c, "unknown")
    assert {:ok, result} = resolve(c, attrs)
    assert result.disposition == "held_unknown"
    assert result.evidence["review_basis"] == c.review.basis
    assert ContentHash.term_sha256(result.evidence["review_basis"]) == c.review.basis_sha256
    assert result.holds_preserved?
    refute result.automatic_takeover_allowed?
    assert result.evidence["actor"] == %{"kind" => "user", "id" => c.user.user_id}
    assert {:ok, ^result} = resolve(c, attrs)
    assert {:error, :resolution_id_conflict} = resolve(c, Map.put(attrs, "note", "changed"))
    assert {:error, :unresolved_transport_send} = TransportRecords.clear?(c.resource)

    assert {:error, {:command_queue_lane_release_pending, _}} =
             RequestQueueStore.ensure_lane_not_in_flight(c.org, c.mission, c.queue.queue_lane_key)

    after_row = Repo.get!(TransportActionRequestRow, c.row.action_request_id)
    assert after_row.metadata == c.row.metadata
    assert after_row.request_document == c.row.request_document
    assert [] == VerifierTransportSignals.build([], [result.preparation])

    assert ContentHash.term_sha256({after_row.request_document, after_row.metadata}) ==
             ContentHash.term_sha256({c.row.request_document, c.row.metadata})
  end

  test "partial and contradictory frame interpretations are retained without resolving an attempt",
       c do
    attrs = evidence(c, "protocol_acknowledged")

    assert {:ok, %{disposition: "held_partial"}} =
             resolve(c, Map.update!(attrs, "frames", &Enum.take(&1, 1)))

    c = refresh(c)
    assert {:ok, %{disposition: "held_contradictory"}} = resolve(c, evidence(c, "not_sent"))
    c = refresh(c)
    assert length(c.review.preparation.reconciliation_evidence["entries"]) == 2

    assert {:error, {:command_queue_lane_release_pending, _}} =
             RequestQueueStore.ensure_lane_not_in_flight(c.org, c.mission, c.queue.queue_lane_key)

    assert {:ok, %{lifecycle_state: :release_pending}} =
             Cadence.Commanding.fetch_command_release_attempt(
               c.org,
               c.mission,
               c.attempt.command_release_attempt_id
             )
  end

  test "complete protocol acknowledgement remains pending qualified recovery and emits no verifier acceptance",
       c do
    assert {:ok, result} = resolve(c, evidence(c, "protocol_acknowledged"))
    assert result.disposition == "recorded_pending_qualified_recovery"
    assert [] == VerifierTransportSignals.build([], [result.preparation])
    assert {:error, :unresolved_transport_send} = TransportRecords.clear?(c.resource)
  end

  test "wrong session and frame occurrences are auditable but uncorrelated", c do
    attrs = evidence(c, "not_sent") |> Map.put("session_ref", "other-session")
    assert {:ok, %{disposition: "held_uncorrelated"}} = resolve(c, attrs)
    c = refresh(c)

    attrs =
      evidence(c, "not_sent")
      |> Map.update!("frames", fn [first | rest] ->
        [Map.put(first, "frame_id", String.duplicate("0", 64)) | rest]
      end)

    assert {:ok, %{disposition: "held_uncorrelated"}} = resolve(c, attrs)
  end

  test "late local observations, new preparations and intervening audits require a fresh full review",
       c do
    attrs = evidence(c, "unknown")

    Repo.update!(
      Ecto.Changeset.change(c.row, metadata: Map.put(c.row.metadata, "send_status", "sending"))
    )

    assert {:error, :stale_reconciliation_basis} = resolve(c, attrs)
    c = refresh(c)
    attrs = evidence(c, "unknown")
    insert_send(c)
    assert {:error, :stale_reconciliation_basis} = resolve(c, attrs)
    c = refresh(c)
    attrs = evidence(c, "unknown")
    assert {:ok, _} = resolve(c, attrs)

    assert {:error, :stale_reconciliation_basis} =
             resolve(c, Map.put(attrs, "resolution_id", Ids.new("resolution")))

    # Exact duplicate remains idempotent even after subsequent observations.
    assert {:ok, _} = resolve(c, attrs)
  end

  test "review covers more than the operational hundred-row limit", c do
    Enum.each(1..101, fn _ -> insert_send(c) end)
    c = refresh(c)
    assert length(c.review.basis["sends"]) == 102
    assert length(c.review.basis["actions"]) == 102
    assert {:ok, _} = resolve(c, evidence(c, "unknown"))
  end

  test "scoped evidence-store references verify their content hash", c do
    {:ok, stored} =
      ProviderEvidenceStore.persist(c.org, "account", %{document: %{"receipt" => "sanitized"}})

    attrs =
      evidence(c, "not_sent") |> Map.put("provider_evidence_id", stored.provider_evidence_id)

    assert {:error, :provider_evidence_mismatch} = resolve(c, attrs)
    attrs = Map.put(attrs, "evidence_sha256", stored.content_sha256)
    assert {:ok, %{disposition: "recorded_pending_qualified_recovery"}} = resolve(c, attrs)
  end

  test "authorization, mission isolation and validated fields apply to both entry points", c do
    other = CommandReviewFixtures.scope!()

    assert {:error, :prepared_send_not_found} =
             Commanding.review_prepared_send(other.scope, other.mission, c.row.action_request_id)

    low = %{c.scope | capabilities: MapSet.new()}

    assert {:error, :forbidden} =
             Commanding.review_prepared_send(low, c.mission, c.row.action_request_id)

    assert {:error, :forbidden} =
             Commanding.reconcile_prepared_send(low, c.mission, c.row.action_request_id, %{})

    attrs = evidence(c, "unknown")

    for invalid <- [
          Map.put(attrs, "actor", %{}),
          Map.put(attrs, "frames", []),
          Map.put(attrs, "observed_at", "9999-01-01T00:00:00Z"),
          Map.put(evidence(c, "not_sent"), "source", "timeout")
        ] do
      assert {:error, :invalid_prepared_send_evidence} = resolve(c, invalid)
    end

    service =
      ServiceIdentity.new(%{
        organization_id: c.org,
        mission_id: c.mission,
        display_name: "Recovery",
        capabilities: [:mission_admin]
      })

    scope =
      Scope.new(%{
        service_identity: service,
        organization: c.scope.organization,
        organization_id: c.org,
        mission_id: c.mission,
        capabilities: [:mission_admin]
      })

    assert {:ok, result} =
             Commanding.reconcile_prepared_send(scope, c.mission, c.row.action_request_id, attrs)

    assert result.evidence["actor"] == %{"kind" => "service", "id" => service.service_identity_id}
  end

  test "concurrent duplicate submissions commit one audit entry", c do
    attrs = evidence(c, "unknown")

    results =
      Task.async_stream(1..2, fn _ -> resolve(c, attrs) end, timeout: 5000) |> Enum.to_list()

    assert [{:ok, {:ok, first}}, {:ok, {:ok, second}}] = results
    assert first == second
    assert length(first.preparation.reconciliation_evidence["entries"]) == 1
  end

  defp refresh(c) do
    {:ok, review} = Commanding.review_prepared_send(c.scope, c.mission, c.row.action_request_id)
    %{c | review: review}
  end

  defp resolve(c, attrs),
    do: Commanding.reconcile_prepared_send(c.scope, c.mission, c.row.action_request_id, attrs)

  defp evidence(c, outcome) do
    %{
      "resolution_id" => Ids.new("resolution"),
      "basis_sha256" => c.review.basis_sha256,
      "source" => "operator_evidence",
      "reference" => "recovery/ticket/1",
      "evidence_sha256" => ContentHash.term_sha256("receipt"),
      "session_ref" => "original-session",
      "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "frames" =>
        Enum.map(c.review.frame_occurrences, fn frame ->
          claim = frame |> Map.take(~w(frame_id ordinal)) |> Map.put("outcome", outcome)

          if outcome == "protocol_acknowledged",
            do: Map.put(claim, "acceptance_stage", "protocol_acceptance"),
            else: claim
        end)
    }
  end

  defp insert_send(c) do
    record = %TransportActionRequest{
      action_request_id: Ids.new("send"),
      mission_id: c.mission,
      realized_contact_id: "contact",
      path_id: "path",
      capability_instance_id: "uplink",
      family_key: :uplink_gateway,
      activation_id: "activation",
      binding_set_id: "bindings",
      binding_set_version: 1,
      partition_affinity: :path,
      partition_value: "path",
      command_release_attempt_id: c.attempt.command_release_attempt_id,
      command_request_id: c.attempt.command_request_id,
      action_kind: :provider_send_prepared,
      requested_at: DateTime.utc_now(),
      request_document: %{
        frames:
          Enum.map(
            0..1,
            &%{
              ordinal: &1,
              frame_id: ContentHash.term_sha256(&1),
              bytes_base64: Base.encode64(<<&1>>)
            }
          )
      },
      metadata: %{
        resource_id: c.resource,
        incarnation: "original-session",
        send_status: "unknown",
        send_runtime_id: "original-runtime"
      }
    }

    Repo.insert!(TransportActionRequestRow.changeset(record))
  end
end
