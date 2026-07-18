defmodule Cadence.Observability.Metrics.MissionHealthSamplerTest do
  use Cadence.UnitCase, async: false

  alias Cadence.Commanding.CommandQueueEntry
  alias Cadence.Contacts.{RealizedContact, ScheduledContact}
  alias Cadence.Observability.Metrics.MissionHealthSampler
  alias Cadence.Telemetry.Sample

  test "classifies recent telemetry as available during an expected live downlink" do
    now = ~U[2026-07-18 04:00:00Z]
    scheduled = scheduled_contact(now)
    realized = realized_contact(now)

    entries = [
      command_entry("command-met", :released, DateTime.add(now, 60, :second), now),
      command_entry("command-missed", :pending, DateTime.add(now, -1, :second), now)
    ]

    start_sampler(
      now,
      %{scheduled: [scheduled], realized: [realized]},
      [%Sample{receipt_time: DateTime.add(now, -5, :second)}],
      entries
    )

    assert_receive {:otel_metric_record, "cadence.telemetry.expected", 1,
                    %{"cadence.mission.id" => "mission-test"}, _observed_at}

    assert_receive {:otel_metric_record, "cadence.telemetry.availability.interval", 1,
                    %{"cadence.mission.id" => "mission-test", "outcome" => "met"}, _observed_at}

    assert_receive {:otel_metric_record, "cadence.commanding.deadline.result", 1,
                    %{"cadence.mission.id" => "mission-test", "outcome" => "met"}, _observed_at}

    assert_receive {:otel_metric_record, "cadence.commanding.deadline.result", 1,
                    %{"cadence.mission.id" => "mission-test", "outcome" => "missed"},
                    _observed_at}

    assert_receive {:otel_metric_record, "cadence.contact.realization.delay", 3.0,
                    %{"cadence.mission.id" => "mission-test"}, _observed_at}
  end

  test "does not classify silence as unavailable outside an expected contact" do
    now = ~U[2026-07-18 04:00:00Z]
    realized = %{realized_contact(now) | lifecycle_state: :completed}

    start_sampler(now, %{scheduled: [scheduled_contact(now)], realized: [realized]}, [], [])

    assert_receive {:otel_metric_record, "cadence.telemetry.expected", 0,
                    %{"cadence.mission.id" => "mission-test"}, _observed_at}

    refute_receive {:otel_metric_record, "cadence.telemetry.availability.interval", _value,
                    _attributes, _observed_at},
                   50
  end

  test "classifies missing telemetry as unavailable during expected downlink" do
    now = ~U[2026-07-18 04:00:00Z]

    start_sampler(
      now,
      %{scheduled: [scheduled_contact(now)], realized: [realized_contact(now)]},
      [],
      []
    )

    assert_receive {:otel_metric_record, "cadence.telemetry.availability.interval", 1,
                    %{"cadence.mission.id" => "mission-test", "outcome" => "missed"},
                    _observed_at}
  end

  defp start_sampler(now, contacts, samples, entries) do
    start_supervised!(
      {MissionHealthSampler,
       reporter: self(),
       interval_ms: 60_000,
       freshness_grace_seconds: 30,
       mission_ids_fun: fn -> ["mission-test"] end,
       contacts_fun: fn "mission-test" -> contacts end,
       latest_values_fun: fn "mission-test" -> samples end,
       command_entries_fun: fn "org-test", "mission-test" -> entries end,
       now_fun: fn -> now end}
    )
  end

  defp scheduled_contact(now) do
    ScheduledContact.new(%{
      scheduled_contact_id: "scheduled-test",
      organization_id: "org-test",
      mission_id: "mission-test",
      starts_at: DateTime.add(now, -3, :second),
      lifecycle_state: :realized
    })
  end

  defp realized_contact(now) do
    RealizedContact.new(%{
      realized_contact_id: "realized-test",
      scheduled_contact_id: "scheduled-test",
      organization_id: "org-test",
      mission_id: "mission-test",
      contact_intents: [:telemetry_downlink],
      clock_mode: :live,
      lifecycle_state: :active,
      realized_at: now
    })
  end

  defp command_entry(id, lifecycle_state, expires_at, now) do
    CommandQueueEntry.new(%{
      command_queue_entry_id: id,
      mission_id: "mission-test",
      command_request_id: "request-#{id}",
      source_endpoint_ref: "source-test",
      queue_lane_key: "lane-test",
      lifecycle_state: lifecycle_state,
      expires_at: expires_at,
      enqueued_at: DateTime.add(now, -10, :second)
    })
  end
end
