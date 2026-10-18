defmodule Cadence.Reads.Dashboards.ExecutionEvidenceTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    Field,
    Frame,
    PlacementFrames,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCacheKey
  }

  alias Cadence.Reads.Dashboards.ExecutionEvidence

  test "caps metadata collections without exposing frame values, raw cache parts or provenance" do
    requests =
      for i <- 1..60,
          do: %PlannedSourceRequest{
            request_id: "request-#{i}",
            logical_source: :telemetry,
            observables: [String.duplicate("é", 200)],
            metadata: %{password: "private-request-secret"}
          }

    frames =
      Map.new(1..60, fn i ->
        {"placement-#{i}",
         %PlacementFrames{
           primary: [
             %Frame{
               frame_id: "frame-#{i}",
               source: :telemetry,
               shape: :scalar,
               fields: [%Field{name: "field", values: ["private-sample-secret"]}],
               meta: %{authorization: "private-frame-secret"}
             }
           ]
         }}
      end)

    result = %DashboardResolveResult{
      dashboard_id: "dashboard",
      resolve_mode: :initial,
      planned_source_requests: requests,
      frames_by_placement: frames,
      plan_metadata: %{
        degraded?: true,
        arbitrary: %{password: "private-plan-secret"},
        cache: %{
          plan_cache: %{
            status: :hit,
            key: %RuntimeCacheKey{
              layer: :plan,
              fingerprint: "opaque-fingerprint",
              parts: %{authorization: "private-cache-secret"}
            }
          }
        }
      }
    }

    collections = ExecutionEvidence.inspection(result)
    assert [%{status: "degraded"}] = Enum.find(collections, &(&1.id == "plan")).rows

    for id <- ~w(requests frames source_execution) do
      c = Enum.find(collections, &(&1.id == id))
      assert c.limited and length(c.rows) == 50
      assert length(Enum.uniq_by(c.rows, & &1.id)) == 50
    end

    for c <- collections, row <- c.rows, d <- row.details, is_binary(d.value) do
      assert byte_size(d.value) <= 256 and String.valid?(d.value)
    end

    refute Jason.encode!(collections) =~ "private-"
  end

  test "identities are exact and cannot be silently truncated or control-character rewritten" do
    for id <- [String.duplicate("x", 257), "bad\0id", "bad\nidentity"] do
      assert_raise MatchError, fn ->
        ExecutionEvidence.inspection(%DashboardResolveResult{
          dashboard_id: id,
          plan_metadata: %{}
        })
      end
    end
  end

  test "projects warning code, severity and scope without free-form messages or private evidence" do
    warning = %ResolveWarning{
      code: :unsupported_source_capability,
      severity: :error,
      scope: :field,
      placement_id: "placement/1",
      frame_id: "frame?1",
      field_name: "battery_voltage",
      message: "private-message-secret",
      details: %{
        "source_request_id" => "request#1",
        "logical_source" => "telemetry",
        "token" => "private-details-secret",
        "value" => 28.4
      },
      evidence: [%{payload: "private-evidence-secret"}],
      links: [%{route: "private-link-secret"}]
    }

    result = %DashboardResolveResult{dashboard_id: "dashboard", dashboard_warnings: [warning]}
    [plan | _] = ExecutionEvidence.inspection(result)
    assert [summary, row] = plan.rows
    assert summary.kind == "plan"
    assert Enum.find(summary.details, &(&1.key == "warnings")).value == 1
    assert row.kind == "plan_warning" and row.status == "error"

    assert Map.new(row.details, &{&1.key, &1.value}) == %{
             "warning_code" => "unsupported_source_capability",
             "scope" => "field",
             "placement_id" => "placement/1",
             "frame_id" => "frame?1",
             "field_name" => "battery_voltage",
             "source_request_id" => "request#1",
             "logical_source" => "telemetry"
           }

    assert String.match?(row.identity, ~r/\A[a-f0-9]{64}\z/)
    refute Jason.encode!(plan) =~ "private-"
    refute Jason.encode!(plan) =~ "28.4"
  end

  test "warning identities survive reordering and distinguish affected resources and severity" do
    warning = %ResolveWarning{code: :stale_data, placement_id: "one"}
    other = %{warning | placement_id: "two"}
    severe = %{warning | severity: :error}

    result = %DashboardResolveResult{
      dashboard_id: "dashboard",
      dashboard_warnings: [warning, other, severe]
    }

    [first | _] = ExecutionEvidence.inspection(result)

    [reordered | _] =
      ExecutionEvidence.inspection(%{result | dashboard_warnings: [severe, warning, other]})

    assert length(Enum.uniq_by(first.rows, & &1.id)) == 4
    assert Enum.sort_by(first.rows, & &1.id) == Enum.sort_by(reordered.rows, & &1.id)
    [foreign | _] = ExecutionEvidence.inspection(%{result | dashboard_id: "foreign"})
    refute Enum.at(first.rows, 1).identity == Enum.at(foreign.rows, 1).identity
  end

  test "plan warnings share the collection bound and preserve the total count" do
    warning = %ResolveWarning{code: :stale_data}
    warnings = for i <- 1..55, do: %{warning | placement_id: "placement-#{i}"}

    [plan | _] =
      ExecutionEvidence.inspection(%DashboardResolveResult{
        dashboard_id: "dashboard",
        dashboard_warnings: [hd(warnings) | warnings]
      })

    assert plan.limited and length(plan.rows) == 50
    assert Enum.count(plan.rows, &(&1.kind == "plan_warning")) == 49
    assert Enum.find(hd(plan.rows).details, &(&1.key == "warnings")).value == 56
    assert length(Enum.uniq_by(plan.rows, & &1.id)) == 50
  end

  test "warning identities and semantic fields are never truncated or coerced" do
    for patch <- [
          %{code: nil},
          %{code: true},
          %{severity: :other},
          %{scope: :other},
          %{placement_id: String.duplicate("x", 257)},
          %{frame_id: "bad\nframe"},
          %{field_name: <<255>>},
          %{placement_id: :not_a_string},
          %{details: %{source_request_id: %{secret: "no"}}}
        ] do
      warning = struct!(%ResolveWarning{code: :stale_data}, patch)

      assert_raise MatchError, fn ->
        ExecutionEvidence.inspection(%DashboardResolveResult{
          dashboard_id: "dashboard",
          dashboard_warnings: [warning]
        })
      end
    end
  end
end
