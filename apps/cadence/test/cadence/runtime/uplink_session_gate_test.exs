defmodule Cadence.Runtime.UplinkSessionGateTest do
  use Cadence.ProcessDataCase, async: false
  alias Cadence.ActionRequests.{ProviderRequest, UplinkRequest}
  alias Cadence.Commanding.VerifierTransportSignals
  alias Cadence.ProviderAdapters.TCPSocket

  alias Cadence.Runtime.{
    MissionRuntime,
    PartitionKey,
    RecoveryExchange,
    SessionReadiness,
    TransportRuntime
  }

  alias Cadence.Runtime.TransportRecords
  alias Cadence.Runtime.TransportRecords.TransportActionRequestRow
  alias Cadence.SessionTestSupport
  alias CCSDS.Transport.COP1.CLCW

  setup do
    Cadence.UplinkSessionFixture.setup()
  end

  test "starts blocked before framing and rejects direct adapter and forged recovery traffic",
       c do
    assert {:error, {:uplink_session_blocked, _}} =
             TransportRuntime.handle_control_input(c.runtime, request())

    assert {:ok, %{state: %{next_frame_seq: 0}, timer_count: 0}} =
             TransportRuntime.snapshot(c.runtime)

    assert {:error, _} = TCPSocket.deliver_uplink(c.provider, provider_request())

    assert {:error, _} =
             TransportRuntime.handle_control_input(
               c.runtime,
               %{request() | metadata: %{"recovery" => true, "ready" => true}}
             )

    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "ordinary sends and COP-1 retransmissions recheck the same readiness generation", c do
    ready(c.runtime)
    assert {:ok, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, first_window} = :gen_tcp.recv(c.peer, 44, 1000)
    assert :ok = TransportRuntime.advance_time(c.runtime, ~U[2026-10-27 00:00:00.100Z])
    assert {:ok, ^first_window} = :gen_tcp.recv(c.peer, 44, 1000)
    {:ok, handle} = TCPSocket.uplink_session(c.provider)
    assert {:ok, _} = SessionReadiness.block(handle, :authority_lost)
    assert {:error, _} = TransportRuntime.advance_time(c.runtime, ~U[2026-10-27 00:00:00.200Z])
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "CLCW-driven retransmission cannot bypass a blocked session", c do
    ready(c.runtime)
    assert {:ok, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, _} = :gen_tcp.recv(c.peer, 44, 1000)
    assert {:ok, _} = TransportRuntime.block_session(c.runtime, :authority_lost)

    assert {:error, _} =
             TransportRuntime.handle_transport_event(
               c.runtime,
               %{kind: :cop1_clcw, clcw: CLCW.new(vcid: 0, report_value: 0, retransmit: 1)}
             )

    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "recovery exchanges are separately verified, exact, one-use, and never ordinary command permits",
       c do
    {:ok, review} = TransportRuntime.session_review(c.runtime)

    assert :ok =
             TransportRuntime.begin_session_recovery(
               c.runtime,
               SessionTestSupport.evidence(review, :fencing)
             )

    {:ok, review} = TransportRuntime.session_review(c.runtime)

    exchange = %RecoveryExchange{
      operation_id: "resync-1",
      purpose: "test-recovery",
      provider_binding_id: "provider",
      provider_adapter_key: :tcp_socket,
      payloads_base64: [Base.encode64(<<42>>)]
    }

    assert {:error, _} =
             TransportRuntime.permit_recovery_exchange(
               c.runtime,
               %{exchange | purpose: "ordinary-command"},
               SessionTestSupport.evidence(review, :exchange)
             )

    {:ok, permit} =
      TransportRuntime.permit_recovery_exchange(
        c.runtime,
        exchange,
        SessionTestSupport.evidence(review, :exchange)
      )

    assert {:error, _} =
             TCPSocket.deliver_uplink(c.provider, %{provider_request() | session_permit: permit})

    assert {:error, _} =
             TransportRuntime.recovery_exchange(
               c.runtime,
               %{exchange | payloads_base64: [Base.encode64(<<43>>)]},
               permit
             )

    assert {:ok, _} = TransportRuntime.recovery_exchange(c.runtime, exchange, permit)
    assert {:ok, <<42>>} = :gen_tcp.recv(c.peer, 1, 1000)
    assert {:error, _} = TransportRuntime.recovery_exchange(c.runtime, exchange, permit)
    assert {:error, _} = TransportRuntime.handle_control_input(c.runtime, request())

    assert {:error, :recovery_exchange_already_used} =
             TransportRuntime.permit_recovery_exchange(
               c.runtime,
               exchange,
               SessionTestSupport.evidence(review, :exchange)
             )

    assert {:ok, %{status: :recovering}} = TransportRuntime.session_review(c.runtime)
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)

    # A fresh gate generation cannot forget an already prepared recovery operation.
    {:ok, _} = TransportRuntime.block_session(c.runtime, :authority_lost)
    {:ok, review} = TransportRuntime.session_review(c.runtime)

    :ok =
      TransportRuntime.begin_session_recovery(
        c.runtime,
        SessionTestSupport.evidence(review, :fencing)
      )

    {:ok, review} = TransportRuntime.session_review(c.runtime)

    {:ok, replacement_permit} =
      TransportRuntime.permit_recovery_exchange(
        c.runtime,
        exchange,
        SessionTestSupport.evidence(review, :exchange)
      )

    assert {:error, :recovery_operation_already_prepared} =
             TransportRuntime.recovery_exchange(c.runtime, exchange, replacement_permit)

    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "queued work from before invalidation cannot send after recovery", c do
    ready(c.runtime)
    {:ok, old_permit} = GenServer.call(c.runtime, :uplink_admission)
    {:ok, _} = TransportRuntime.block_session(c.runtime, :authority_lost)
    ready(c.runtime)

    assert {:error, :invalid_session_permit} =
             GenServer.call(
               c.runtime,
               {:handle_control_input, request(), [session_admission: old_permit]}
             )

    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
    assert {:ok, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, _} = :gen_tcp.recv(c.peer, 44, 1000)
  end

  test "transport death and gate loss revoke direct delivery capability", c do
    ready(c.runtime)
    {:ok, permit} = GenServer.call(c.runtime, :uplink_admission)
    Process.exit(c.runtime, :kill)

    assert {:error, _} =
             TCPSocket.deliver_uplink(c.provider, %{provider_request() | session_permit: permit})

    stop_supervised!(SessionReadiness)
    assert {:error, _} = TCPSocket.deliver_uplink(c.provider, provider_request())
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "direct bypass frames still require ordinary readiness", c do
    bypass =
      start_supervised!(
        Supervisor.child_spec(
          {TransportRuntime,
           process_namespace: c.namespace,
           mission_id: "gate-mission",
           realized_contact_id: "gate-contact",
           path_id: "path",
           activation_id: "activation",
           binding_set_id: "binding",
           binding_set_version: 1,
           capability_instance_id: "bypass",
           family_key: :uplink_gateway,
           configuration: %{
             service_name: "cop1",
             frame_size: 12,
             segment_header_flag: 1,
             bypass_flag: 1,
             cop1_mode: :disabled,
             provider_binding_id: "provider",
             provider_adapter_key: :tcp_socket
           },
           scope_ref: "path",
           partition_key: PartitionKey.new(%{affinity: :path, value: "path"}),
           clock_mode: :replay,
           initial_time: ~U[2026-10-27 00:00:00Z],
           persist_runtime_records?: false},
          id: :bypass
        )
      )

    assert {:error, _} = TransportRuntime.handle_control_input(bypass, request())
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
    ready(bypass)
    {:ok, admission} = TransportRuntime.admit_uplink(bypass)

    assert {:ok, _} =
             TransportRuntime.handle_admitted_control_input(bypass, request(), admission, [])

    assert {:ok, _} = :gen_tcp.recv(c.peer, 44, 1000)

    assert {:error, :invalid_session_permit} =
             TransportRuntime.handle_admitted_control_input(bypass, request(), admission, [])

    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "a replacement connection cannot inherit the old transport's readiness", c do
    ready(c.runtime)
    {:ok, original} = TransportRuntime.session_review(c.runtime)
    Process.exit(c.provider, :kill)
    {:ok, peer} = :gen_tcp.accept(c.listener, 1000)
    on_exit(fn -> :gen_tcp.close(peer) end)

    name =
      MissionRuntime.provider_runtime_name(
        c.namespace,
        "gate-mission",
        "gate-contact",
        "path",
        "provider"
      )

    provider = GenServer.whereis(name)
    assert provider != c.provider
    {:ok, replacement} = TCPSocket.uplink_session(provider)

    assert {:ok, %{status: :blocked, incarnation: incarnation}} =
             SessionReadiness.review(replacement)

    refute incarnation == original.incarnation

    assert {:error, :stale_uplink_session} =
             TransportRuntime.handle_control_input(c.runtime, request())

    assert {:error, :timeout} = :gen_tcp.recv(peer, 0, 25)
  end

  test "recovery does not rearm timers from the previous admission generation", c do
    ready(c.runtime)
    assert {:ok, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, _} = :gen_tcp.recv(c.peer, 44, 1000)
    assert {:ok, %{timers: [old]}} = TransportRuntime.snapshot(c.runtime)
    {:ok, _} = TransportRuntime.block_session(c.runtime, :authority_lost)
    ready(c.runtime)

    send(
      c.runtime,
      {:managed_application_timer, old.capability_instance_id, old.timer_key, old.timer_id}
    )

    assert :ok = TransportRuntime.advance_time(c.runtime, ~U[2026-10-27 00:00:00.200Z])
    assert {:ok, %{timer_count: 0}} = TransportRuntime.snapshot(c.runtime)
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "commits exact frames and counter transition before the provider can send", c do
    ready(c.runtime)
    :ok = :sys.suspend(c.provider)
    task = Task.async(fn -> TransportRuntime.handle_control_input(c.runtime, request()) end)

    try do
      records = await_preparations()
      preparation = hd(records)
      assert preparation.metadata["send_status"] == "prepared"
      assert preparation.command_release_attempt_id == "attempt"
      assert preparation.signal_phase == nil
      assert preparation.request_document["protocol_before"]["next_frame_seq"] == 0
      assert preparation.request_document["protocol_after"]["next_frame_seq"] == 4
      assert preparation.request_document["session_basis"]["resource_id"] == "physical-vc"

      assert [] ==
               VerifierTransportSignals.build([], [
                 TransportActionRequestRow.to_domain(preparation)
               ])

      assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
      :ok = :sys.resume(c.provider)
      assert {:ok, _} = Task.await(task)
      assert {:ok, bytes} = :gen_tcp.recv(c.peer, 44, 1000)

      assert bytes ==
               Enum.flat_map(records, & &1.request_document["frames"])
               |> Enum.map_join(fn frame ->
                 Base.decode64!(frame["bytes_base64"])
               end)

      assert Repo.get!(TransportActionRequestRow, preparation.action_request_id).metadata[
               "send_status"
             ] ==
               "transport_committed"
    after
      :sys.resume(c.provider)
    end
  end

  test "failed preparation sends no bytes and leaves counters unchanged", c do
    ready(c.runtime)
    reject_send_record("INSERT", "NEW.action_kind = 'provider_send_prepared'")

    assert {:error, :transport_send_persistence_unavailable} =
             TransportRuntime.handle_control_input(c.runtime, request())

    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
    assert [] == preparations()
    assert {:ok, %{state: %{next_frame_seq: 0}}} = TransportRuntime.snapshot(c.runtime)
  end

  test "missing local write observation infers uncertainty from sending preparation", c do
    ready(c.runtime)
    reject_send_record("UPDATE", "NEW.metadata->>'send_status' = 'local_write_completed'")
    assert {:error, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, _} = :gen_tcp.recv(c.peer, 12, 1000)
    assert [record | unsent] = preparations()
    assert length(unsent) == 3
    assert Enum.all?(unsent, &(&1.metadata["send_status"] == "prepared"))
    assert record.metadata["send_status"] == "sending"
    assert {:error, :unresolved_transport_send} = TransportRecords.clear?("physical-vc")
    assert {:error, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)

    {:ok, review} = TransportRuntime.session_review(c.runtime)

    assert :ok =
             TransportRuntime.begin_session_recovery(
               c.runtime,
               SessionTestSupport.evidence(review, :fencing)
             )

    {:ok, review} = TransportRuntime.session_review(c.runtime)

    assert {:error, :unresolved_transport_send} =
             TransportRuntime.complete_session_recovery(
               c.runtime,
               SessionTestSupport.evidence(review, :protocol)
             )
  end

  test "failed final confirmation rolls back transport signals and blocks the stream", c do
    :sys.replace_state(c.runtime, &%{&1 | persist_runtime_records?: true})
    ready(c.runtime)
    reject_send_record("UPDATE", "NEW.metadata->>'send_status' = 'transport_committed'")
    assert {:error, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, _} = :gen_tcp.recv(c.peer, 44, 1000)
    assert [record | _] = preparations()
    assert Enum.all?(preparations(), &(&1.metadata["send_status"] == "local_write_completed"))
    assert record.metadata["send_status"] == "local_write_completed"
    assert {:error, :unresolved_transport_send} = TransportRecords.clear?("physical-vc")
    assert {:ok, %{status: :blocked}} = TransportRuntime.session_review(c.runtime)

    refute Repo.exists?(
             from(r in TransportActionRequestRow,
               where: r.mission_id == "gate-mission" and r.action_kind != "provider_send_prepared"
             )
           )

    refute Repo.exists?(
             from(r in "transport_capability_records", where: r.mission_id == "gate-mission")
           )
  end

  test "a transport crash after preparation cannot send or erase unresolved evidence", c do
    ready(c.runtime)
    :ok = :sys.suspend(c.provider)

    task =
      Task.async(fn ->
        try do
          TransportRuntime.handle_control_input(c.runtime, request())
        catch
          :exit, _ -> :runtime_lost
        end
      end)

    try do
      records = await_preparations()
      record = hd(records)
      Process.exit(c.runtime, :kill)
      assert :runtime_lost == Task.await(task)
      :ok = :sys.resume(c.provider)
      assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 50)

      assert "prepared" ==
               Repo.get!(TransportActionRequestRow, record.action_request_id).metadata[
                 "send_status"
               ]

      assert {:error, :unresolved_transport_send} = TransportRecords.clear?("physical-vc")
    after
      :sys.resume(c.provider)
    end
  end

  test "retransmissions persist the original bytes without allocating fresh counters", c do
    ready(c.runtime)
    assert {:ok, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, first} = :gen_tcp.recv(c.peer, 44, 1000)
    assert :ok = TransportRuntime.advance_time(c.runtime, ~U[2026-10-27 00:00:00.100Z])
    assert {:ok, ^first} = :gen_tcp.recv(c.peer, 44, 1000)
    {initials, retries} = Enum.split(preparations(), 4)
    assert length(retries) == 4

    assert Enum.flat_map(initials, & &1.request_document["frames"]) ==
             Enum.flat_map(retries, & &1.request_document["frames"])

    assert Enum.all?(retries, fn retry ->
             retry.request_document["protocol_before"]["next_frame_seq"] == 4 and
               retry.request_document["protocol_after"]["next_frame_seq"] == 4
           end)

    refute hd(initials).action_request_id == hd(retries).action_request_id

    assert {:error, :protocol_state_restore_required} =
             TransportRecords.clear?("physical-vc", "replacement-runtime")
  end

  test "a fresh transport cannot qualify initialized counters over previous sends", c do
    ready(c.runtime)
    assert {:ok, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, _} = :gen_tcp.recv(c.peer, 44, 1000)

    opts =
      c.runtime
      |> :sys.get_state()
      |> Map.to_list()
      |> Keyword.put(:clock_mode, :replay)
      |> Keyword.put(:initial_time, ~U[2026-10-27 00:00:00Z])

    stop_supervised!(TransportRuntime)
    replacement = start_supervised!({TransportRuntime, opts})
    {:ok, review} = TransportRuntime.session_review(replacement)

    :ok =
      TransportRuntime.begin_session_recovery(
        replacement,
        SessionTestSupport.evidence(review, :fencing)
      )

    {:ok, review} = TransportRuntime.session_review(replacement)

    assert {:error, :protocol_state_restore_required} =
             TransportRuntime.complete_session_recovery(
               replacement,
               SessionTestSupport.evidence(review, :protocol)
             )

    assert {:error, _} = TransportRuntime.handle_control_input(replacement, request())
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
  end

  test "an exact session delivery permit cannot bypass durable preparation", c do
    ready(c.runtime)
    request = provider_request()
    {:ok, admission} = TransportRuntime.admit_uplink(c.runtime)
    caller = self()

    :sys.replace_state(c.runtime, fn state ->
      {:ok, permit} =
        SessionReadiness.permit_delivery(
          state.session_handle,
          admission,
          ProviderRequest.digest(request)
        )

      send(caller, {:delivery_permit, permit})
      state
    end)

    assert_receive {:delivery_permit, permit}
    assert {:error, _} = TCPSocket.deliver_uplink(c.provider, %{request | session_permit: permit})
    assert {:error, :timeout} = :gen_tcp.recv(c.peer, 0, 25)
    assert [] == preparations()
  end

  test "failed input after a due retransmission retains committed timer state", c do
    ready(c.runtime)
    assert {:ok, _} = TransportRuntime.handle_control_input(c.runtime, request())
    assert {:ok, first} = :gen_tcp.recv(c.peer, 44, 1000)
    # This deliberately invalid admission is checked after due timers run.
    assert {:error, :invalid_session_permit} =
             GenServer.call(
               c.runtime,
               {:handle_control_input, request(), [occurred_at: ~U[2026-10-27 00:00:00.100Z]]}
             )

    assert {:ok, ^first} = :gen_tcp.recv(c.peer, 44, 1000)
    state = :sys.get_state(c.runtime)
    latest = preparations() |> List.last()

    assert latest.request_document["protocol_after"]["external_term_base64"] ==
             state.extension_state |> :erlang.term_to_binary() |> Base.encode64()

    assert {:ok, %{current_time: ~U[2026-10-27 00:00:00.100Z]}} =
             TransportRuntime.snapshot(c.runtime)
  end

  defp preparations do
    Repo.all(
      from(r in TransportActionRequestRow,
        where: r.action_kind == "provider_send_prepared" and r.mission_id == "gate-mission",
        order_by: [asc: r.requested_at, asc: r.action_request_id]
      )
    )
  end

  defp await_preparations(attempts \\ 100)
  defp await_preparations(0), do: flunk("transport preparation was not committed")

  defp await_preparations(attempts) do
    case preparations() do
      records when length(records) == 4 ->
        records

      [] ->
        Process.sleep(10)
        await_preparations(attempts - 1)
    end
  end

  defp reject_send_record(operation, condition) do
    Repo.query!("""
    CREATE FUNCTION pg_temp.reject_send_record() RETURNS trigger AS $$
    BEGIN
      IF #{condition} THEN RAISE EXCEPTION 'injected send record failure'; END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER reject_send_record BEFORE #{operation} ON transport_action_requests
    FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_send_record()
    """)
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
      command_queue_entry_id: "queue",
      command_request_id: "request",
      source_endpoint_ref: "endpoint",
      mission_model_revision_id: "model",
      command_id: "command",
      command_name: "BURST",
      layout_kind: :command,
      preferred_uplink_service: "cop1",
      encoded_binary_base64: Base.encode64(:binary.copy(<<0xA5>>, 20)),
      encoded_size_bytes: 20
    })
  end

  defp provider_request,
    do:
      ProviderRequest.new(%{
        provider_binding_id: "provider",
        provider_adapter_key: :tcp_socket,
        payloads_base64: [Base.encode64(<<1>>)],
        payload_count: 1
      })
end
