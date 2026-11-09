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

    assert %{
             text:
               "Contact for EARENDIL-004 at Hawaii (Demo) (HAW), 07:32:53–07:40:53Z, canceled by the provider"
           } = EventSentences.describe(canceled, @ctx)

    activated =
      entry(:binding_set_activated, %{
        summary: "Activated mission_applications:mission-earendil-demo v1"
      })

    assert %{text: "Mission applications configuration v1 activated"} =
             EventSentences.describe(activated, @ctx)
  end

  test "unknown kinds use the sentence-case key plus the entity, never Title Case" do
    unknown = entry(:limit_violation, %{title: "Limit Violation", spacecraft_id: "sc-4"})
    assert %{text: "Limit violation on EARENDIL-004"} = EventSentences.describe(unknown, @ctx)

    written = entry(:limit_violation, %{title: "VBAT crossed red low", spacecraft_id: "sc-4"})

    assert %{text: "VBAT crossed red low on EARENDIL-004"} =
             EventSentences.describe(written, @ctx)
  end
end
