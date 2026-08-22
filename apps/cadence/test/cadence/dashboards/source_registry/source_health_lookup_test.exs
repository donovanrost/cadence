defmodule Cadence.Dashboards.SourceRegistry.SourceHealthLookupTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.SourceRegistryFixtures

  alias Cadence.Dashboards.ResolvedSourceBinding

  alias Cadence.DataSources.{SourceHealthEvent, SourceHealthStatus}

  alias Cadence.Dashboards.SourceRegistry.SourceHealthLookup
  alias Cadence.OperationalEvents.EffectiveInterval

  test "prefers an exact injected status over the source-level fallback" do
    request = source_request()
    resolved_binding = resolved_binding()

    fallback =
      status(
        source_health_key:
          source_health_key(%{
            source_binding_id: nil,
            realm: nil,
            replay_run_id: nil,
            dataset: nil
          }),
        source_health_event_id: "fallback-health-event"
      )

    exact =
      status(
        source_health_key: source_health_key(%{}),
        source_health_event_id: "exact-health-event"
      )

    assert {:ok, ^exact} =
             SourceHealthLookup.fetch(
               request,
               resolved_binding,
               source_health_statuses: [fallback, exact]
             )
  end

  test "uses the source-level injected status when no exact status exists" do
    fallback =
      status(
        source_health_key:
          source_health_key(%{
            source_binding_id: nil,
            realm: nil,
            replay_run_id: nil,
            dataset: nil
          }),
        source_health_event_id: "fallback-health-event"
      )

    assert {:ok, ^fallback} =
             SourceHealthLookup.fetch(
               source_request(),
               resolved_binding(),
               source_health_statuses: [fallback]
             )
  end

  test "selects the replay-aware interval for the injected health event" do
    parent = self()
    observed_at = ~U[2026-07-19 10:00:00Z]

    status =
      status(
        source_health_event_id: "health-event-1",
        replay_run_id: "replay-run-1",
        observed_at: observed_at,
        last_seen_at: observed_at
      )

    unrelated = interval("unrelated", "another-event", %{})

    selected =
      interval(
        "selected",
        "operational_event:source_health_event:replay-run-1:health-event-1",
        %{}
      )

    assert ^selected =
             SourceHealthLookup.interval(
               replay_source_request(),
               resolved_binding(),
               status,
               source_health_intervals_fun: fn organization_id, mission_id, opts ->
                 send(parent, {:interval_lookup, organization_id, mission_id, opts})
                 [unrelated, selected]
               end
             )

    assert_received {:interval_lookup, "org-1", "mission-1", opts}
    assert opts[:at] == observed_at
    assert opts[:logical_source] == :telemetry
    assert opts[:data_source_id] == "source-1"
    assert opts[:source_binding_id] == "flight-telemetry"
    assert opts[:realm] == :flight
    assert opts[:dataset] == "flight"
    assert opts[:replay_run_id] == "replay-run-1"
  end

  defp resolved_binding do
    %ResolvedSourceBinding{
      binding: data_binding("source-1"),
      data_source: data_source("source-1", []),
      realm: :flight,
      dataset: "flight"
    }
  end

  defp status(overrides) do
    struct!(
      SourceHealthStatus,
      Keyword.merge(
        [
          source_health_key: source_health_key(%{}),
          source_health_event_id: "health-event-1",
          organization_id: "org-1",
          mission_id: "mission-1",
          logical_source: :telemetry,
          data_source_id: "source-1",
          source_binding_id: "flight-telemetry",
          realm: :flight,
          replay_run_id: nil,
          dataset: "flight",
          event_type: :healthy,
          source_health: :healthy,
          reason: :source_recovered,
          observed_at: ~U[2026-07-19 10:00:00Z],
          last_seen_at: ~U[2026-07-19 10:00:00Z]
        ],
        overrides
      )
    )
  end

  defp source_health_key(overrides) do
    %{
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :telemetry,
      data_source_id: "source-1",
      source_binding_id: "flight-telemetry",
      realm: :flight,
      replay_run_id: nil,
      dataset: "flight"
    }
    |> Map.merge(overrides)
    |> SourceHealthEvent.source_health_key()
  end

  defp interval(interval_id, source_event_id, payload) do
    %EffectiveInterval{
      interval_id: interval_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      kind: :source_health,
      subject_kind: :data_source,
      subject_id: "source-1",
      starts_at: ~U[2026-07-19 09:55:00Z],
      source_event_id: source_event_id,
      payload: payload
    }
  end
end
