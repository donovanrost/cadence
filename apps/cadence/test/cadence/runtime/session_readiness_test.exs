defmodule Cadence.Runtime.SessionReadinessTest do
  use Cadence.UnitCase, async: true
  alias Cadence.Runtime.{RecoveryExchange, SessionReadiness}
  alias Cadence.SessionTestSupport

  setup do
    gate = start_supervised!({SessionReadiness, policy: SessionTestSupport})
    provider = actor()

    {:ok, connection} =
      as(provider, fn ->
        SessionReadiness.register_provider(gate, "shared-provider-vc", %{
          configuration_sha256: "provider-v1"
        })
      end)

    {:ok, transport} =
      SessionReadiness.attach(connection, %{configuration_sha256: "transport-v1"})

    %{gate: gate, provider: provider, connection: connection, transport: transport}
  end

  test "starts blocked and default policy cannot turn configuration into external authority", c do
    default =
      start_supervised!(%{id: :default_policy, start: {SessionReadiness, :start_link, [[]]}})

    {:ok, connection} =
      as(c.provider, fn -> SessionReadiness.register_provider(default, "raw-tcp", %{}) end)

    {:ok, transport} = SessionReadiness.attach(connection, %{})
    {:ok, review} = SessionReadiness.review(transport)
    assert review.status == :blocked

    assert {:error, :unsupported_takeover} =
             SessionReadiness.begin_recovery(
               transport,
               SessionTestSupport.evidence(review, :fencing)
             )

    assert {:error, {:uplink_session_blocked, :unsupported_takeover}} =
             SessionReadiness.admit(transport)

    assert {:error, :fencing_unproven} =
             SessionReadiness.complete_recovery(
               transport,
               SessionTestSupport.evidence(review, :protocol)
             )
  end

  test "ready delivery binds exact bytes, registered transport, provider and one-use token", c do
    ready(c.transport)
    {:ok, admission} = SessionReadiness.admit(c.transport)
    {:ok, permit} = SessionReadiness.permit_delivery(c.transport, admission, "exact-frame")

    assert {:error, :invalid_session_provider} =
             SessionReadiness.begin_delivery(c.connection, permit, "exact-frame")

    assert {:error, :invalid_session_permit} =
             as(c.provider, fn ->
               SessionReadiness.begin_delivery(c.connection, permit, "different-frame")
             end)

    {:ok, delivery} =
      as(c.provider, fn ->
        SessionReadiness.begin_delivery(c.connection, permit, "exact-frame")
      end)

    assert :ok = as(c.provider, fn -> SessionReadiness.check_delivery(c.connection, delivery) end)

    assert :ok =
             as(c.provider, fn ->
               SessionReadiness.finish_delivery(c.connection, delivery, :ok)
             end)

    assert {:error, :invalid_session_permit} =
             as(c.provider, fn ->
               SessionReadiness.begin_delivery(c.connection, permit, "exact-frame")
             end)
  end

  test "recovery exchanges cannot admit ordinary commands or different payloads", c do
    {:ok, review} = SessionReadiness.review(c.transport)

    exchange = %RecoveryExchange{
      operation_id: "recover-1",
      purpose: "test-recovery",
      provider_binding_id: "provider",
      provider_adapter_key: :tcp_socket,
      payloads_base64: [Base.encode64(<<1>>)]
    }

    assert {:error, :recovery_exchange_not_permitted} =
             SessionReadiness.permit_recovery(
               c.transport,
               exchange,
               SessionTestSupport.evidence(review, :exchange)
             )

    assert :ok =
             SessionReadiness.begin_recovery(
               c.transport,
               SessionTestSupport.evidence(review, :fencing)
             )

    {:ok, review} = SessionReadiness.review(c.transport)

    assert {:error, {:uplink_session_blocked, :protocol_recovery_required}} =
             SessionReadiness.admit(c.transport)

    {:ok, permit} =
      SessionReadiness.permit_recovery(
        c.transport,
        exchange,
        SessionTestSupport.evidence(review, :exchange)
      )

    assert {:error, :invalid_session_permit} =
             as(c.provider, fn -> SessionReadiness.begin_delivery(c.connection, permit, nil) end)

    assert {:error, :invalid_session_permit} =
             as(c.provider, fn ->
               SessionReadiness.begin_delivery(c.connection, permit, "changed")
             end)

    {:ok, delivery} =
      as(c.provider, fn ->
        SessionReadiness.begin_delivery(c.connection, permit, RecoveryExchange.digest(exchange))
      end)

    assert :ok =
             as(c.provider, fn ->
               SessionReadiness.finish_delivery(c.connection, delivery, :ok)
             end)

    assert {:error, :invalid_session_permit} =
             as(c.provider, fn ->
               SessionReadiness.begin_delivery(
                 c.connection,
                 permit,
                 RecoveryExchange.digest(exchange)
               )
             end)
  end

  test "authority loss invalidates queued permits and reports in-flight uncertainty", c do
    ready(c.transport)
    {:ok, admission} = SessionReadiness.admit(c.transport)
    {:ok, permit} = SessionReadiness.permit_delivery(c.transport, admission, "frame")

    {:ok, delivery} =
      as(c.provider, fn -> SessionReadiness.begin_delivery(c.connection, permit, "frame") end)

    assert {:ok, %{pending_delivery_count: 1}} =
             SessionReadiness.block(c.transport, :authority_lost)

    assert {:error, :invalid_session_permit} = SessionReadiness.check(c.transport, admission)

    assert {:error, :invalid_session_delivery} =
             as(c.provider, fn -> SessionReadiness.check_delivery(c.connection, delivery) end)

    {:ok, review} = SessionReadiness.review(c.transport)

    assert {:error, :session_delivery_in_flight} =
             SessionReadiness.begin_recovery(
               c.transport,
               SessionTestSupport.evidence(review, :fencing)
             )

    assert {:error, :send_outcome_unknown} =
             as(c.provider, fn ->
               SessionReadiness.finish_delivery(c.connection, delivery, :ok)
             end)

    assert {:ok, %{status: :blocked, pending_delivery_count: 0, reason: :send_outcome_unknown}} =
             SessionReadiness.review(c.transport)
  end

  test "new binding or transport membership invalidates evidence and prior ready generation", c do
    ready(c.transport)
    {:ok, admission} = SessionReadiness.admit(c.transport)
    {:ok, review} = SessionReadiness.review(c.transport)
    other = actor()

    assert {:ok, _} =
             as(other, fn ->
               SessionReadiness.attach(c.connection, %{configuration_sha256: "transport-v2"})
             end)

    assert {:error, :invalid_session_permit} = SessionReadiness.check(c.transport, admission)

    assert {:error, :session_evidence_basis_changed} =
             SessionReadiness.begin_recovery(
               c.transport,
               SessionTestSupport.evidence(review, :fencing)
             )

    ready(c.transport)
    assert {:error, _} = SessionReadiness.admit(c.transport, admission.generation)
    Process.exit(other, :kill)
    assert {:error, _} = SessionReadiness.admit(c.transport)
  end

  test "separate paths cannot create independent authority for a shared resource", c do
    ready(c.transport)
    {:ok, admission} = SessionReadiness.admit(c.transport)
    other_provider = actor()

    assert {:error, :uplink_resource_conflict} =
             as(other_provider, fn ->
               SessionReadiness.register_provider(c.gate, "shared-provider-vc", %{
                 path_id: "other-path"
               })
             end)

    assert {:error, :invalid_session_permit} = SessionReadiness.check(c.transport, admission)

    assert {:ok, %{status: :blocked, reason: :uplink_resource_conflict}} =
             SessionReadiness.review(c.transport)

    Process.exit(c.provider, :kill)

    {:ok, replacement} =
      as(other_provider, fn ->
        SessionReadiness.register_provider(c.gate, "shared-provider-vc", %{})
      end)

    assert {:error, :stale_uplink_session} = SessionReadiness.review(c.transport)

    assert {:ok, %{status: :blocked, reason: :fencing_unproven}} =
             SessionReadiness.review(replacement)
  end

  test "evidence expiry and reattachment with identical configuration require fresh proof", c do
    {:ok, old_review} = SessionReadiness.review(c.transport)

    {:ok, replacement} =
      SessionReadiness.attach(c.connection, %{configuration_sha256: "transport-v1"})

    assert {:error, :session_evidence_basis_changed} =
             SessionReadiness.begin_recovery(
               replacement,
               SessionTestSupport.evidence(old_review, :fencing)
             )

    {:ok, review} = SessionReadiness.review(replacement)

    assert :ok =
             SessionReadiness.begin_recovery(
               replacement,
               SessionTestSupport.evidence(review, :fencing)
             )

    {:ok, review} = SessionReadiness.review(replacement)

    evidence = %{
      SessionTestSupport.evidence(review, :protocol)
      | valid_until: DateTime.add(DateTime.utc_now(), 250, :millisecond)
    }

    assert :ok = SessionReadiness.complete_recovery(replacement, evidence)
    Process.sleep(275)

    assert {:error, {:uplink_session_blocked, :session_evidence_expired}} =
             SessionReadiness.admit(replacement)
  end

  test "transport death during delivery retains uncertainty without leaking an in-flight slot",
       c do
    transport_pid = actor()

    {:ok, h} =
      as(transport_pid, fn -> SessionReadiness.attach(c.connection, %{binding: "other"}) end)

    ready(h)
    {:ok, admission} = as(transport_pid, fn -> SessionReadiness.admit(h) end)

    {:ok, permit} =
      as(transport_pid, fn -> SessionReadiness.permit_delivery(h, admission, "frame") end)

    {:ok, delivery} =
      as(c.provider, fn -> SessionReadiness.begin_delivery(c.connection, permit, "frame") end)

    Process.exit(transport_pid, :kill)

    assert {:error, :send_outcome_unknown} =
             as(c.provider, fn ->
               SessionReadiness.finish_delivery(c.connection, delivery, :ok)
             end)

    assert {:ok, %{status: :blocked, pending_delivery_count: 0}} =
             SessionReadiness.review(c.connection)
  end

  defp ready(transport) do
    {:ok, review} = SessionReadiness.review(transport)

    :ok =
      SessionReadiness.begin_recovery(transport, SessionTestSupport.evidence(review, :fencing))

    {:ok, review} = SessionReadiness.review(transport)

    :ok =
      SessionReadiness.complete_recovery(
        transport,
        SessionTestSupport.evidence(review, :protocol)
      )
  end

  defp actor,
    do:
      start_supervised!(%{
        id: make_ref(),
        start: {Agent, :start_link, [fn -> nil end]},
        restart: :temporary
      })

  defp as(actor, fun), do: Agent.get(actor, fn _ -> fun.() end)
end
