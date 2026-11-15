defmodule Cadence.Reads.EventSentencesTest do
  use ExUnit.Case, async: true

  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.EventSentences

  @ctx %{
    spacecraft: %{"sc-4" => {"EARENDIL-004", 4}},
    users: %{"user-mira" => "Mira K."},
    dashboards: %{"dash-comms" => "Comms payload"},
    contacts: %{
      "sc-contact-1" => %{
        spacecraft_id: "sc-4",
        station: %{name: "Hawaii (Demo)", code: "HAW"},
        starts_at: ~U[2026-11-10 07:32:53Z],
        ends_at: ~U[2026-11-10 07:40:53Z]
      }
    }
  }

  defp entry(kind, attrs) do
    struct(Entry, Map.merge(%{mission_event_id: "e1", kind: kind, metadata: %{}}, attrs))
  end

  defp source_doc(event_type, reason, through) do
    %{
      "payload" => %{
        "value" => %{
          "reason" => reason,
          "data_realm" => "flight",
          "logical_source" => "telemetry",
          "event_type" => event_type
        }
      },
      "current" => %{"value" => %{"complete_through" => through}}
    }
  end

  test "watermarks name the source and time; a retreat is caution only with a reason" do
    advanced =
      entry(:source_watermark_advanced, %{
        subject_id: "questdb",
        metadata: source_doc("advanced", "telemetry_storage_write", "2026-11-09T10:23:54.246231Z")
      })

    assert %{
             text: "Flight telemetry source caught up to 10:23:54Z",
             subject: %{kind: "data_source", id: "questdb"}
           } =
             EventSentences.describe(advanced, @ctx)

    plain_retreat =
      entry(:source_watermark_retreated, %{
        metadata: source_doc("retreated", "telemetry_storage_write", "2026-11-09T10:23:52Z")
      })

    assert %{text: "Flight telemetry source went back to 10:23:52Z", severity: :info} =
             EventSentences.describe(plain_retreat, @ctx)

    replay =
      entry(:source_watermark_retreated, %{
        metadata:
          "retreated"
          |> source_doc("telemetry_storage_write", "2026-11-09T10:23:52Z")
          |> Map.put("replay_run_id", "replay-1")
      })

    assert %{
             text: "Flight telemetry source went back to 10:23:52Z (data replay)",
             severity: :caution
           } =
             EventSentences.describe(replay, @ctx)
  end

  test "ux U60: settled per contact, caught up after falling behind, a named retreat" do
    settled =
      entry(:source_watermark_settled, %{
        occurred_at: ~U[2026-11-15 03:21:00Z],
        subject_id: "realized-1",
        spacecraft_id: "sc-4",
        realized_contact_id: "realized-1",
        scheduled_contact_id: "scheduled-1",
        metadata: %{
          "current" => %{"value" => %{"complete_through" => "2026-11-15T03:19:40.120Z"}},
          "payload" => %{
            "value" => %{
              "ground_station_ref" => "SVB",
              "starts_at" => "2026-11-15T03:10:02Z",
              "ends_at" => "2026-11-15T03:19:57Z"
            }
          }
        }
      })

    assert %{
             text:
               "EARENDIL-004 · SVB 03:10Z pass: telemetry stored through 03:19:40Z (LOS 03:19:57Z)",
             subject: %{kind: "contact", id: "realized-1"},
             severity: nil
           } = EventSentences.describe(settled, @ctx)

    caught_up =
      entry(:source_watermark_caught_up, %{
        subject_id: "questdb",
        spacecraft_id: "sc-4",
        metadata: %{
          "current" => %{"value" => %{"complete_through" => "2026-11-15T03:21:58Z"}},
          "payload" => %{
            "value" => %{"behind_max_seconds" => 120, "caught_up_at" => "2026-11-15T03:22:04Z"}
          }
        }
      })

    assert %{
             text: "Telemetry from EARENDIL-004 caught up at 03:22Z after falling 2 min behind",
             subject: %{kind: "data_source", id: "questdb"}
           } = EventSentences.describe(caught_up, @ctx)

    replay =
      entry(:source_watermark_retreated, %{
        spacecraft_id: "sc-4",
        metadata:
          "retreated"
          |> source_doc("telemetry_storage_write", "2026-11-15T03:12:30Z")
          |> Map.put("replay_run_id", "replay-1")
      })

    assert %{
             text: "EARENDIL-004's stored telemetry moved back to 03:12Z for a replay",
             severity: :caution
           } = EventSentences.describe(replay, @ctx)

    # Fields missing: the sentence still reads, never crashes.
    assert %{text: "a spacecraft · SVB pass: telemetry stored through an unknown time"} =
             EventSentences.describe(
               entry(:source_watermark_settled, %{
                 metadata: %{"payload" => %{"value" => %{"ground_station_ref" => "SVB"}}}
               }),
               @ctx
             )
  end

  test "contacts, dashboards and catalog revisions read as sentences with their subject and actor" do
    contact =
      entry(:realized_contact_interval, %{
        spacecraft_id: "sc-4",
        realized_contact_id: "rc-1",
        metadata: %{
          "current" => %{
            "value" => %{
              "status" => "completed",
              "starts_at" => "2026-11-09T10:22:54Z",
              "ends_at" => "2026-11-09T10:23:52Z"
            }
          }
        }
      })

    assert %{
             text: "Contact with EARENDIL-004 ended (not verified), 10:22:54–10:23:52Z",
             subject: %{kind: "contact", id: "rc-1"}
           } =
             EventSentences.describe(contact, @ctx)

    dashboard =
      entry(:dashboard_published, %{
        subject_id: "dash-comms",
        actor: %{"value" => %{"kind" => "user", "id" => "user-mira"}},
        metadata: %{"payload" => %{"value" => %{"dashboard_version" => 1}}}
      })

    assert %{text: "Dashboard Comms payload v1 published by Mira K."} =
             EventSentences.describe(dashboard, @ctx)

    catalog =
      entry(:catalog_revision_registered, %{
        subject_id: "rev-2",
        actor: %{"value" => %{"kind" => "system"}},
        metadata: %{
          "current" => %{
            "value" => %{"revision_number" => 2, "revision_label" => "QA-E2E re-import"}
          }
        }
      })

    assert %{
             text: "Catalog rev 2 (QA-E2E re-import) registered",
             subject: %{kind: "catalog_revision"}
           } =
             EventSentences.describe(catalog, @ctx)
  end

  test "a cancelled contact names its spacecraft, station and window; activations drop internal keys" do
    canceled =
      entry(:scheduled_contact_canceled, %{
        scheduled_contact_id: "sc-contact-1",
        spacecraft_id: "sc-4",
        summary: "provider_canceled"
      })

    # U55/U56: Cadence canceled it because the reservation won't fly.
    assert %{text: "EARENDIL-004 · HAW 07:32Z pass canceled by Cadence: the provider canceled it"} =
             EventSentences.describe(canceled, @ctx)

    by_operator =
      entry(:scheduled_contact_canceled, %{
        scheduled_contact_id: "sc-contact-1",
        spacecraft_id: "sc-4",
        summary: "Antenna maintenance",
        actor: %{"kind" => "user", "id" => "user-mira"},
        metadata: %{"cause" => "operator"}
      })

    assert %{text: "EARENDIL-004 · HAW 07:32Z contact canceled by Mira K.: “Antenna maintenance”"} =
             EventSentences.describe(by_operator, @ctx)

    rejected = %{
      by_operator
      | actor: %{"kind" => "system"},
        metadata: %{"cause" => "provider_rejected"}
    }

    assert %{
             text:
               "EARENDIL-004 · HAW 07:32Z pass canceled by Cadence: the provider rejected its booking"
           } =
             EventSentences.describe(rejected, @ctx)

    ended = %{by_operator | kind: :realized_contact_ended_early, summary: "Wrong target"}

    assert %{text: "EARENDIL-004 · HAW 07:32Z contact ended early by Mira K.: “Wrong target”"} =
             EventSentences.describe(ended, @ctx)

    activated =
      entry(:binding_set_activated, %{
        summary: "Activated mission_applications:mission-earendil-demo v1"
      })

    assert %{text: "Mission applications configuration v1 activated"} =
             EventSentences.describe(activated, @ctx)
  end

  # Window truth (director 11-14; ux U56): a provider move, in ux's four cases.
  test "a moved pass reads later/earlier with the new AOS label and links the pass" do
    moved = fn before, after_window, extra ->
      entry(:contact_window_moved, %{
        spacecraft_id: "sc-4",
        subject_id: "sc-contact-1",
        occurred_at: ~U[2026-11-14 12:58:00Z],
        metadata: %{
          "payload" => %{
            "value" =>
              Map.merge(
                %{
                  "provider_reservation_id" => "res-4",
                  "ground_station_ref" => "PUQ",
                  "provider_name" => "Northlight",
                  "before" => before,
                  "after" => after_window
                },
                extra
              )
          }
        }
      })
    end

    w = &%{"starts_at" => "2026-11-14T#{&1}Z", "ends_at" => "2026-11-14T#{&2}Z"}
    text = &EventSentences.describe(&1, @ctx).text

    both = moved.(w.("13:04:00", "13:12:00"), w.("13:04:30", "13:12:30"), %{})

    assert %{
             text:
               "EARENDIL-004 · PUQ 13:04Z pass moved 30 s later by Northlight: 13:04:30–13:12:30Z",
             subject: %{kind: "pass", id: "res-4"}
           } = EventSentences.describe(both, @ctx)

    assert text.(moved.(w.("13:04:30", "13:12:30"), w.("13:04:30", "13:13:30"), %{})) ==
             "EARENDIL-004 · PUQ 13:04Z pass LOS moved 1 min later by Northlight: 13:04:30–13:13:30Z"

    assert text.(moved.(w.("13:06:00", "13:12:00"), w.("13:04:30", "13:12:00"), %{})) ==
             "EARENDIL-004 · PUQ 13:04Z pass AOS moved 1 min 30 s earlier by Northlight: 13:04:30–13:12:00Z"

    next_day = %{"starts_at" => "2026-11-15T00:00:00Z", "ends_at" => "2026-11-15T00:08:00Z"}

    assert text.(moved.(w.("23:59:30", "23:59:59"), next_day, %{})) =~
             "pass window changed by Northlight: 11-15 00:00:00–00:08:00Z"

    midnight = %{"starts_at" => "2026-11-14T23:58:00Z", "ends_at" => "2026-11-15T00:06:00Z"}

    assert text.(moved.(w.("23:57:00", "23:59:00"), midnight, %{})) =~
             ": 11-14 23:58:00–11-15 00:06:00Z"

    assert text.(
             moved.(w.("13:00:00", "13:10:00"), w.("13:02:00", "13:13:00"), %{
               "provider_name" => nil
             })
           ) ==
             "EARENDIL-004 · PUQ 13:02Z pass window changed by the provider: 13:02:00–13:13:00Z"
  end

  test "unknown kinds use the sentence-case key plus the entity, never Title Case" do
    unknown = entry(:limit_violation, %{title: "Limit Violation", spacecraft_id: "sc-4"})
    assert %{text: "Limit violation on EARENDIL-004"} = EventSentences.describe(unknown, @ctx)

    written = entry(:limit_violation, %{title: "VBAT crossed red low", spacecraft_id: "sc-4"})

    assert %{text: "VBAT crossed red low on EARENDIL-004"} =
             EventSentences.describe(written, @ctx)
  end
end
