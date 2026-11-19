defmodule Cadence.Control.UplinkReadinessTest do
  @moduledoc "Uplink readiness, the uplink_blocked attention source and Recover uplink (#58)."
  use Cadence.DataCase, async: false

  import Ecto.Query
  import Cadence.CommandGroupFixtures

  alias Cadence.Commanding.CommandRequestRow
  alias Cadence.Contacts.ContactStore.ScheduledContactRow
  alias Cadence.Contacts.{ScheduledContact, UplinkPasses}
  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Control.{UplinkQualification, UplinkReadiness}
  alias Cadence.Control.UplinkReadiness.{Attention, Groups}
  alias Cadence.GroundNetworks.ProviderAudit
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Runtime.ProcessNamespace

  defmodule FakeDriver do
    @moduledoc false
    use GenServer
    def start_link(reply), do: GenServer.start_link(__MODULE__, reply)
    def init(reply), do: {:ok, reply}
    def handle_call({:requalify, key}, _from, reply), do: {:reply, reply.(key), reply}
  end

  defmodule FakeSession do
    @moduledoc false
    # A provider uplink session whose recovery is refused, and which can't be reviewed after
    # (as a failed challenge can leave it).
    use GenServer
    def start_link(args), do: GenServer.start_link(__MODULE__, args)

    def init({registry, {m, c, p, b} = key, test}) do
      {:ok, _} = Registry.register(registry, {:transport_runtime, m, c, p, b}, nil)
      {:ok, %{key: key, refused?: false, test: test}}
    end

    def handle_call({:session_action, :drop_peer, [peer, reason]}, _from, state) do
      send(state.test, {:dropped, peer, reason})
      {:reply, :ok, state}
    end

    def handle_call({:session_action, :review, []}, _from, %{refused?: true} = state),
      do: {:reply, {:error, :session_blocked}, state}

    def handle_call({:session_action, :review, []}, _from, %{key: {m, c, _p, _b}} = state) do
      provider = %{
        adapter_key: :tcp_socket,
        peer: "127.0.0.1:50123",
        mission_id: m,
        contact_id: c
      }

      {:reply,
       {:ok,
        %{
          provider: provider,
          status: :blocked,
          pending_delivery_count: 0,
          incarnation: 1,
          basis_sha256: "basis"
        }}, state}
    end

    def handle_call({:session_action, :begin_recovery, [_evidence]}, _from, state),
      do: {:reply, {:error, :attestation_peer_mismatch}, %{state | refused?: true}}
  end

  defmodule ReadySession do
    @moduledoc false
    # A qualified provider uplink session with deliveries pending (kept, not re-challenged),
    # whose snapshot answers with the given reply, or exits when it is `:exit`.
    use GenServer
    def start_link(args), do: GenServer.start_link(__MODULE__, args)

    def init({registry, {m, c, p, b} = key, snapshot}) do
      {:ok, _} = Registry.register(registry, {:transport_runtime, m, c, p, b}, nil)
      {:ok, %{key: key, snapshot: snapshot}}
    end

    def handle_call({:session_action, :review, []}, _from, %{key: {m, c, _p, _b}} = state) do
      provider = %{
        adapter_key: :tcp_socket,
        peer: "127.0.0.1:50124",
        mission_id: m,
        contact_id: c
      }

      {:reply,
       {:ok,
        %{
          provider: provider,
          status: :ready,
          pending_delivery_count: 1,
          incarnation: 1,
          basis_sha256: "basis"
        }}, state}
    end

    def handle_call(:snapshot, _from, %{snapshot: :exit} = state), do: {:stop, :normal, state}
    def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}
  end

  defmodule AttestingClient do
    @moduledoc false
    def attest_uplink_session(_context, _contact, _attrs, _opts),
      do: {:ok, %{"valid_until" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 240))}}
  end

  setup do
    c = setup!(2)
    table = :"uplink_readiness_#{System.unique_integer([:positive])}"
    UplinkReadiness.create_table(table)
    [sc | _] = c.spacecraft

    Map.merge(c, %{table: table, sc: sc, key: {c.mission, "realized-1", "uplink-path", "gateway"}})
  end

  defp pass(c, overrides \\ %{}) do
    now = DateTime.utc_now()

    Map.merge(
      %{
        organization_id: c.org,
        mission_id: c.mission,
        scheduled_contact_id: "contact-live",
        provider_reservation_id: "reservation-live",
        provider_contact_ref: "provider-contact-live",
        provider_id: "provider-1",
        spacecraft_id: c.sc,
        ground_station_ref: "earendil-kiruna",
        starts_at: DateTime.add(now, -60),
        ends_at: DateTime.add(now, 540)
      },
      overrides
    )
  end

  defp record(c, state, reason, at \\ DateTime.utc_now()),
    do: UplinkReadiness.record(c.table, c.key, pass(c), state, reason, at)

  defp queued_group!(c) do
    draft = draft([c.sc], [command(c, "SET_SIGNED", %{"counter" => 1})])

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    Repo.update_all(
      from(r in CommandRequestRow, where: r.command_group_id == ^group.command_group_id),
      set: [lifecycle_state: "queued"]
    )

    group.command_group_id
  end

  test "readiness keeps `since` while unchanged and records a blocked pass recovering", c do
    t0 = ~U[2026-11-10 20:18:40Z]
    record(c, :qualifying, :cop1_awaiting_clcw, t0)
    record(c, :blocked, :attestation_signature_invalid, DateTime.add(t0, 2))
    record(c, :blocked, :attestation_signature_invalid, DateTime.add(t0, 17))

    assert %{
             "contact-live" => %{
               state: :blocked,
               reason: :attestation_signature_invalid,
               since: since
             }
           } =
             UplinkReadiness.for_contacts(c.org, c.mission, ["contact-live", "other"], c.table)

    assert since == DateTime.add(t0, 2)

    record(c, :ready, nil, DateTime.add(t0, 30))

    assert [%{action: "uplink recovered", resolved_at: resolved_at}] =
             UplinkReadiness.resolved_since(c.org, c.mission, t0, c.table)

    assert resolved_at == DateTime.add(t0, 30)

    assert UplinkReadiness.for_contacts(c.org, "another-mission", ["contact-live"], c.table) ==
             %{}
  end

  test "a blocked pass with queued groups is an open uplink_blocked item until the pass ends",
       c do
    record(c, :blocked, :protocol_state_restore_required)
    assert Attention.items(c.org, c.mission, c.table) == []

    group_id = queued_group!(c)

    assert [
             %{
               id: "contact-live",
               source: "uplink_blocked",
               state: "open",
               reason: "protocol_state_restore_required",
               command_group_ids: [^group_id],
               spacecraft_id: spacecraft_id
             }
           ] = Attention.items(c.org, c.mission, c.table)

    assert spacecraft_id == c.sc
    assert %{open: 1, acknowledged: 0} = Attention.counts(c.org, c.mission, c.table)

    UplinkReadiness.forget(c.table, c.key, DateTime.utc_now())
    assert Attention.items(c.org, c.mission, c.table) == []

    assert [%{source: "uplink_blocked", action: "pass ended", resolved_by: %{"kind" => "system"}}] =
             Attention.resolved_since(
               c.org,
               c.mission,
               DateTime.add(DateTime.utc_now(), -60),
               c.table
             )
  end

  test "a command group's pass is its spacecraft's live pass; next_contact the next booked uplink pass",
       c do
    group_id = queued_group!(c)
    record(c, :blocked, :attestation_signature_invalid)

    later = DateTime.add(DateTime.utc_now(), 7_200)
    reservation = commandable_pass!(c.org, c.mission, c.sc, later)
    scheduled_contact!(c, reservation, ["telemetry_downlink", "command_window"])
    downlink_only = commandable_pass!(c.org, c.mission, c.sc, DateTime.add(later, -3_600))
    scheduled_contact!(c, downlink_only, ["telemetry_downlink"])

    assert %{^group_id => %{contact: live, next_contact: next, targets: [_]}} =
             Groups.for_command_groups(c.org, c.mission, [group_id], table: c.table)

    assert %{scheduled_contact_id: "contact-live", readiness: %{state: :blocked}} = live
    assert next.scheduled_contact_id == reservation.scheduled_contact_id
    assert live.ground_station_ref == "earendil-kiruna"
    assert Map.has_key?(next, :ground_station_ref)
    assert next.starts_at == reservation.starts_at

    assert %{} == UplinkPasses.upcoming(c.org, c.mission, [], DateTime.utc_now())

    # An accepted change drops that pass's uplink leg: it can't command, so it isn't next.
    drop_uplink_leg!(reservation)

    assert %{^group_id => %{next_contact: nil}} =
             Groups.for_command_groups(c.org, c.mission, [group_id], table: c.table)

    assert %{} == UplinkPasses.upcoming(c.org, c.mission, [c.sc], DateTime.utc_now())
  end

  test "Recover re-qualifies a blocked pass, audited; refuses what re-qualifying can't fix", c do
    outsider = Map.put(c.scope, :organization_membership, nil)
    {:ok, ready} = FakeDriver.start_link(fn _key -> :ready end)

    {:ok, refusing} =
      FakeDriver.start_link(fn _key -> {:error, :attestation_signature_invalid} end)

    opts = [table: c.table, driver: ready]

    assert {:error, :not_found} =
             UplinkReadiness.recover(c.scope, c.mission, "contact-live", opts)

    record(c, :ready, nil)

    assert {:error, :not_blocked} =
             UplinkReadiness.recover(c.scope, c.mission, "contact-live", opts)

    record(c, :blocked, :protocol_state_restore_required)

    assert {:error, {:refused, :protocol_state_restore_required}} =
             UplinkReadiness.recover(c.scope, c.mission, "contact-live", opts)

    record(c, :blocked, :provider_cannot_attest_uplink_sessions)

    assert {:error, {:refused, :provider_cannot_attest_uplink_sessions}} =
             UplinkReadiness.recover(c.scope, c.mission, "contact-live", opts)

    record(c, :blocked, :cop1_no_clcw_report)

    assert {:error, {:refused, :cop1_no_clcw_report}} =
             UplinkReadiness.recover(c.scope, c.mission, "contact-live", opts)

    record(c, :blocked, :attestation_signature_invalid)

    assert {:error, _forbidden} =
             UplinkReadiness.recover(outsider, c.mission, "contact-live", opts)

    assert {:error, {:refused, :attestation_signature_invalid}} =
             UplinkReadiness.recover(
               c.scope,
               c.mission,
               "contact-live",
               Keyword.put(opts, :driver, refusing)
             )

    assert {:ok, %{state: :ready, ready_at: %DateTime{}}} =
             UplinkReadiness.recover(c.scope, c.mission, "contact-live", opts)

    audits =
      c.org
      |> ProviderAudit.list_entries(mission_id: c.mission)
      |> Enum.filter(&(&1.action == "uplink_session.recover"))

    assert Enum.sort(Enum.map(audits, & &1.outcome)) == ["recovered", "refused"]
  end

  test "#67: an unverified peer is dropped; the pass reads blocked (unverified peer) and raises uplink_blocked",
       c do
    registry = :"uplink_qualification_registry_#{System.unique_integer([:positive])}"
    start_supervised!({Registry, keys: :unique, name: registry})
    namespace = %ProcessNamespace{ProcessNamespace.default() | registry: registry}
    start_supervised!({FakeSession, {registry, c.key, self()}})
    booking = Map.merge(pass(c), %{client: AttestingClient, context: nil, call_opts: []})

    driver =
      start_supervised!(
        {UplinkQualification,
         process_namespace: namespace,
         readiness_table: c.table,
         tick_ms: nil,
         booking: fn _provider -> {:ok, booking} end}
      )

    group_id = queued_group!(c)

    assert %{} = UplinkQualification.qualify_now(driver)

    # The provider attested another peer than the one connected: drop it, keep accepting.
    assert_received {:dropped, "127.0.0.1:50123", :attestation_peer_mismatch}

    assert %{"contact-live" => %{state: :blocked, reason: :unverified_peer_connected}} =
             UplinkReadiness.for_contacts(c.org, c.mission, ["contact-live"], c.table)

    assert [
             %{
               source: "uplink_blocked",
               reason: "unverified_peer_connected",
               command_group_ids: [^group_id]
             }
           ] = Attention.items(c.org, c.mission, c.table)
  end

  test "#38: a qualified pass reads ready only when its uplink runtime reports its first CLCW",
       c do
    registry = :"uplink_qualification_registry_#{System.unique_integer([:positive])}"
    start_supervised!({Registry, keys: :unique, name: registry})
    namespace = %ProcessNamespace{ProcessNamespace.default() | registry: registry}
    booking = Map.merge(pass(c), %{client: AttestingClient, context: nil, call_opts: []})

    for {snapshot, expected} <- [
          {{:ok, %{state: %{cop1_awaiting_clcw: false}}}, {:ready, nil}},
          {{:ok, %{state: %{cop1_awaiting_clcw: true}}}, {:qualifying, :cop1_awaiting_clcw}},
          {{:error, :snapshot_failed}, {:qualifying, :uplink_state_unavailable}},
          {:exit, {:qualifying, :uplink_state_unavailable}}
        ] do
      session =
        start_supervised!(
          Supervisor.child_spec({ReadySession, {registry, c.key, snapshot}},
            id: make_ref(),
            restart: :temporary
          )
        )

      driver =
        start_supervised!(
          Supervisor.child_spec(
            {UplinkQualification,
             process_namespace: namespace,
             readiness_table: c.table,
             tick_ms: nil,
             booking: fn _provider -> {:ok, booking} end},
            id: make_ref()
          )
        )

      UplinkQualification.qualify_now(driver)
      {state, reason} = expected

      assert %{"contact-live" => %{state: ^state, reason: ^reason}} =
               UplinkReadiness.for_contacts(c.org, c.mission, ["contact-live"], c.table),
             "snapshot #{inspect(snapshot)}"

      if Process.alive?(session), do: GenServer.stop(session)
    end
  end

  # As Cadence's accepted terms read after the provider takes the leg out of "included".
  defp drop_uplink_leg!(reservation) do
    id = reservation.provider_reservation_id

    row =
      Cadence.Repo.get_by!(Cadence.Control.Contacts.Store.ProviderReservationRow,
        provider_reservation_id: id
      )

    request = Map.put(JsonDocument.unwrap_value(row.request_document), "uplink", %{})

    accepted =
      Map.put(JsonDocument.unwrap_value(row.cadence_accepted_snapshot_document), "uplink", %{
        "status" => "rejected"
      })

    row
    |> Ecto.Changeset.change(
      request_document: JsonDocument.wrap_value(request),
      cadence_accepted_snapshot_document: JsonDocument.wrap_value(accepted)
    )
    |> Cadence.Repo.update!()
  end

  defp scheduled_contact!(c, reservation, intents) do
    ScheduledContact.new(%{
      organization_id: c.org,
      mission_id: c.mission,
      scheduled_contact_id: reservation.scheduled_contact_id,
      source_endpoint_refs: [Cadence.SourceEndpoints.managed_source_endpoint_id(c.sc)],
      contact_intents: Enum.map(intents, &String.to_existing_atom/1),
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at,
      metadata: %{}
    })
    |> ScheduledContactRow.changeset()
    |> Repo.insert!()
  end
end
