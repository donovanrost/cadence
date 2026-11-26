defmodule Cadence.Contacts.ArchiveQuarantineAttentionTest do
  @moduledoc "DECISIONS #88 / ux U49: the archive_quarantine Now item, retry and discard."
  use Cadence.ProcessDataCase, async: false

  import Ecto.Query

  alias Cadence.CommandGroupFixtures
  alias Cadence.Contacts
  alias Cadence.Contacts.ArchiveQuarantineAttention, as: Attention
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{RecordArchive, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Protocol.RecordArchive.FileSystem.IdentityRow
  alias Cadence.Protocol.RecordArchive.Quarantine
  alias Cadence.ProviderChangeFixtures

  setup do
    base_path =
      Path.join(
        System.tmp_dir!(),
        "cadence_quarantine_attention_#{System.unique_integer([:positive])}"
      )

    config = [
      module: FileSystem,
      base_path: base_path,
      flush_interval_ms: 60_000,
      flush_count: 1_000
    ]

    policy = RecordArchive.policy(config)
    start_supervised!(RecordArchive.child_spec(policy))

    previous = Application.get_env(:cadence, :protocol_record_archive)
    Application.put_env(:cadence, :protocol_record_archive, config)

    on_exit(fn ->
      Application.put_env(:cadence, :protocol_record_archive, previous)
      File.rm_rf!(base_path)
    end)

    org = "org-quarantine-attention-#{System.unique_integer([:positive])}"
    mission = "mission-quarantine-attention-#{System.unique_integer([:positive])}"
    persist_mission_scope(org, mission)
    scope = CommandGroupFixtures.operator!(%{org: org}, "Mira K.")

    # One frame archived, then a different frame at its id quarantined (a real conflict).
    run = evidence(mission, "run")
    archived = frame(run, mission, 1)
    :ok = RecordArchive.persist_records(policy, run, [archived], [])
    :ok = RecordArchive.flush(policy, mission)

    later = evidence(mission, "later")

    :ok =
      RecordArchive.persist_records(policy, later, [%{frame(later, mission, 1) | scid: 99}], [])

    :ok = RecordArchive.flush(policy, mission)

    %{org: org, mission: mission, scope: scope, archived: archived}
  end

  test "a quarantined pass is one item: counts, span and actions", c do
    assert [item] = Attention.items(c.org, c.mission)

    assert %{
             id: "contact-qa:identity_conflict",
             source: "archive_quarantine",
             conflict: "quarantined",
             state: "open",
             error_code: "identity_conflict",
             counts: %{entries: 1, frames: 1, packets: 0},
             stored_without_archive: %{frames: 1, packets: 0},
             first_received_at: ~U[2026-11-14 03:14:00.000000Z],
             actions: ["retry", "discard"],
             last_retry: nil,
             realized_contact_id: "contact-qa"
           } = item

    assert %{open: 1} = Attention.counts(c.org, c.mission)
    assert {:error, :attention_item_not_open} = Attention.acknowledge(c.scope, c.mission, item.id)
  end

  test "a retry that still fails keeps the item with last_retry; after the fix it resolves", c do
    [%{id: id}] = Attention.items(c.org, c.mission)

    assert {:ok, %{indexed: 0, still_failing: 1, item: %{state: "open", last_retry: retry}}} =
             Attention.retry(c.scope, c.mission, id)

    assert %{by: %{"kind" => "user", "name" => "Mira K."}, indexed: 0, at: %DateTime{}} = retry

    # The cause is fixed (the conflicting archived row is gone): the retry archives it.
    Repo.delete_all(from(r in IdentityRow, where: r.record_id == ^c.archived.frame_record_id))

    assert {:ok, %{indexed: 1, still_failing: 0, item: %{state: "resolved", resolution: res}}} =
             Attention.retry(c.scope, c.mission, id)

    assert %{action: "retried", actor: %{"kind" => "user"}, note: nil} = res
    assert Attention.items(c.org, c.mission) == []

    assert [
             %{
               id: ^id,
               action: "retried",
               resolved_by: %{"kind" => "user"},
               source: "archive_quarantine"
             }
           ] =
             Attention.resolved_since(c.org, c.mission, DateTime.add(DateTime.utc_now(), -60))
  end

  test "discard needs a reason, then resolves the item", c do
    [%{id: id}] = Attention.items(c.org, c.mission)

    assert {:error, :reason_required} = Attention.resolve(c.scope, c.mission, id, "  ")

    assert {:ok, %{state: "resolved", resolution: %{action: "discarded", note: "Bad replay"}}} =
             Attention.resolve(c.scope, c.mission, id, " Bad replay ")

    assert Quarantine.rows(c.mission) == []
    assert {:error, :attention_item_not_found} = Attention.retry(c.scope, c.mission, id)
  end

  test "the item names its pass: the booking's, or a hand start's own station and start" do
    booked = ProviderChangeFixtures.setup_contact()
    reservation = booked.reservation
    org = booked.organization_id
    mission = booked.mission_id

    contact = fn id, scheduled_id, metadata ->
      {:ok, _} =
        Contacts.persist_realized_contact(
          org,
          RealizedContact.new(%{
            realized_contact_id: id,
            organization_id: org,
            mission_id: mission,
            scheduled_contact_id: scheduled_id,
            source_endpoint_refs: [],
            paths: [],
            metadata: metadata,
            realized_at: ~U[2026-11-14 03:10:00.000000Z]
          })
        )
    end

    contact.("booked-run", reservation.scheduled_contact_id, %{})
    contact.("hand-run", nil, %{"ground_station_ref" => "SVB"})

    for id <- ["booked-run", "hand-run"] do
      entry = %{
        "record_kind" => "transfer_frame_record",
        "record_id" => "frame-" <> id,
        "mission_id" => mission,
        "metadata" => %{"realized_contact_id" => id}
      }

      :ok =
        Quarantine.put(
          mission,
          org,
          [%{entry: entry, error_code: "identity_conflict", error: nil}],
          DateTime.utc_now()
        )
    end

    items = Map.new(Attention.items(org, mission), &{&1.realized_contact_id, &1})
    id = reservation.provider_reservation_id
    starts_at = reservation.starts_at

    assert %{provider_reservation_id: ^id, starts_at: ^starts_at, contact_id: contact_id} =
             items["booked-run"]

    assert contact_id == reservation.scheduled_contact_id

    assert %{
             provider_reservation_id: nil,
             ground_station_ref: "SVB",
             ends_at: nil,
             starts_at: %DateTime{}
           } =
             items["hand-run"]
  end

  defp evidence(mission, name) do
    RawEvidence.new(%{
      evidence_id: "evidence-qa-#{name}",
      mission_id: mission,
      protocol_family: :tm,
      direction: :downlink,
      raw: :crypto.strong_rand_bytes(8),
      receipt_time: ~U[2026-11-14 03:14:00Z],
      metadata: %{"realized_contact_id" => "contact-qa"}
    })
  end

  defp frame(evidence, mission, seq) do
    TransferFrameRecord.new(%{
      frame_record_id: "frame-qa-#{seq}",
      evidence_id: evidence.evidence_id,
      mission_id: mission,
      protocol_family: :tm,
      direction: :downlink,
      scid: 8,
      vcid: 0,
      frame_seq: seq,
      raw_frame_offset_bytes: seq * 1115,
      raw_frame_length_bytes: 1115,
      payload_length_bytes: 1109,
      first_header_pointer: 0,
      quality: :good,
      receipt_time: evidence.receipt_time
    })
  end
end
