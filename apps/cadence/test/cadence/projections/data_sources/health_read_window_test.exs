defmodule Cadence.Projections.DataSources.HealthReadWindowTest do
  @moduledoc """
  qa/api-ops 11-14: health a dashboard read recorded (a timeout) stays fresh for minutes, not a
  day, so one slow read doesn't leave a setup blocker on Now or a warning on every save. Probes and
  connection tests keep the long window.
  """
  use ExUnit.Case, async: true

  alias Cadence.DataSources.SourceHealthStatus
  alias Cadence.Projections.DataSources.Health

  @now ~U[2026-11-14 12:00:00.000000Z]

  defp status(payload, minutes_ago, reason) do
    seen = DateTime.add(@now, -minutes_ago * 60, :second)

    %SourceHealthStatus{
      data_source_id: "managed_questdb_primary",
      source_health: :unavailable,
      reason: reason,
      observed_at: seen,
      last_seen_at: seen,
      payload: payload
    }
  end

  # The day-long default the app runs with (the test config sets a shorter one).
  defp opts(policy \\ %{}),
    do: [now: @now, source_health_freshness: Map.merge(%{default_max_age_ms: 86_400_000}, policy)]

  @read %{"returned_frame_count" => 0, "circuit" => %{"state" => "closed"}, "warning_codes" => []}
  @probe %{"probe_kind" => "adapter"}

  test "a read's unavailable is fresh for 10 minutes, then unknown" do
    assert %{freshness: :fresh, source_health: :unavailable} =
             Health.classify_status(status(@read, 9, :source_unavailable), nil, opts())

    assert %{freshness: :stale, source_health: :unknown, raw_source_health: :unavailable} =
             Health.classify_status(status(@read, 11, :source_unavailable), nil, opts())
  end

  test "a probe's unavailable keeps the long window" do
    assert %{freshness: :fresh, source_health: :unavailable} =
             Health.classify_status(status(@probe, 60, :source_probe_timeout), nil, opts())
  end

  test "the read window is a policy setting" do
    opts = opts(%{read_derived_max_age_ms: 3_600_000})

    assert %{freshness: :fresh} =
             Health.classify_status(status(@read, 30, :source_unavailable), nil, opts)
  end
end
