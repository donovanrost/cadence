defmodule Cadence.Dashboards.Sources.Telemetry.PhysicalSampleRequestTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.SourceRegistryFixtures

  alias Cadence.Dashboards.{
    DataContext,
    Engine,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ScopeContext,
    TimeContext
  }

  alias Cadence.Dashboards.Sources.Telemetry.PhysicalSampleRequest
  alias Cadence.Reads.Dashboards.{ExplorationQuery, ExplorationRequest}

  test "accepts actual Explore plans for latest, relative and explicit clock windows" do
    for params <- [
          %{},
          %{"time_mode" => "last_1h", "time_axis" => "generation_time"},
          %{"time_mode" => "live", "time_axis" => "receipt_time"},
          %{
            "time_mode" => "range",
            "time_axis" => "receipt_time",
            "from" => "2026-09-08T12:00:00.123456Z",
            "to" => "2026-09-08T12:01:00.123456Z"
          }
        ] do
      params =
        Map.merge(params, %{
          "point_id" => "HK.counter",
          "scope_kind" => "source_endpoint",
          "scope_id" => "endpoint-1"
        })

      assert {:ok, context} = ExplorationQuery.admit(params, ~U[2026-09-08 12:01:00.123456Z])
      assert {:ok, request} = ExplorationRequest.build("org-1", "mission-1", context)
      [planned] = Engine.plan(request).planned_source_requests
      assert {:ok, query} = PhysicalSampleRequest.build(planned, resolved_binding(), selection())
      assert query.source_endpoint_ids == ["endpoint-1"]
      assert query.receipt_time == ~U[2026-09-08 12:00:05.654321Z]
    end
  end

  test "retains exact selected identity, source, scope and microsecond receipt bounds" do
    scope = %ScopeContext{
      spacecraft_id: "sc-1",
      primary: %{kind: :source_endpoint, mode: :many, ids: ["endpoint-1", "endpoint-2"]},
      filters: %{source_endpoint_ids: ["endpoint-2"]}
    }

    request = request(scope_context: scope)

    assert {:ok, query} = PhysicalSampleRequest.build(request, resolved_binding(), selection())
    assert query.organization_id == "org-1"
    assert query.mission_id == "mission-1"
    assert query.point_id == "HK.counter"
    assert query.sample_id == "sample-1"
    assert query.data_source_id == "source-1"
    assert query.source_binding_id == "flight-telemetry"
    assert query.spacecraft_id == "sc-1"
    assert query.source_endpoint_ids == ["endpoint-2"]
    assert query.receipt_time == ~U[2026-09-08 12:00:05.654321Z]
    assert query.from_receipt_time == ~U[2026-09-08 12:00:00.123456Z]
    assert query.to_receipt_time == ~U[2026-09-08 12:01:00.123456Z]
    refute Map.has_key?(query, :selection_view)
    refute Map.has_key?(query, :limit)
  end

  test "rejects selectors that could broaden a scoped read" do
    scopes = [
      %ScopeContext{primary: %{kind: :source_endpoint, mode: :many, ids: []}},
      %ScopeContext{primary: %{kind: :transport, mode: :one, ids: ["transport-1"]}},
      %ScopeContext{contact_id: "unresolved-contact"},
      %ScopeContext{filters: %{source_endpoint_ids: []}},
      %ScopeContext{filters: %{source_endpoint_ids: ["endpoint-1", "invalid\n"]}},
      %ScopeContext{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-1", "endpoint-2"]}
      },
      %ScopeContext{filters: %{transport_ids: ["transport-1"]}},
      %ScopeContext{mission_id: "foreign-mission"},
      %ScopeContext{
        spacecraft_id: "sc-1",
        primary: %{kind: :spacecraft, mode: :one, ids: ["sc-2"]}
      },
      %ScopeContext{
        source_endpoint_id: "endpoint-1",
        filters: %{source_endpoint_ids: ["endpoint-2"]}
      },
      %ScopeContext{primary: %{kind: :spacecraft, mode: :many, ids: ["sc-1", "sc-2"]}}
    ]

    for scope <- scopes do
      assert {:error, :unsupported_physical_sample_scope} =
               PhysicalSampleRequest.build(
                 request(scope_context: scope),
                 resolved_binding(),
                 selection()
               )
    end
  end

  test "the selection cannot replace source identity or request bounds" do
    for changes <- [
          %{organization_id: "other"},
          %{source_binding_id: "other"},
          %{from_receipt_time: nil},
          %{point_id: "HK.other"},
          %{sample_id: ""}
        ] do
      assert {:error, _} =
               PhysicalSampleRequest.build(
                 request(),
                 resolved_binding(),
                 Map.merge(selection(), changes)
               )
    end
  end

  test "generation bounds and historical binding segments intersect without rounding" do
    request = request(time_context: %{time() | axis: :generation_time})

    binding = %{
      resolved_binding()
      | segment_from: ~U[2026-09-08 12:00:02.123456Z],
        segment_to: ~U[2026-09-08 12:00:30.123456Z]
    }

    assert {:ok, query} = PhysicalSampleRequest.build(request, binding, selection())
    assert query.from_observed_at == binding.segment_from
    assert query.to_observed_at == binding.segment_to
    assert query.from_receipt_time == nil

    assert {:error, _} =
             PhysicalSampleRequest.build(
               request,
               %{binding | segment_from: ~U[2026-09-08 13:00:00Z]},
               selection()
             )
  end

  test "unbounded latest inspection does not substitute a latest or canonical sample" do
    request =
      request(
        time_context: %TimeContext{mode: :live, axis: :receipt_time},
        sampling: %{mode: :latest},
        data_context: %DataContext{realm: :flight, view: :canonical}
      )

    assert {:ok, query} = PhysicalSampleRequest.build(request, resolved_binding(), selection())
    assert query.sample_id == "sample-1"
    assert query.from_receipt_time == nil
    assert query.to_receipt_time == nil
  end

  test "malformed, conflicting, and unresolved clocks are not silently ignored" do
    for time <- [
          %{time() | axis: :occurred_at},
          %{time() | from: nil},
          %{time() | start: ~U[2026-09-08 11:00:00Z]},
          %{time() | range: %{kind: :relative}},
          %{time() | to: "invalid"},
          %{time() | from: %{time().from | month: 99}},
          %TimeContext{mode: :live, axis: :receipt_time, window_seconds: 60}
        ] do
      assert {:error, _} =
               PhysicalSampleRequest.build(
                 request(time_context: time),
                 resolved_binding(),
                 selection()
               )
    end
  end

  test "replay identity is required and data/time run conflicts fail closed" do
    binding = %{resolved_binding() | realm: :replay}

    request =
      request(
        data_context: %DataContext{realm: :replay, replay_run_id: "run-1"},
        time_context: %{time() | mode: :replay_run, replay_run_id: "run-1"}
      )

    assert {:ok, %{replay_run_id: "run-1", realm: "replay"}} =
             PhysicalSampleRequest.build(request, binding, selection())

    assert {:error, _} =
             PhysicalSampleRequest.build(
               %{request | data_context: %DataContext{realm: :replay, replay_run_id: "run-2"}},
               binding,
               selection()
             )

    assert {:error, _} =
             PhysicalSampleRequest.build(
               request(data_context: %DataContext{realm: :replay}),
               binding,
               selection()
             )
  end

  defp request(overrides \\ []) do
    source_request(
      Keyword.merge([scope_context: %ScopeContext{}, time_context: time()], overrides)
    )
    |> PlannedSourceRequest.normalize()
  end

  defp time,
    do: %TimeContext{
      mode: :range,
      axis: :receipt_time,
      from: ~U[2026-09-08 12:00:00.123456Z],
      to: ~U[2026-09-08 12:01:00.123456Z]
    }

  defp selection,
    do: %{
      point_id: "HK.counter",
      sample_id: "sample-1",
      receipt_time: ~U[2026-09-08 12:00:05.654321Z]
    }

  defp resolved_binding,
    do: %ResolvedSourceBinding{
      binding: data_binding("source-1"),
      data_source: data_source("source-1", []),
      realm: :flight,
      dataset: "flight"
    }
end
