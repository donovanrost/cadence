defmodule CadenceWeb.Console.ScidMismatchAPITest do
  @moduledoc """
  ux U81 §2 / DECISIONS #102 over HTTP: a settled pass where most frames carried another SCID.
  Now's contact_scid_mismatch row (P2, the pass's craft named, the refused frames summed), Mark as
  seen answering the attention object resolved, and the pass detail's per-path scid_mismatch.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Contacts
  alias Cadence.Contacts.RealizedContact
  alias Cadence.{ProviderChangeFixtures, Spacecraft, SpacecraftStore}
  alias CadenceWeb.TestFixtures

  setup do
    booked = ProviderChangeFixtures.setup_contact()
    org = booked.organization_id
    mission = booked.mission_id

    {:ok, craft} =
      SpacecraftStore.persist_spacecraft(
        org,
        Spacecraft.new(%{mission_id: mission, display_name: "EARENDIL-312", scid: 1})
      )

    entry = fn path, frames, total, scids ->
      %{
        "path_id" => path,
        "provider_binding_id" => "binding-" <> path,
        "ground_station_ref" => "FBK",
        "spacecraft_id" => craft.spacecraft_id,
        "expected_scid" => 1,
        "frames" => frames,
        "frames_total" => total,
        "scids" => scids,
        "scid_count" => length(scids)
      }
    end

    settled_at = DateTime.add(DateTime.utc_now(), -60)

    {:ok, _contact} =
      Contacts.persist_realized_contact(
        org,
        RealizedContact.new(%{
          realized_contact_id: "scid-run",
          organization_id: org,
          mission_id: mission,
          scheduled_contact_id: booked.reservation.scheduled_contact_id,
          source_endpoint_refs: [],
          paths: [],
          clock_mode: :live,
          lifecycle_state: :completed,
          realized_at: DateTime.add(settled_at, -900) |> DateTime.truncate(:microsecond),
          metadata: %{
            "settlement" => %{
              "state" => "settled",
              "settled_at" => DateTime.to_iso8601(settled_at),
              # One path refused most of its frames; a clean path is kept (frames 0) for 'most'.
              "scid_mismatch" => [
                entry.("path-a", 412, 430, [3, 7]),
                entry.("path-b", 0, 20, [])
              ]
            }
          }
        })
      )

    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, booked.organization, role: :organization_admin)

    %{
      conn: TestFixtures.member_conn(user),
      base: "/api/console/v1/missions/#{mission}",
      reservation: booked.reservation,
      craft: craft
    }
  end

  test "Now: one P2 caution row, the craft named, frames summed over the paths", c do
    items =
      c.conn |> get(c.base <> "/action-queue") |> json_response(200) |> get_in(["data", "items"])

    assert %{"priority" => 2, "state" => "caution", "attention" => attention} =
             Enum.find(items, &(&1["id"] == "attention:contact_scid_mismatch:scid-run"))

    craft_id = c.craft.spacecraft_id
    scheduled = c.reservation.scheduled_contact_id
    reservation = c.reservation.provider_reservation_id

    assert %{
             "id" => "scid-run",
             "source" => "contact_scid_mismatch",
             "conflict" => nil,
             "state" => "open",
             "acknowledged_by" => nil,
             "contact_id" => ^scheduled,
             "realized_contact_id" => "scid-run",
             "reservation_id" => ^reservation,
             "starts_at" => starts_at,
             "raised_at" => raised_at,
             "resolution" => nil,
             "spacecraft" => %{"id" => ^craft_id, "name" => "EARENDIL-312", "scid" => 1},
             "scid_mismatch" => %{
               "expected_scid" => 1,
               "frames" => 412,
               "frames_total" => 450,
               "scids" => [3, 7],
               "scid_count" => 2
             }
           } = attention

    assert starts_at && raised_at
  end

  test "Mark as seen answers the attention object, resolved by the person, named", c do
    path = c.base <> "/attention/contact_scid_mismatch/scid-run/acknowledge"

    assert %{
             "data" => %{
               "state" => "resolved",
               "realized_contact_id" => "scid-run",
               "resolution" => %{
                 "action" => "seen",
                 "actor" => %{"kind" => "user", "name" => "Mira K."},
                 "at" => at
               }
             }
           } = c.conn |> post(path, %{}) |> json_response(200)

    assert at

    queue = c.conn |> get(c.base <> "/action-queue") |> json_response(200) |> Map.fetch!("data")
    refute Enum.any?(queue["items"], &(&1["id"] == "attention:contact_scid_mismatch:scid-run"))

    assert %{"error" => %{"code" => "attention_item_not_found"}} =
             c.conn |> post(path, %{}) |> json_response(404)
  end

  test "the pass detail lists the refusing path only, the clean one left out", c do
    pass =
      c.conn
      |> get(c.base <> "/passes/#{c.reservation.provider_reservation_id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{
             "expected_scid" => 1,
             "paths" => [
               %{
                 "frames" => 412,
                 "scids" => [3, 7],
                 "scid_count" => 2,
                 "path_id" => "path-a",
                 "provider_binding_id" => "binding-path-a",
                 "station" => %{"ref" => "FBK"}
               }
             ]
           } = pass["scid_mismatch"]
  end
end
