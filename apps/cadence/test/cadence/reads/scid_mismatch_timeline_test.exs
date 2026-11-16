defmodule Cadence.Reads.ScidMismatchTimelineTest do
  @moduledoc """
  ux U81 §2 (#102), end to end: domain's stored contact_scid_mismatch event reads back on the
  Timeline as a caution contact row with ux's title and secondary line, linked to the contact.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{RealizedContact, ScidMismatch}
  alias Cadence.Reads.EventLog
  alias Cadence.{Spacecraft, SpacecraftStore}

  @org "org-scid-timeline"
  @mission "mission-scid-timeline"
  @started ~U[2026-11-16 03:10:41.000000Z]

  setup do
    persist_mission_scope(@org, @mission)

    {:ok, craft} =
      SpacecraftStore.persist_spacecraft(
        @org,
        Spacecraft.new(%{mission_id: @mission, display_name: "EARENDIL-312", scid: 1})
      )

    contact =
      RealizedContact.new(%{
        realized_contact_id: "rc-scid",
        organization_id: @org,
        mission_id: @mission,
        source_endpoint_refs: [],
        clock_mode: :live,
        initial_time: @started,
        realized_at: @started,
        lifecycle_state: :completed,
        metadata: %{"ground_station_ref" => "FBK"}
      })

    entries = [
      %{
        "path_id" => "path-a",
        "spacecraft_id" => craft.spacecraft_id,
        "expected_scid" => 1,
        "frames" => 412,
        "frames_total" => 430,
        "scids" => [3],
        "scid_count" => 1
      }
    ]

    {:ok, %{}} = ScidMismatch.record_event(contact, entries, DateTime.add(@started, 1_200))
    %{craft: craft}
  end

  test "a caution contact row: ux's title and detail, the contact as subject", c do
    {:ok, %{events: [event]}} =
      EventLog.page(@org, @mission, %{
        from: DateTime.add(@started, -60),
        to: DateTime.add(@started, 3_600),
        limit: 50,
        cursor: nil,
        kinds: nil,
        plane: nil,
        spacecraft_id: nil
      })

    craft_id = c.craft.spacecraft_id

    assert %{
             kind: "contact",
             raw_kind: "contact_scid_mismatch",
             severity: :caution,
             # No station is stored in this mission, so the title has no station clause.
             text: "EARENDIL-312 · Most frames on the 03:10Z pass carried another SCID.",
             detail:
               "412 of 430 frames carried SCID 3, not EARENDIL-312's SCID 1. Cadence kept them " <>
                 "as raw evidence and made no telemetry from them.",
             spacecraft: %{id: ^craft_id},
             refs: %{subject: %{kind: "contact", id: "rc-scid"}, contact_id: "rc-scid"}
           } = event
  end

  test "an archived craft is still named on its past events", c do
    {:ok, _} =
      SpacecraftStore.archive_spacecraft(@org, @mission, c.craft.spacecraft_id, %{kind: :system})

    {:ok, %{events: [event]}} =
      EventLog.page(@org, @mission, %{
        from: DateTime.add(@started, -60),
        to: DateTime.add(@started, 3_600),
        limit: 50,
        cursor: nil,
        kinds: nil,
        plane: nil,
        spacecraft_id: nil
      })

    assert %{spacecraft: %{name: "EARENDIL-312", scid: 1}} = event
    assert event.text =~ "EARENDIL-312 · "
  end
end
