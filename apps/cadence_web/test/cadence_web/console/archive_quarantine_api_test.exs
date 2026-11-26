defmodule CadenceWeb.Console.ArchiveQuarantineAPITest do
  @moduledoc """
  DECISIONS #88 / ux U49 over HTTP: the archive_quarantine item on Now and on its pass row (P2, no
  due time, the pass fields), no acknowledge, discard through resolve with a reason, and the
  synchronous retry `{item, indexed, still_failing}`.
  """
  use CadenceWeb.ConnCase, async: false
  @moduletag :tmp_dir

  import Ecto.Query

  alias Cadence.Contacts
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Protocol.{RecordArchive, TransferFrameRecord}
  alias Cadence.Protocol.RecordArchive.FileSystem
  alias Cadence.Protocol.RecordArchive.FileSystem.IdentityRow
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup %{tmp_dir: base_path} do
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
    end)

    booked = ProviderChangeFixtures.setup_contact()
    org = booked.organization_id
    mission = booked.mission_id
    reservation = booked.reservation

    {:ok, _} =
      Contacts.persist_realized_contact(
        org,
        RealizedContact.new(%{
          realized_contact_id: "booked-run",
          organization_id: org,
          mission_id: mission,
          scheduled_contact_id: reservation.scheduled_contact_id,
          source_endpoint_refs: [],
          paths: [],
          realized_at: ~U[2026-11-14 03:10:00.000000Z]
        })
      )

    # One frame archived, then a different frame at its id: a real identity conflict.
    run = evidence(mission, "run")
    archived = frame(run, mission)
    :ok = RecordArchive.persist_records(policy, run, [archived], [])
    :ok = RecordArchive.flush(policy, mission)
    later = evidence(mission, "later")
    :ok = RecordArchive.persist_records(policy, later, [%{frame(later, mission) | scid: 99}], [])
    :ok = RecordArchive.flush(policy, mission)

    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, booked.organization, role: :organization_admin)

    %{
      conn: TestFixtures.member_conn(user),
      base: "/api/v1/missions/#{mission}",
      reservation: reservation,
      archived: archived
    }
  end

  @id "booked-run:identity_conflict"

  test "Now and the pass row carry it as P2 with no due time, named by its pass", c do
    items =
      c.conn |> get(c.base <> "/action-queue") |> json_response(200) |> get_in(["data", "items"])

    assert %{"priority" => 2, "due_at" => nil, "attention" => attention} =
             Enum.find(items, &(&1["id"] == "attention:archive_quarantine:" <> @id))

    reservation_id = c.reservation.provider_reservation_id

    assert %{
             "source" => "archive_quarantine",
             "conflict" => "quarantined",
             "state" => "open",
             "reservation_id" => ^reservation_id,
             "realized_contact_id" => "booked-run",
             "error_code" => "identity_conflict",
             "counts" => %{"frames" => 1, "packets" => 0},
             "stored_without_archive" => %{"frames" => 1, "packets" => 0},
             "actions" => ["retry", "discard"],
             "last_retry" => nil,
             "resolution" => nil,
             "station" => %{},
             "starts_at" => starts_at
           } = attention

    assert starts_at

    pass =
      c.conn
      |> get(c.base <> "/passes/#{reservation_id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.any?(pass["attentions"], &(&1["source"] == "archive_quarantine"))
  end

  test "no acknowledge; discard needs a reason", c do
    path = c.base <> "/attention/archive_quarantine/#{@id}"

    assert %{"error" => %{"code" => "attention_item_not_open"}} =
             c.conn |> post(path <> "/acknowledge", %{}) |> json_response(409)

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"action_text" => _}}} =
             c.conn |> post(path <> "/resolve", %{"action_text" => "  "}) |> json_response(422)

    assert %{"data" => %{"state" => "resolved", "resolution" => resolution}} =
             c.conn
             |> post(path <> "/resolve", %{"action_text" => "Bad replay"})
             |> json_response(200)

    assert %{"action" => "discarded", "note" => "Bad replay", "provider_reference" => nil} =
             resolution
  end

  test "retry answers with the item and the counts, then resolves once the cause is fixed", c do
    path = c.base <> "/attention/archive_quarantine/#{@id}/retry"

    assert %{
             "data" => %{
               "indexed" => 0,
               "still_failing" => 1,
               "item" => %{"state" => "open", "last_retry" => %{"by" => %{"name" => "Mira K."}}}
             }
           } = c.conn |> post(path, %{}) |> json_response(200)

    Repo.delete_all(from(r in IdentityRow, where: r.record_id == ^c.archived.frame_record_id))

    assert %{
             "data" => %{
               "indexed" => 1,
               "still_failing" => 0,
               "item" => %{"state" => "resolved", "resolution" => %{"action" => "retried"}}
             }
           } = c.conn |> post(path, %{}) |> json_response(200)

    assert %{"error" => %{"code" => "attention_item_not_found"}} =
             c.conn |> post(path, %{}) |> json_response(404)
  end

  defp evidence(mission, name) do
    RawEvidence.new(%{
      evidence_id: "evidence-api-#{name}",
      mission_id: mission,
      protocol_family: :tm,
      direction: :downlink,
      raw: :crypto.strong_rand_bytes(8),
      receipt_time: ~U[2026-11-14 03:14:00Z],
      metadata: %{"realized_contact_id" => "booked-run"}
    })
  end

  defp frame(evidence, mission) do
    TransferFrameRecord.new(%{
      frame_record_id: "frame-api-1",
      evidence_id: evidence.evidence_id,
      mission_id: mission,
      protocol_family: :tm,
      direction: :downlink,
      scid: 8,
      vcid: 0,
      frame_seq: 1,
      raw_frame_offset_bytes: 1115,
      raw_frame_length_bytes: 1115,
      payload_length_bytes: 1109,
      first_header_pointer: 0,
      quality: :good,
      receipt_time: evidence.receipt_time
    })
  end
end
