defmodule Cadence.Reads.PassTelemetryStoredTest do
  @moduledoc "ux U60: a pass detail's telemetry_stored, from the latest settle event on its contact."
  use Cadence.DataCase, async: true

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Reads.PassTelemetryStored

  @org "org-telemetry-stored"
  @mission "mission-telemetry-stored"

  defp settle!(contact, through, at) do
    %{
      event_id: "settled-#{contact}-#{DateTime.to_unix(at)}",
      organization_id: @org,
      mission_id: @mission,
      occurred_at: at,
      recorded_at: at,
      effective_at: at,
      category: :data_source,
      kind: :source_watermark_settled,
      severity: :info,
      subject: %{kind: :contact, id: contact},
      scope: %{spacecraft_id: "sc-8", realized_contact_id: contact},
      current: %{complete_through: through},
      payload: %{
        ground_station_ref: "SVB",
        starts_at: "2026-11-15T03:10:02Z",
        ends_at: "2026-11-15T03:19:57Z"
      }
    }
    |> Event.new()
    |> OperationalEvents.persist_event()
  end

  test "the latest settle on the pass's realized contact, with its sentence; nil without one" do
    assert PassTelemetryStored.read(@org, @mission, nil, "EARENDIL-008") == nil
    assert PassTelemetryStored.read(@org, @mission, "realized-1", "EARENDIL-008") == nil

    {:ok, _} = settle!("realized-1", "2026-11-15T03:19:20Z", ~U[2026-11-15 03:20:00Z])
    {:ok, _} = settle!("realized-1", "2026-11-15T03:19:40Z", ~U[2026-11-15 03:21:00Z])
    {:ok, _} = settle!("realized-other", "2026-11-15T03:30:00Z", ~U[2026-11-15 03:31:00Z])

    assert %{
             through: ~U[2026-11-15 03:19:40Z],
             los: ~U[2026-11-15 03:19:57Z],
             settled_at: ~U[2026-11-15 03:21:00.000000Z],
             text:
               "EARENDIL-008 · SVB 03:10Z pass: telemetry stored through 03:19:40Z (LOS 03:19:57Z)"
           } = PassTelemetryStored.read(@org, @mission, "realized-1", "EARENDIL-008")
  end
end
