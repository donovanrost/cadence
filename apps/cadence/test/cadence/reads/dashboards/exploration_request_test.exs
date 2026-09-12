defmodule Cadence.Reads.Dashboards.ExplorationRequestTest do
  use Cadence.UnitCase, async: true
  alias Cadence.Dashboards.{Document, Engine}
  alias Cadence.Dashboards.Sources.Telemetry.QueryOptions
  alias Cadence.Reads.Dashboards.{ExplorationQuery, ExplorationRequest}

  @now ~U[2026-09-07 12:00:00.123456Z]

  test "range reads use the normal engine with exact context and bounded raw sampling" do
    params = %{
      "point_id" => "tlm.hk.voltage",
      "time_mode" => "range",
      "time_axis" => "receipt_time",
      "from" => "2026-09-07T11:00:00.123456Z",
      "to" => "2026-09-07T12:00:00.654321Z",
      "selection_view" => "all_revisions",
      "validity_state" => "conflict",
      "spacecraft_id" => "spacecraft-a",
      "limit" => "12",
      "order" => "desc"
    }

    request = build(params)
    assert request.document_mode == :draft_preview
    assert request.document.metadata == %{ephemeral: true}
    assert Document.version(request.document) == nil
    assert request.document.defaults == %{}
    assert request.document.organization_id == "org"
    assert request.document.mission_id == "mission"
    [planned] = Engine.plan(request).planned_source_requests
    assert planned.logical_source == :telemetry
    assert planned.observables == ["tlm.hk.voltage"]
    assert planned.sampling.mode == :raw_series
    {opts, []} = QueryOptions.history(planned, nil, [])
    assert opts[:limit] == 12
    assert opts[:order] == :desc
    assert opts[:spacecraft_id] == "spacecraft-a"
    assert opts[:from_receipt_time] == ~U[2026-09-07 11:00:00.123456Z]
    assert opts[:to_receipt_time] == ~U[2026-09-07 12:00:00.654321Z]
    assert opts[:selection_view] == "all_revisions"
    assert opts[:validity_state] == :conflict
  end

  test "latest is a scalar read, not an unbounded history request" do
    request = build(%{"point_id" => "voltage"})
    [planned] = Engine.plan(request).planned_source_requests
    assert planned.sampling.mode == :latest
    assert request.time_context.mode == "live"
  end

  test "binding, replay and scope survive compilation without dashboard defaults" do
    request =
      build(%{
        "point_id" => "voltage",
        "time_mode" => "replay_run",
        "from" => "2026-09-07T11:00:00Z",
        "to" => "2026-09-07T12:00:00Z",
        "replay_run_id" => "run-a",
        "source_binding_id" => "binding-a",
        "data_source_id" => "source-a",
        "scope_kind" => "source_endpoint",
        "scope_id" => "endpoint-a"
      })

    assert request.data_context.realm == "replay"
    assert request.data_context.source_mode == "specific"
    assert request.data_context.source_binding_id == "binding-a"
    assert request.data_context.data_source_id == "source-a"
    assert request.data_context.replay_run_id == "run-a"
    assert request.time_context.replay_run_id == "run-a"
    assert request.scope_context.source_endpoint_id == "endpoint-a"
  end

  test "navigation selection cannot change execution identity; query and tenant changes do" do
    params = %{"point_id" => "voltage", "time_mode" => "last_1h"}
    original = build(params)

    selected =
      build(Map.merge(params, %{"sample_id" => "sample-a", "source_dashboard_id" => "origin"}))

    assert selected == original
    refute build(Map.put(params, "order", "asc")).dashboard_id == original.dashboard_id
    refute build(Map.put(params, "point_id", "current")).dashboard_id == original.dashboard_id
    {:ok, context} = ExplorationQuery.admit(params, @now)
    {:ok, foreign} = ExplorationRequest.build("other-org", "mission", context)
    refute foreign.dashboard_id == original.dashboard_id
  end

  test "a missing point never silently chooses the first catalog entry" do
    {:ok, context} = ExplorationQuery.admit(%{}, @now)
    assert {:error, :point_required} = ExplorationRequest.build("org", "mission", context)
  end

  defp build(params) do
    {:ok, context} = ExplorationQuery.admit(params, @now)
    {:ok, request} = ExplorationRequest.build("org", "mission", context)
    request
  end
end
