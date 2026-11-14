defmodule Cadence.Projections.DataSources.HealthReadWindowStorageTest do
  @moduledoc """
  api-ops' review of the read window: pins it through storage (record → list → classify). The
  stored payload is wrapped, so a change to the wrapping would otherwise turn the window off
  silently.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Projections.DataSources.Health

  @org "org-health-read-window"
  @mission "mission-health-read-window"
  @now ~U[2026-11-14 12:00:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    :ok
  end

  defp record!(binding, payload) do
    {:ok, _event, _status} =
      Health.record_source_health(
        %{
          organization_id: @org,
          mission_id: @mission,
          logical_source: :telemetry,
          data_source_id: "managed_questdb_primary",
          source_binding_id: binding,
          realm: :flight,
          dataset: "flight",
          source_health: :unavailable,
          reason: :source_unavailable,
          observed_at: DateTime.add(@now, -11 * 60, :second),
          payload: payload
        },
        invalidate_runtime_cache?: false
      )
  end

  test "a stored read status goes stale after its window; a stored probe status doesn't" do
    record!("read-binding", %{returned_frame_count: 0, circuit: %{state: :closed}})
    record!(nil, %{probe_kind: "adapter"})

    by_binding =
      @org
      |> Health.list_source_health_statuses(@mission)
      |> Map.new(&{&1.source_binding_id, &1})

    opts = [now: @now, source_health_freshness: %{default_max_age_ms: 86_400_000}]

    assert Health.read_derived?(by_binding["read-binding"])

    assert %{freshness: :stale, source_health: :unknown} =
             Health.classify_status(by_binding["read-binding"], nil, opts)

    refute Health.read_derived?(by_binding[nil])

    assert %{freshness: :fresh, source_health: :unavailable} =
             Health.classify_status(by_binding[nil], nil, opts)
  end
end
