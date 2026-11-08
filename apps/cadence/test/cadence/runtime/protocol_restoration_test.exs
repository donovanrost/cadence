defmodule Cadence.Runtime.ProtocolRestorationTest do
  use Cadence.ProcessDataCase, async: false
  alias Cadence.ActionRequests.{ProviderRequest, UplinkRequest}
  alias Cadence.Commanding.VerifierTransportSignals
  alias Cadence.Platform.{ContentHash, PreparedSendEvidence}

  alias Cadence.Runtime.{
    ProtocolCheckpoint,
    TransportRecords,
    TransportRuntime
  }

  alias Cadence.Runtime.TransportRecords.{TransportActionRequestRow, TransportCapabilityRecordRow}
  alias Cadence.{SessionTestSupport, UplinkSessionFixture}

  setup do
    c = UplinkSessionFixture.setup()
    :sys.replace_state(c.runtime, &%{&1 | persist_runtime_records?: true})
    c
  end

  test "normal COP-1 commit includes a versioned checkpoint, and export extends its chain", c do
    send_command(c)
    [automatic] = checkpoints()
    assert automatic.state_snapshot["revision"] == 1
    assert ProtocolCheckpoint.valid_hash?(automatic.state_snapshot)
    assert automatic.state_snapshot["protocol"]["implementation"] == "cadence-cop1/v1"
    assert {:ok, exported} = TransportRuntime.export_protocol_checkpoint(c.runtime)
    assert exported["predecessor_id"] == automatic.transport_record_id
    assert exported["revision"] == 2
    assert exported["timers"] |> hd() |> Map.fetch!("due_at") == "2026-10-27T00:00:00.100Z"
    assert [] == VerifierTransportSignals.build(checkpoints(), [])
  end

  test "prepared-send audits preserve checkpoint integrity and cannot grant recovery readiness",
       c do
    send_command(c)
    {:ok, checkpoint} = TransportRuntime.latest_protocol_checkpoint(c.runtime)
    {:ok, [preparation | _]} = TransportRecords.review("physical-vc")

    {:ok, review} =
      TransportRecords.review_prepared_send(
        "gate-org",
        "gate-mission",
        preparation.action_request_id
      )

    evidence = unknown_evidence(preparation, review)

    assert {:ok, %{disposition: "held_unknown", automatic_takeover_allowed?: false}} =
             TransportRecords.reconcile_prepared_send(
               "gate-org",
               "gate-mission",
               preparation.action_request_id,
               evidence
             )

    assert {:error, :unresolved_transport_send} = TransportRecords.clear?("physical-vc")
    assert {:ok, ^checkpoint} = TransportRuntime.latest_protocol_checkpoint(c.runtime)
    replacement = replace_runtime(c.runtime)

    assert {:ok, _} =
             TransportRuntime.restore_protocol_checkpoint(
               replacement,
               checkpoint["checkpoint_id"]
             )

    assert {:error, :protocol_recovery_unqualified} =
             TransportRuntime.complete_session_recovery(replacement, %{})

    assert {:ok, %{timer_count: 0}} = TransportRuntime.snapshot(replacement)
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "a preparation waiting for delivery cannot send after an audit holds its stream", c do
    ready(c.runtime)
    state = :sys.get_state(c.runtime)

    action =
      ProviderRequest.new(%{
        provider_binding_id: "provider",
        provider_adapter_key: :tcp_socket,
        payloads_base64: ["AQ=="],
        payload_count: 1
      })

    {:ok, [prepared]} = TransportRecords.prepare(state, [action], state.extension_state)

    {:ok, review} =
      TransportRecords.review_prepared_send("gate-org", "gate-mission", prepared.preparation_id)

    {:ok, _} =
      TransportRecords.reconcile_prepared_send(
        "gate-org",
        "gate-mission",
        prepared.preparation_id,
        unknown_evidence(review.preparation, review)
      )

    assert {:error, :unresolved_transport_send} =
             TransportRecords.begin_send(:sys.get_state(c.provider), prepared)

    [row] =
      Repo.all(
        from(r in TransportActionRequestRow, where: r.action_kind == "provider_send_prepared")
      )

    assert row.metadata["send_status"] == "prepared"
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "restart restores exact protocol state, preserves expired deadlines and remains blocked",
       c do
    send_command(c)
    {:ok, checkpoint} = TransportRuntime.export_protocol_checkpoint(c.runtime)
    original = :sys.get_state(c.runtime).extension_state
    replacement = replace_runtime(c.runtime)
    assert {:ok, ^checkpoint} = TransportRuntime.latest_protocol_checkpoint(replacement)
    assert :sys.get_state(replacement).protocol_restoration == nil

    assert {:ok, installed} =
             TransportRuntime.restore_protocol_checkpoint(
               replacement,
               checkpoint["checkpoint_id"]
             )

    assert installed.status == :installed_pending_reconciliation
    assert [%{expired?: true, timer_key: "cop1:t1:0"}] = installed.timers
    assert :sys.get_state(replacement).extension_state == original

    assert {:ok,
            %{timer_count: 0, state: %{next_frame_seq: 2, packet_sequence_counts: %{7 => 1}}}} =
             TransportRuntime.snapshot(replacement)

    assert {:error, :protocol_recovery_unqualified} =
             TransportRuntime.handle_control_input(replacement, request())

    assert {:error, :protocol_recovery_unqualified} =
             TransportRuntime.advance_time(replacement, ~U[2026-10-27 00:00:01Z])

    assert {:error, :protocol_recovery_unqualified} =
             TransportRuntime.complete_session_recovery(replacement, %{})

    assert {:ok, ^installed} =
             TransportRuntime.restore_protocol_checkpoint(
               replacement,
               checkpoint["checkpoint_id"]
             )

    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 50)

    assert length(
             Repo.all(
               from(r in TransportCapabilityRecordRow, where: r.event_kind == "protocol_restored")
             )
           ) == 1

    assert Enum.all?(
             Repo.all(
               from(r in TransportActionRequestRow,
                 where: r.action_kind == "provider_send_prepared"
               )
             ),
             &(&1.metadata["send_status"] == "transport_committed")
           )

    assert {:error, :protocol_state_restore_required} =
             TransportRecords.clear?("physical-vc", :sys.get_state(replacement).send_runtime_id)
  end

  test "old checkpoint and changed full send basis are rejected without installing state", c do
    send_command(c)
    [first] = checkpoints()
    {:ok, latest} = TransportRuntime.export_protocol_checkpoint(c.runtime)
    replacement = replace_runtime(c.runtime)

    assert {:error, :stale_protocol_checkpoint} =
             TransportRuntime.restore_protocol_checkpoint(replacement, first.transport_record_id)

    assert {:ok, %{state: %{next_frame_seq: 0}, timer_count: 0}} =
             TransportRuntime.snapshot(replacement)

    [send | _] =
      Repo.all(
        from(r in TransportActionRequestRow, where: r.action_kind == "provider_send_prepared")
      )

    Repo.update!(
      Ecto.Changeset.change(send, metadata: Map.put(send.metadata, "late_observation", "unknown"))
    )

    assert {:error, :protocol_checkpoint_basis_changed} =
             TransportRuntime.restore_protocol_checkpoint(replacement, latest["checkpoint_id"])

    assert :sys.get_state(replacement).protocol_restoration == nil
  end

  test "missing checkpoint predecessors and tampered payloads fail closed", c do
    send_command(c)
    [first] = checkpoints()
    {:ok, latest} = TransportRuntime.export_protocol_checkpoint(c.runtime)
    replacement = replace_runtime(c.runtime)
    Repo.delete!(Repo.get!(TransportCapabilityRecordRow, first.transport_record_id))

    assert {:error, :invalid_protocol_checkpoint_chain} =
             TransportRuntime.restore_protocol_checkpoint(replacement, latest["checkpoint_id"])

    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "changed configuration cannot restore an otherwise valid checkpoint", c do
    send_command(c)
    [checkpoint] = checkpoints()

    replacement =
      replace_runtime(c.runtime, fn opts ->
        Keyword.update!(opts, :configuration, &Map.put(&1, :vcid, 1))
      end)

    assert {:error, :protocol_checkpoint_scope_mismatch} =
             TransportRuntime.restore_protocol_checkpoint(
               replacement,
               checkpoint.transport_record_id
             )

    assert {:ok, %{timer_count: 0, state: %{vcid: 1, next_frame_seq: 0}}} =
             TransportRuntime.snapshot(replacement)
  end

  test "failed durable installation leaves initialized state and permits no sends", c do
    send_command(c)
    [checkpoint] = checkpoints()
    replacement = replace_runtime(c.runtime)
    reject_record("protocol_restored")

    assert {:error, :protocol_checkpoint_persistence_unavailable} =
             TransportRuntime.restore_protocol_checkpoint(
               replacement,
               checkpoint.transport_record_id
             )

    assert {:ok, %{timer_count: 0, state: %{next_frame_seq: 0}}} =
             TransportRuntime.snapshot(replacement)

    assert {:error, _} = TransportRuntime.handle_control_input(replacement, request())
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "checkpoint failure rolls back resulting records and retains a durable send hold", c do
    ready(c.runtime)
    reject_record("protocol_checkpoint")
    assert {:error, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, _} = :gen_tcp.recv(c.peer, 20, 1000)
    assert [] == checkpoints()
    assert {:error, :unresolved_transport_send} = TransportRecords.clear?("physical-vc")

    assert Enum.all?(
             Repo.all(
               from(r in TransportActionRequestRow,
                 where: r.action_kind == "provider_send_prepared"
               )
             ),
             &(&1.metadata["send_status"] == "local_write_completed")
           )
  end

  test "optional-history mode cannot silently produce an incomplete recovery checkpoint", c do
    :sys.replace_state(c.runtime, &%{&1 | persist_runtime_records?: false})

    assert {:error, :protocol_checkpoint_history_required} =
             TransportRuntime.export_protocol_checkpoint(c.runtime)
  end

  test "recovery includes send records older than the operational review window", c do
    send_command(c)

    template =
      Repo.one!(
        from(r in TransportActionRequestRow,
          where: r.action_kind == "provider_send_prepared",
          limit: 1
        )
      )

    attrs = template |> Map.from_struct() |> Map.delete(:__meta__)

    Enum.each(0..104, fn index ->
      id = "history_" <> String.pad_leading(Integer.to_string(index), 3, "0")
      Repo.insert!(struct(TransportActionRequestRow, Map.put(attrs, :action_request_id, id)))
    end)

    {:ok, checkpoint} = TransportRuntime.export_protocol_checkpoint(c.runtime)
    {:ok, review} = TransportRecords.review("physical-vc")
    assert length(review) == 100
    refute Enum.any?(review, &(&1.action_request_id == "history_000"))
    old = Repo.get!(TransportActionRequestRow, "history_000")

    Repo.update!(
      Ecto.Changeset.change(old, metadata: Map.put(old.metadata, "late_evidence", "changed"))
    )

    replacement = replace_runtime(c.runtime)

    assert {:error, :protocol_checkpoint_basis_changed} =
             TransportRuntime.restore_protocol_checkpoint(
               replacement,
               checkpoint["checkpoint_id"]
             )
  end

  test "tampering with a durable checkpoint cannot install its payload", c do
    send_command(c)
    [checkpoint] = checkpoints()
    row = Repo.get!(TransportCapabilityRecordRow, checkpoint.transport_record_id)
    doc = put_in(checkpoint.state_snapshot["protocol"]["schema_version"], 2).state_snapshot
    Repo.update!(Ecto.Changeset.change(row, state_snapshot: %{"value" => doc}))
    replacement = replace_runtime(c.runtime)

    assert {:error, :invalid_protocol_checkpoint_chain} =
             TransportRuntime.restore_protocol_checkpoint(
               replacement,
               checkpoint.transport_record_id
             )

    assert {:ok, %{state: %{next_frame_seq: 0}, timer_count: 0}} =
             TransportRuntime.snapshot(replacement)
  end

  test "new evidence between decoding and installation rejects the recovery proposal", c do
    send_command(c)
    [checkpoint] = checkpoints()
    replacement = replace_runtime(c.runtime)
    registry = GenServer.whereis(c.namespace.capability_registry)
    :sys.suspend(registry)

    task =
      Task.async(fn ->
        TransportRuntime.restore_protocol_checkpoint(replacement, checkpoint.transport_record_id)
      end)

    try do
      await_restore_request(registry)

      send_record =
        Repo.one!(
          from(r in TransportActionRequestRow,
            where: r.action_kind == "provider_send_prepared",
            limit: 1
          )
        )

      Repo.update!(
        Ecto.Changeset.change(send_record,
          metadata: Map.put(send_record.metadata, "late_evidence", "changed")
        )
      )

      :sys.resume(registry)
      assert {:error, :protocol_checkpoint_basis_changed} = Task.await(task)

      assert {:ok, %{state: %{next_frame_seq: 0}, timer_count: 0}} =
               TransportRuntime.snapshot(replacement)

      refute Repo.exists?(
               from(r in TransportCapabilityRecordRow, where: r.event_kind == "protocol_restored")
             )

      assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
    after
      :sys.resume(registry)
    end
  end

  test "incremental timer checkpoints retain earlier frame evidence and exact retry state", c do
    send_command(c)
    assert :ok = TransportRuntime.advance_time(c.runtime, ~U[2026-10-27 00:00:00.100Z])
    assert {:ok, _} = :gen_tcp.recv(c.peer, 20, 1000)
    assert [first, second] = checkpoints()
    assert second.state_snapshot["predecessor_id"] == first.transport_record_id
    assert map_size(first.state_snapshot["evidence"]["sends"]) == 2
    assert map_size(second.state_snapshot["evidence"]["sends"]) == 2
    replacement = replace_runtime(c.runtime)
    assert {:ok, latest} = TransportRuntime.latest_protocol_checkpoint(replacement)
    assert latest["checkpoint_id"] == second.transport_record_id

    assert {:ok, _} =
             TransportRuntime.restore_protocol_checkpoint(replacement, latest["checkpoint_id"])

    assert Enum.all?(
             :sys.get_state(replacement).extension_state.cop1.sent_queue,
             &(&1.frame.retries == 1)
           )

    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  defp await_restore_request(pid, remaining \\ 100)
  defp await_restore_request(_pid, 0), do: flunk("restoration did not reach protocol validation")

  defp await_restore_request(pid, remaining) do
    {:messages, messages} = Process.info(pid, :messages)

    if Enum.any?(
         messages,
         &match?({:"$gen_call", _, {:protocol_checkpoint, :restore_checkpoint, _, _}}, &1)
       ) do
      :ok
    else
      Process.sleep(10)
      await_restore_request(pid, remaining - 1)
    end
  end

  defp unknown_evidence(preparation, review) do
    attrs = %{
      "resolution_id" => "checkpoint-audit",
      "basis_sha256" => review.basis_sha256,
      "source" => "operator_evidence",
      "reference" => "recovery/ticket",
      "evidence_sha256" => ContentHash.term_sha256("evidence"),
      "session_ref" => preparation.metadata["incarnation"],
      "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "frames" =>
        Enum.map(
          review.frame_occurrences,
          &(&1 |> Map.take(~w(frame_id ordinal)) |> Map.put("outcome", "unknown"))
        )
    }

    {:ok, evidence} =
      PreparedSendEvidence.new(%{"kind" => "service", "id" => "reviewer"}, attrs)

    evidence
  end

  defp send_command(c) do
    ready(c.runtime)
    assert {:ok, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, _} = :gen_tcp.recv(c.peer, 20, 1000)
  end

  defp ready(runtime) do
    {:ok, review} = TransportRuntime.session_review(runtime)

    :ok =
      TransportRuntime.begin_session_recovery(
        runtime,
        SessionTestSupport.evidence(review, :fencing)
      )

    {:ok, review} = TransportRuntime.session_review(runtime)

    :ok =
      TransportRuntime.complete_session_recovery(
        runtime,
        SessionTestSupport.evidence(review, :protocol)
      )
  end

  defp request do
    UplinkRequest.new(%{
      command_release_attempt_id: "attempt",
      command_request_id: "request",
      command_queue_entry_id: "queue",
      source_endpoint_ref: "endpoint",
      mission_model_revision_id: "model",
      command_id: "command",
      command_name: "TEST",
      layout_kind: :space_packet,
      apid: 7,
      encoded_binary_base64: Base.encode64(<<1, 2>>),
      encoded_size_bytes: 2
    })
  end

  defp replace_runtime(runtime, transform \\ &Function.identity/1) do
    opts =
      runtime
      |> :sys.get_state()
      |> Map.to_list()
      |> Keyword.put(:clock_mode, :replay)
      |> Keyword.put(:initial_time, ~U[2026-10-27 00:00:00.200Z])
      |> transform.()

    stop_supervised!(TransportRuntime)
    start_supervised!({TransportRuntime, opts})
  end

  defp checkpoints do
    Repo.all(
      from(r in TransportCapabilityRecordRow,
        where: r.event_kind == "protocol_checkpoint",
        order_by: [asc: r.recorded_at]
      )
    )
    |> Enum.map(&TransportCapabilityRecordRow.to_domain/1)
  end

  defp reject_record(kind) do
    Repo.query!("""
    CREATE FUNCTION pg_temp.reject_checkpoint_record() RETURNS trigger AS $$
    BEGIN
      IF NEW.event_kind = '#{kind}' THEN RAISE EXCEPTION 'injected checkpoint failure'; END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER reject_checkpoint_record BEFORE INSERT ON transport_capability_records
    FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_checkpoint_record()
    """)
  end
end
