defmodule Cadence.Dashboards.SaveWarningsTest do
  @moduledoc """
  lead 11-14 (dashboards' save sheet): a save's source warnings, one per (code, source, realm),
  so one slow source behind several widgets is one warning naming them all.
  """
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.SaveWarnings

  defp warning(code, placement_ids, observed_at, overrides \\ %{}) do
    %{
      code: code,
      details:
        Map.merge(
          %{
            source_warning_code: code,
            source_warning_message: "No ready source binding matches request",
            logical_source: :telemetry,
            realm: "flight",
            reasons: [:source_unavailable],
            observed_at: observed_at,
            details: %{placement_ids: placement_ids}
          },
          overrides
        )
    }
  end

  test "one slow source behind three widgets is one warning naming them, at the latest sighting" do
    early = ~U[2026-11-14 09:10:00Z]
    late = ~U[2026-11-14 09:12:00Z]

    assert [
             %{
               code: :source_unavailable,
               logical_source: :telemetry,
               realm: "flight",
               reasons: [:source_unavailable],
               observed_at: ^late,
               placement_ids: ["p1", "p2", "p3"],
               message: "No ready source binding matches request"
             }
           ] =
             SaveWarnings.group([
               warning(:source_unavailable, ["p2", "p1"], early),
               warning(:source_unavailable, ["p3"], late)
             ])
  end

  test "other sources and codes are separate; non-source warnings are left out" do
    grouped =
      SaveWarnings.group([
        warning(:source_unavailable, ["p1"], nil),
        warning(:source_degraded, ["p2"], nil, %{reasons: [:source_degraded]}),
        warning(:source_unavailable, ["p3"], nil, %{logical_source: :limits}),
        %{code: :stale_data, details: %{logical_source: :telemetry}}
      ])

    assert Enum.map(grouped, &{&1.code, &1.logical_source, &1.placement_ids}) == [
             {:source_degraded, :telemetry, ["p2"]},
             {:source_unavailable, :limits, ["p3"]},
             {:source_unavailable, :telemetry, ["p1"]}
           ]

    assert Enum.all?(grouped, &is_nil(&1.observed_at))
  end
end
