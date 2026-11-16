defmodule Cadence.Reads.ScidMismatchEventsTest do
  @moduledoc "ux U81 §2 (#102): the Timeline row for a pass where most frames carried another SCID."
  use ExUnit.Case, async: true

  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.{EventSentences, ScidMismatchEvents}

  @ctx %{
    spacecraft: %{"sc-312" => {"EARENDIL-312", 1}, "sc-nameless" => {nil, 5}},
    users: %{},
    dashboards: %{},
    contacts: %{},
    stations: %{"FBK" => %{id: "ground_station_fbk", code: "FBK", name: "Fairbanks"}}
  }

  @tail "Cadence kept them as raw evidence and made no telemetry from them."

  defp payload(overrides) do
    Map.merge(
      %{
        "realized_contact_id" => "rc-1",
        "spacecraft_id" => "sc-312",
        "contact_started_at" => "2026-11-16T03:10:41Z",
        "ground_station_ref" => "FBK",
        "expected_scid" => 1,
        "frames" => 412,
        "frames_total" => 430,
        "scids" => [3],
        "scid_count" => 1
      },
      overrides
    )
  end

  defp entry(payload, spacecraft_id \\ "sc-312"),
    do: %Entry{
      mission_event_id: "mission_event:operational_event:contact_scid_mismatch:rc-1",
      kind: :contact_scid_mismatch,
      severity: :warning,
      spacecraft_id: spacecraft_id,
      realized_contact_id: "rc-1",
      subject_id: "rc-1",
      metadata: %{"payload" => payload}
    }

  test "title, caution severity, the contact as subject, and the secondary line" do
    e = entry(payload(%{}))

    assert %{
             text: "EARENDIL-312 · Most frames on the FBK 03:10Z pass carried another SCID.",
             severity: :caution,
             subject: %{kind: "contact", id: "rc-1"}
           } = EventSentences.describe(e, @ctx)

    assert EventSentences.detail(e, @ctx) ==
             "412 of 430 frames carried SCID 3, not EARENDIL-312's SCID 1. #{@tail}"
  end

  test "no spacecraft name: the title drops it and the detail says this pass's; never an id" do
    e = entry(payload(%{"spacecraft_id" => "sc-nameless"}), "sc-nameless")

    assert EventSentences.describe(e, @ctx).text ==
             "Most frames on the FBK 03:10Z pass carried another SCID."

    detail = EventSentences.detail(e, @ctx)
    assert detail =~ "not this pass's SCID 1"
    refute detail =~ "sc-nameless"
  end

  test "no station (or an unknown one): 'the 03:10Z pass'" do
    for ref <- [nil, "NOPE"] do
      assert EventSentences.describe(entry(payload(%{"ground_station_ref" => ref})), @ctx).text ==
               "EARENDIL-312 · Most frames on the 03:10Z pass carried another SCID."
    end
  end

  test "a payload projected in memory (atom keys) reads the same" do
    atoms = Map.new(payload(%{}), fn {k, v} -> {String.to_atom(k), v} end)
    assert EventSentences.describe(entry(atoms), @ctx).text =~ "FBK 03:10Z pass"
  end

  test "SCID words: one, two, three, more than three, and a list that may be short" do
    words = &ScidMismatchEvents.scid_words(%{"scids" => &1, "scid_count" => &2})

    assert words.([3], 1) == "SCID 3"
    assert words.([3, 7], 2) == "SCIDs 3 and 7"
    assert words.([3, 7, 9], 3) == "SCIDs 3, 7 and 9"
    assert words.([1, 2, 3, 4], 4) == "4 different SCIDs"
    assert words.(Enum.to_list(1..8), 12) == "at least 12 different SCIDs"
    assert words.(Enum.to_list(1..8), 8) == "at least 8 different SCIDs"
    assert words.([3], 2) == "at least 2 different SCIDs"
  end

  test "other kinds have no detail" do
    assert EventSentences.detail(%Entry{kind: :realized_contact_interval}, @ctx) == nil
  end
end
