defmodule CadenceWeb.Console.ReplayConflictAPITest do
  @moduledoc """
  #99 follow-up / ux U84 'Stuck processing' over HTTP: the replay_conflict item on Now (the agreed
  shape: buffer, the craft named, the pass label), acknowledge with an optional note (500 at most,
  `invalid_note` past it), and nothing to resolve.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Contacts
  alias Cadence.Contacts.RealizedContact
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Runtime.ReplayConflicts
  alias Cadence.Runtime.ReplayConflicts.Recorder
  alias CadenceWeb.TestFixtures

  setup do
    booked = ProviderChangeFixtures.setup_contact()
    org = booked.organization_id
    mission = booked.mission_id
    reservation = booked.reservation

    {:ok, _} =
      Contacts.persist_realized_contact(
        org,
        RealizedContact.new(%{
          realized_contact_id: "stuck-run",
          organization_id: org,
          mission_id: mission,
          scheduled_contact_id: reservation.scheduled_contact_id,
          source_endpoint_refs: [],
          paths: [],
          realized_at: ~U[2026-11-17 03:10:00.000000Z]
        })
      )

    unit = Recorder.stream_unit(:storage, mission, "stuck-run", "path-1", "binding-1")

    :open =
      Recorder.track({:error, {:replay_id_conflict, :alarm_event, "aev_1"}}, unit, :clear)

    [record] = ReplayConflicts.open(mission)

    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, booked.organization, role: :organization_admin)

    %{
      conn: TestFixtures.member_conn(user),
      base: "/api/console/v1/missions/#{mission}",
      org: org,
      mission: mission,
      reservation: reservation,
      id: record.id
    }
  end

  test "Now carries it in the agreed shape", c do
    items =
      c.conn |> get(c.base <> "/action-queue") |> json_response(200) |> get_in(["data", "items"])

    assert %{"priority" => 2, "attention" => attention} =
             Enum.find(items, &(&1["id"] == "attention:replay_conflict:" <> c.id))

    spacecraft_id = c.reservation.spacecraft_id

    assert %{
             "source" => "replay_conflict",
             "conflict" => "replay_id_conflict",
             "state" => "open",
             "path" => "storage",
             "effect_kind" => "alarm_effect",
             "effect_id" => "aev_1",
             "effect_count" => 1,
             "occurrences" => 1,
             "partition_id" => nil,
             "partition_stopped" => false,
             "realized_contact_id" => "stuck-run",
             "path_id" => "path-1",
             "stream_key" => "stuck-run:path-1:binding-1",
             "spacecraft_ids" => [^spacecraft_id],
             "spacecraft_count" => 1,
             "affected_spacecraft" => [%{"id" => ^spacecraft_id, "name" => _, "scid" => _}],
             "contact" => %{"id" => _, "station_code" => _, "starts_at" => starts_at},
             "buffer" => nil,
             "dropping" => false,
             "dropping_since" => nil,
             "reraised" => false,
             "acknowledged_at" => nil,
             "acknowledged_note" => nil
           } = attention

    assert starts_at
    refute Map.has_key?(attention, "journal")
  end

  test "a hand-started contact (no booking) carries contact null, not a half pass", c do
    {:ok, _} =
      Contacts.persist_realized_contact(
        c.org,
        RealizedContact.new(%{
          realized_contact_id: "hand-run",
          organization_id: c.org,
          mission_id: c.mission,
          scheduled_contact_id: nil,
          source_endpoint_refs: [],
          paths: [],
          realized_at: ~U[2026-11-17 04:00:00.000000Z]
        })
      )

    unit = Recorder.stream_unit(:processing, c.mission, "hand-run", "path-1", "binding-1")

    :open =
      Recorder.track(
        {:error, {:replay_id_conflict, :managed_action_request, "mar_h"}},
        unit,
        :clear
      )

    items =
      c.conn |> get(c.base <> "/action-queue") |> json_response(200) |> get_in(["data", "items"])

    assert %{"attention" => attention} =
             Enum.find(items, &(get_in(&1, ["attention", "realized_contact_id"]) == "hand-run"))

    assert %{
             "path" => "processing",
             "contact" => nil,
             "affected_spacecraft" => [],
             "spacecraft_count" => 0
           } = attention
  end

  test "acknowledge takes an optional note; a long one is refused; nothing to resolve", c do
    path = c.base <> "/attention/replay_conflict/#{c.id}"

    assert %{"error" => %{"code" => "invalid_note"}} =
             c.conn
             |> post(path <> "/acknowledge", %{"note" => String.duplicate("x", 501)})
             |> json_response(422)

    assert %{
             "data" => %{
               "state" => "acknowledged",
               "acknowledged_note" => "told domain at 03:18Z",
               "acknowledged_by" => %{"kind" => "user", "name" => "Mira K."}
             }
           } =
             c.conn
             |> post(path <> "/acknowledge", %{"note" => "told domain at 03:18Z"})
             |> json_response(200)

    assert %{"data" => %{"acknowledged_note" => nil}} =
             c.conn |> post(path <> "/acknowledge", %{}) |> json_response(200)

    assert %{"error" => %{"code" => "attention_item_not_found"}} =
             c.conn |> post(path <> "/resolve", %{"action_text" => "fixed"}) |> json_response(404)
  end
end
