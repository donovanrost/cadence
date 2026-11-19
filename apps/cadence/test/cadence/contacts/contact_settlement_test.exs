defmodule Cadence.Contacts.ContactSettlementTest do
  @moduledoc "DECISIONS #71: ending a contact never waits on the TSDB, and drops nothing."
  use Cadence.RuntimeCase, async: false

  @moduletag :ingest_journal_matrix

  import Cadence.TestSupport.IngressJournalMatrix, only: [requires_ingress_journal: 0]

  import Ecto.Query

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Contacts

  alias Cadence.Contacts.{
    ContactSettlement,
    ContactSettlementAttention,
    ContactSettler,
    ContactStore
  }

  alias Cadence.Contacts.{
    Path,
    ProviderBinding,
    RealizedContact,
    ScheduledContact,
    TransportBinding
  }

  alias Cadence.OutageTelemetryWriter
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Telemetry.SampleRecords.TelemetrySampleRow
  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.TM.Segmentation

  @frame_size 10
  @apid 42

  setup do
    # The test env's telemetry writer is OutageTelemetryWriter (config/test.exs): the runtime
    # takes its storage policy at boot.
    projector = Application.get_env(:cadence, :ingress_persistence_projector)
    settlement = Application.get_env(:cadence, :contact_settlement)

    Application.put_env(:cadence, :ingress_persistence_projector, retry_max_ms: 200)
    OutageTelemetryWriter.outage(false)

    on_exit(fn ->
      OutageTelemetryWriter.outage(false)
      restore(:ingress_persistence_projector, projector)
      restore(:contact_settlement, settlement)
    end)

    fixture!()
  end

  test "a TSDB outage across one contact's LOS doesn't hold another contact's pass", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    a = schedule!(ctx, "a", DateTime.add(now, -60), DateTime.add(now, 60), downlink: true)
    b = schedule!(ctx, "b", DateTime.add(now, 120), DateTime.add(now, 180), downlink: false)

    assert {:ok, %{realized_scheduled_contact_ids: [a_run]}} =
             Contacts.reconcile(ctx.mission_id, now)

    OutageTelemetryWriter.outage(true)
    send_telemetry!(ctx, a_run, a)

    assert_eventually(fn ->
      projector(ctx, a_run, a).failed_count > 0
    end)

    # A ends while the TSDB is down; B realizes in the same reconcile, which doesn't wait.
    {micros, {:ok, summary}} =
      :timer.tc(fn -> Contacts.reconcile(ctx.mission_id, DateTime.add(now, 130)) end)

    assert micros < 5_000_000
    assert summary.completed_realized_contact_ids == [a_run]
    assert [b_run] = summary.realized_scheduled_contact_ids
    assert summary.errors == []
    assert settlement(ctx, a_run)["state"] == "settling"
    assert Cadence.Runtime.realized_contact_running?(ctx.mission_id, a_run)

    # B completes on schedule and settles while A is still waiting on the TSDB.
    assert {:ok, %{completed_realized_contact_ids: [^b_run]}} =
             Contacts.reconcile(ctx.mission_id, DateTime.add(now, 200))

    assert_eventually(fn -> settlement(ctx, b_run)["state"] == "settled" end)
    refute Cadence.Runtime.realized_contact_running?(ctx.mission_id, b_run)
    assert settlement(ctx, a_run)["state"] == "settling"
    assert samples(ctx) == 0

    # The TSDB returns: A drains, settles and stops. Nothing was lost.
    OutageTelemetryWriter.outage(false)
    assert_eventually(fn -> settlement(ctx, a_run)["state"] == "settled" end)
    refute Cadence.Runtime.realized_contact_running?(ctx.mission_id, a_run)
    assert samples(ctx) == 1
    assert ContactSettlementAttention.items(ctx.organization_id, ctx.mission_id) == []
    assert b.scheduled_contact_id <> "_run" == b_run
  end

  requires_ingress_journal()

  test "past the settling deadline the contact is unsettled, its backlog kept and named", ctx do
    Application.put_env(:cadence, :contact_settlement, deadline_ms: 300)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    a = schedule!(ctx, "a", DateTime.add(now, -60), DateTime.add(now, 60), downlink: true)

    assert {:ok, %{realized_scheduled_contact_ids: [a_run]}} =
             Contacts.reconcile(ctx.mission_id, now)

    journal = journal(ctx, a_run, a)
    OutageTelemetryWriter.outage(true)
    send_telemetry!(ctx, a_run, a)
    assert_eventually(fn -> projector(ctx, a_run, a).failed_count > 0 end)

    assert {:ok, %{completed_realized_contact_ids: [^a_run]}} =
             Contacts.reconcile(ctx.mission_id, DateTime.add(now, 130))

    assert_eventually(fn -> settlement(ctx, a_run)["state"] == "unsettled" end)
    refute Cadence.Runtime.realized_contact_running?(ctx.mission_id, a_run)

    settled = settlement(ctx, a_run)
    assert settled["reason"] == "settle_deadline"
    assert settled["failure_kind"] == "telemetry_storage_unavailable"
    assert settled["failure_message"] =~ "econnrefused"

    assert [
             %{
               "path_id" => path_id,
               "provider_binding_id" => binding_id,
               "from_offset" => 0,
               "to_offset" => bytes,
               "bytes" => bytes,
               "entries" => entries
             }
           ] = settled["unpersisted_journal"]

    assert {path_id, binding_id} == {downlink_path_id(a), provider_binding_id(a)}
    assert entries > 0 and bytes == 2 * @frame_size

    assert %{"entries" => ^entries, "bytes" => ^bytes, "journals" => 1, "lost" => false} =
             settled["backlog"]

    assert settled["journal"] == "enabled"

    # Still on disk, every byte: the journal never reclaims past the processing cursor.
    on_disk =
      journal.stream_path
      |> File.ls!()
      |> Enum.filter(&String.starts_with?(&1, "segment-"))
      |> Enum.map(&File.stat!(Elixir.Path.join(journal.stream_path, &1)).size)
      |> Enum.sum()

    assert on_disk >= bytes

    assert [item] = ContactSettlementAttention.items(ctx.organization_id, ctx.mission_id)
    assert item.id == a_run
    assert item.contact_id == a.scheduled_contact_id
    assert item.conflict == "unsettled"
    assert item.reason == "settle_deadline"
    assert %{entries: ^entries, bytes: ^bytes, journals: 1, lost: false} = item.backlog
    assert item.journal == "enabled"
    assert item.retry == "automatic" and is_nil(item.expires_at)

    assert %{open: 1, acknowledged: 0} =
             ContactSettlementAttention.counts(ctx.organization_id, ctx.mission_id)

    assert samples(ctx) == 0
  end

  test "reconcile settles an ended contact whose runtime outlived it", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    schedule!(ctx, "a", DateTime.add(now, -60), DateTime.add(now, 600), downlink: false)

    assert {:ok, %{realized_scheduled_contact_ids: [a_run]}} =
             Contacts.reconcile(ctx.mission_id, now)

    # As before #71: completed, with no settlement, and its runtime still running.
    {:ok, contact} = ContactStore.fetch_realized(ctx.mission_id, a_run)
    {:ok, _completed} = ContactStore.update_realized_lifecycle(contact, :completed, %{})
    assert Cadence.Runtime.realized_contact_running?(ctx.mission_id, a_run)

    assert {:ok, %{settling_realized_contact_ids: [^a_run], errors: []}} =
             Contacts.reconcile(ctx.mission_id, DateTime.add(now, 10))

    assert_eventually(fn -> settlement(ctx, a_run)["state"] == "settled" end)
    refute Cadence.Runtime.realized_contact_running?(ctx.mission_id, a_run)

    assert {:ok, %{settling_realized_contact_ids: []}} =
             Contacts.reconcile(ctx.mission_id, DateTime.add(now, 20))
  end

  # Domain's partial-frame fix (11-15): what a stream gave up at its end is kept with the settlement.
  test "the bytes a stream gave up at its end are stored per path, and a later empty read keeps them",
       ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    schedule!(ctx, "a", DateTime.add(now, -60), DateTime.add(now, 600), downlink: false)

    {:ok, %{realized_scheduled_contact_ids: [a_run]}} = Contacts.reconcile(ctx.mission_id, now)
    {:ok, contact} = ContactStore.fetch_realized(ctx.mission_id, a_run)

    given_up = [
      %{
        path_id: "path-1",
        provider_binding_id: "binding-1",
        frame_bytes: 37,
        packet_octets: 12,
        journal_bytes: 49
      }
    ]

    {:ok, _} = ContactSettlement.record(contact, :settled, %{}, :ok, nil, given_up)

    assert settlement(ctx, a_run)["incomplete_at_end"] == [
             %{
               "path_id" => "path-1",
               "provider_binding_id" => "binding-1",
               "frame_bytes" => 37,
               "packet_octets" => 12,
               "journal_bytes" => 49
             }
           ]

    # A later settle (the runtime already gone: it reads nothing) keeps the one record.
    {:ok, contact} = ContactStore.fetch_realized(ctx.mission_id, a_run)
    {:ok, _} = ContactSettlement.record(contact, :absent, %{}, :ok, nil, [])
    assert [%{"journal_bytes" => 49}] = settlement(ctx, a_run)["incomplete_at_end"]
  end

  test "a lost backlog (journal off) closes only when an operator marks it seen", ctx do
    lost = settled_contact!(ctx, %{"lost" => true, "queued" => 3})
    kept = settled_contact!(ctx, %{"lost" => false})
    scope = TelemetryDecomFixtures.user_scope(ctx.organization_id, "op")

    assert {:error, :attention_item_not_found} =
             ContactSettlementAttention.acknowledge(scope, ctx.mission_id, kept)

    assert {:ok, %{state: "resolved", resolution: %{action: "acknowledged", actor: actor}}} =
             ContactSettlementAttention.acknowledge(scope, ctx.mission_id, lost)

    assert actor["id"] == scope.user.user_id

    assert {:error, :attention_item_not_found} =
             ContactSettlementAttention.acknowledge(scope, ctx.mission_id, lost)

    assert [%{id: ^kept}] = ContactSettlementAttention.items(ctx.organization_id, ctx.mission_id)

    assert [%{id: ^lost, action: "acknowledged", resolved_by: %{"kind" => "user"}}] =
             ContactSettlementAttention.resolved_since(
               ctx.organization_id,
               ctx.mission_id,
               DateTime.add(DateTime.utc_now(), -60)
             )

    assert {:error, :attention_item_not_found} =
             ContactSettlementAttention.resolve(scope, ctx.mission_id, lost, "x")
  end

  describe "replay (#71 follow-up)" do
    requires_ingress_journal()

    test "an unsettled contact replays when storage is back; nothing is lost or doubled", ctx do
      {a_run, _a} = unsettled_contact!(ctx)
      OutageTelemetryWriter.outage(false)

      assert {:ok, %{replaying_realized_contact_ids: [^a_run], errors: []}} =
               Contacts.reconcile(ctx.mission_id, DateTime.utc_now())

      assert_eventually(fn -> settlement(ctx, a_run)["state"] == "settled" end)
      assert settlement(ctx, a_run)["replayed_at"]
      refute Cadence.Runtime.realized_contact_running?(ctx.mission_id, a_run)
      assert samples(ctx) == 1
      assert ContactSettlementAttention.items(ctx.organization_id, ctx.mission_id) == []

      assert [%{id: ^a_run, action: "replayed"}] =
               ContactSettlementAttention.resolved_since(
                 ctx.organization_id,
                 ctx.mission_id,
                 DateTime.add(DateTime.utc_now(), -60)
               )

      assert {:ok, %{replaying_realized_contact_ids: []}} =
               Contacts.reconcile(ctx.mission_id, DateTime.utc_now())
    end

    requires_ingress_journal()

    test "a failing replay backs off, stops after 6 for an operator, who can retry", ctx do
      Application.put_env(:cadence, :contact_settlement,
        deadline_ms: 300,
        replay_deadline_ms: 300
      )

      {a_run, _a} = unsettled_contact!(ctx)

      for attempt <- 1..6 do
        assert {:ok, %{replaying_realized_contact_ids: [^a_run]}} =
                 Contacts.reconcile(ctx.mission_id, DateTime.utc_now())

        assert_eventually(fn ->
          settlement(ctx, a_run)["attempts"] == attempt and
            not ContactSettler.replaying?(ctx.mission_id)
        end)

        if attempt < 6 do
          assert %{"retry" => "automatic", "next_attempt_at" => next} = settlement(ctx, a_run)
          {:ok, next, _} = DateTime.from_iso8601(next)
          assert DateTime.diff(next, DateTime.utc_now()) > 4 * 60

          # Not due yet: nothing replays until the backoff passes.
          assert {:ok, %{replaying_realized_contact_ids: []}} =
                   Contacts.reconcile(ctx.mission_id, DateTime.utc_now())

          make_due!(ctx, a_run)
        end
      end

      assert %{"retry" => "manual", "next_attempt_at" => nil} = settlement(ctx, a_run)

      assert {:ok, %{replaying_realized_contact_ids: []}} =
               Contacts.reconcile(ctx.mission_id, DateTime.utc_now())

      scope = TelemetryDecomFixtures.user_scope(ctx.organization_id, "op")

      assert {:ok, %{retry: "automatic", attempts: 0}} =
               ContactSettlementAttention.retry(scope, ctx.mission_id, a_run)

      assert {:error, {:retry_not_manual, %{id: ^a_run}}} =
               ContactSettlementAttention.retry(scope, ctx.mission_id, a_run)

      OutageTelemetryWriter.outage(false)

      assert {:ok, %{replaying_realized_contact_ids: [^a_run]}} =
               Contacts.reconcile(ctx.mission_id, DateTime.utc_now())

      assert_eventually(fn -> settlement(ctx, a_run)["state"] == "settled" end)
      assert samples(ctx) == 1
    end

    requires_ingress_journal()

    test "a contact that ended before #71 with a journal backlog is found and drained", ctx do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      a = schedule!(ctx, "a", DateTime.add(now, -60), DateTime.add(now, 600), downlink: true)

      assert {:ok, %{realized_scheduled_contact_ids: [a_run]}} =
               Contacts.reconcile(ctx.mission_id, now)

      OutageTelemetryWriter.outage(true)
      send_telemetry!(ctx, a_run, a)
      assert_eventually(fn -> projector(ctx, a_run, a).failed_count > 0 end)

      # As before #71: the runtime died with its contact ended and no settlement recorded.
      :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, a_run)
      {:ok, contact} = ContactStore.fetch_realized(ctx.mission_id, a_run)
      {:ok, _} = ContactStore.update_realized_lifecycle(contact, :completed, %{})
      OutageTelemetryWriter.outage(false)

      assert {:ok, %{replaying_realized_contact_ids: [^a_run], errors: []}} =
               Contacts.reconcile(ctx.mission_id, DateTime.add(now, 10))

      assert_eventually(fn -> settlement(ctx, a_run)["state"] == "settled" end)
      assert settlement(ctx, a_run)["inspected_at"]
      refute settlement(ctx, a_run)["replayed_at"]
      assert samples(ctx) == 1
    end
  end

  describe "replay bookkeeping (#71 follow-up, 39LEY)" do
    requires_ingress_journal()

    test "a never-inspected contact whose first replay failed is inspected once it drains", ctx do
      Application.put_env(:cadence, :contact_settlement,
        deadline_ms: 300,
        replay_deadline_ms: 300
      )

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      a = schedule!(ctx, "a", DateTime.add(now, -60), DateTime.add(now, 600), downlink: true)

      assert {:ok, %{realized_scheduled_contact_ids: [a_run]}} =
               Contacts.reconcile(ctx.mission_id, now)

      OutageTelemetryWriter.outage(true)
      send_telemetry!(ctx, a_run, a)
      assert_eventually(fn -> projector(ctx, a_run, a).failed_count > 0 end)

      # As 39LEY: settled with no runtime to drain (a node stop mid-pass), journal not inspected.
      :ok = Cadence.Runtime.terminate_realized_contact(ctx.mission_id, a_run)
      {:ok, contact} = ContactStore.fetch_realized(ctx.mission_id, a_run)

      absent = %{
        "state" => "settled",
        "runtime" => "absent",
        "settled_at" => "2026-11-14T01:44:30Z"
      }

      {:ok, _} =
        ContactStore.update_realized_lifecycle(contact, :completed, %{"settlement" => absent})

      # Its first replay fails (storage still down): unsettled.
      assert {:ok, %{replaying_realized_contact_ids: [^a_run]}} =
               Contacts.reconcile(ctx.mission_id, DateTime.add(now, 10))

      assert_eventually(fn ->
        settlement(ctx, a_run)["state"] == "unsettled" and
          not ContactSettler.replaying?(ctx.mission_id)
      end)

      # Storage is back: the due replay drains it.
      OutageTelemetryWriter.outage(false)
      make_due!(ctx, a_run)

      assert {:ok, %{replaying_realized_contact_ids: [^a_run]}} =
               Contacts.reconcile(ctx.mission_id, DateTime.add(now, 20))

      assert_eventually(fn ->
        settlement(ctx, a_run)["state"] == "settled" and
          not ContactSettler.replaying?(ctx.mission_id)
      end)

      assert %{"replayed_at" => replayed, "inspected_at" => inspected} = settlement(ctx, a_run)
      assert replayed == inspected
      assert samples(ctx) == 1

      # Drained once: nothing picks it again (39LEY replayed twice, doubling its observations).
      assert {:ok, %{replaying_realized_contact_ids: []}} =
               Contacts.reconcile(ctx.mission_id, DateTime.add(now, 30))
    end
  end

  defp unsettled_contact!(ctx) do
    if Application.get_env(:cadence, :contact_settlement) == nil,
      do: Application.put_env(:cadence, :contact_settlement, deadline_ms: 300)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    a = schedule!(ctx, "a", DateTime.add(now, -60), DateTime.add(now, 60), downlink: true)

    assert {:ok, %{realized_scheduled_contact_ids: [a_run]}} =
             Contacts.reconcile(ctx.mission_id, now)

    OutageTelemetryWriter.outage(true)
    send_telemetry!(ctx, a_run, a)
    assert_eventually(fn -> projector(ctx, a_run, a).failed_count > 0 end)

    assert {:ok, %{completed_realized_contact_ids: [^a_run]}} =
             Contacts.reconcile(ctx.mission_id, DateTime.add(now, 130))

    assert_eventually(fn -> settlement(ctx, a_run)["state"] == "unsettled" end)
    {a_run, a}
  end

  defp make_due!(ctx, realized_contact_id) do
    {:ok, contact} = ContactStore.fetch_realized(ctx.mission_id, realized_contact_id)

    settlement =
      Map.put(
        contact.metadata["settlement"],
        "next_attempt_at",
        DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -1))
      )

    {:ok, _} =
      ContactStore.update_realized_lifecycle(contact, contact.lifecycle_state, %{
        "settlement" => settlement
      })
  end

  ## Fixture

  defp settled_contact!(ctx, backlog) do
    id = "realized-#{System.unique_integer([:positive])}"

    {:ok, _contact} =
      ContactStore.persist_realized(
        RealizedContact.new(%{
          realized_contact_id: id,
          organization_id: ctx.organization_id,
          mission_id: ctx.mission_id,
          source_endpoint_refs: [ctx.endpoint_id],
          clock_mode: :live,
          initial_time: DateTime.utc_now(),
          lifecycle_state: :completed,
          metadata: %{
            "settlement" => %{
              "state" => "unsettled",
              "reason" => "settle_deadline",
              "unsettled_at" => DateTime.to_iso8601(DateTime.utc_now()),
              "backlog" => Map.merge(%{"entries" => 0, "bytes" => 0, "journals" => 0}, backlog)
            }
          }
        })
      )

    id
  end

  defp fixture! do
    organization_id = "org-settlement-#{System.unique_integer([:positive])}"
    suffix = Integer.to_string(System.unique_integer([:positive]))
    mission_id = "mission-settlement-" <> suffix
    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-settlement-" <> suffix,
        mission_id: mission_id,
        display_name: "SC settlement"
      })

    {:ok, _} = Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    {:ok, endpoint} =
      Cadence.SourceEndpoints.persist_source_endpoint(
        organization_id,
        SourceEndpoint.new(%{
          source_endpoint_id: "endpoint-settlement-" <> suffix,
          mission_id: mission_id,
          spacecraft_id: spacecraft.spacecraft_id,
          source_ref: "provider/tcp"
        })
      )

    packet =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "packet-settlement-" <> suffix,
        packet_name: "TMHK",
        apid: @apid,
        version: 1,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    {:ok, binding_set} =
      Cadence.Governance.persist_binding_set(
        organization_id,
        BindingSet.new(%{
          mission_id: mission_id,
          binding_set_id: "settlement-basis-" <> suffix,
          version: 1,
          rules: [
            BindingRule.new(%{
              binding_rule_id: "settlement-telemetry-rule-" <> suffix,
              handler_key: :definition_bound_telemetry,
              packet_kind: :space_packet,
              apid: @apid,
              priority: 10,
              handler_configuration: packet
            })
          ]
        })
      )

    {:ok, _activation} =
      Cadence.ActivationFixtures.activate_binding_set(
        organization_id,
        mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        activated_by: %{"service_identity_id" => "svc-test"}
      )

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      endpoint_id: endpoint.source_endpoint_id
    }
  end

  defp schedule!(ctx, name, starts_at, ends_at, downlink: downlink?) do
    id = "#{name}-#{System.unique_integer([:positive])}"

    contact =
      ScheduledContact.new(%{
        scheduled_contact_id: id,
        mission_id: ctx.mission_id,
        source_endpoint_refs: [ctx.endpoint_id],
        starts_at: starts_at,
        ends_at: ends_at,
        paths: paths(ctx, id, downlink?)
      })

    {:ok, scheduled} = Contacts.persist_scheduled_contact(ctx.organization_id, contact)
    scheduled
  end

  defp paths(ctx, id, true) do
    [
      Path.new(%{
        path_id: "downlink-#{id}",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: ctx.endpoint_id,
        provider_bindings: [
          ProviderBinding.new(%{
            provider_binding_id: "provider-#{id}",
            adapter_key: :tcp_socket,
            configuration: %{
              mode: :listen,
              port: 0,
              ingress_protocol_family: :tm,
              frame_size: @frame_size,
              ingress_metadata: %{frame_size: @frame_size, ocf_length: 0}
            }
          })
        ]
      })
    ]
  end

  defp paths(ctx, id, false) do
    [
      Path.new(%{
        path_id: "downlink-#{id}",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: ctx.endpoint_id,
        transport_bindings: [
          TransportBinding.new(%{
            transport_binding_id: "heartbeat-#{id}",
            family_key: :heartbeat_monitor,
            target_scope: :transport,
            configuration: %{"heartbeat_interval_ms" => 25}
          })
        ]
      })
    ]
  end

  defp downlink_path_id(%ScheduledContact{scheduled_contact_id: id}), do: "downlink-#{id}"
  defp provider_binding_id(%ScheduledContact{scheduled_contact_id: id}), do: "provider-#{id}"

  defp provider(ctx, realized_contact_id, scheduled) do
    {:ok, snapshot} =
      Cadence.path_runtime_snapshot(
        ctx.organization_id,
        ctx.mission_id,
        realized_contact_id,
        downlink_path_id(scheduled)
      )

    [provider] = snapshot.provider_runtimes
    provider
  end

  defp projector(ctx, id, scheduled),
    do: provider(ctx, id, scheduled).ingress_persistence_projector

  defp journal(ctx, id, scheduled), do: provider(ctx, id, scheduled).ingress_journal

  defp send_telemetry!(ctx, realized_contact_id, scheduled) do
    port = provider(ctx, realized_contact_id, scheduled).port
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, packet: 0, active: false])
    on_exit(fn -> :gen_tcp.close(socket) end)
    [one, two] = tm_frames(@apid, 4, <<0, 21>>)
    :ok = :gen_tcp.send(socket, one <> two)
  end

  defp settlement(ctx, realized_contact_id) do
    {:ok, contact} = ContactStore.fetch_realized(ctx.mission_id, realized_contact_id)
    contact.metadata["settlement"] || %{}
  end

  defp samples(ctx) do
    TelemetrySampleRow
    |> where([row], row.mission_id == ^ctx.mission_id)
    |> Repo.aggregate(:count, :sample_id)
  end

  defp restore(key, nil), do: Application.delete_env(:cadence, key)
  defp restore(key, value), do: Application.put_env(:cadence, key, value)

  defp assert_eventually(fun, attempts \\ 200)
  defp assert_eventually(_fun, 0), do: flunk("condition was not satisfied in time")

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp tm_frames(apid, sequence_count, packet_data) do
    packet =
      <<0::3, 0::1, 0::1, apid::11, 3::2, sequence_count::14, byte_size(packet_data) - 1::16,
        packet_data::binary>>

    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, segmentation} = Segmentation.init([])

    {:ok, encoded, _segmentation} =
      Segmentation.segment_encode(
        sdu,
        %{frame_size: @frame_size, ocf_length: 0},
        segmentation,
        []
      )

    for <<frame::binary-size(@frame_size) <- encoded>>, do: frame
  end
end
