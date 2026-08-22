defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQueryParamsTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeQueryParams
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  test "builds compactable URL params from runtime context and selected refs" do
    params =
      RuntimeQueryParams.to_params(%{
        selected_ref: %{
          "link_id" => "link-1",
          "target" => "telemetry_point",
          "target_id" => "HK.counter",
          "placement_id" => "placement-1",
          "timestamp_ms" => 12_345
        },
        selection_query: %{
          "selected_link" => "stale-link",
          "selected_target" => "limit_event",
          "selected_id" => "stale-id"
        },
        scope_kind: "spacecraft",
        scope_id: "sc-1",
        time_mode: "live",
        realm: "flight",
        default_realm: "flight",
        data_view: "canonical",
        default_data_view: "canonical",
        limit_mode: "observed"
      })
      |> RuntimeQueryParams.compact()

    assert params == %{
             "spacecraft_id" => "sc-1",
             "selected_link" => "link-1",
             "selected_target" => "telemetry_point",
             "selected_id" => "HK.counter",
             "selected_placement" => "placement-1",
             "selected_time" => 12_345,
             "panel" => "data_link"
           }
  end

  test "preserves non-default runtime query dimensions" do
    params =
      RuntimeQueryParams.to_params(%{
        scope_kind: "contact",
        scope_id: "contact-1",
        time_mode: "archive",
        time_from: "2026-01-01T00:00:00Z",
        time_to: "2026-01-01T00:05:00Z",
        realm: "rehearsal",
        default_realm: "flight",
        data_view: "as_recorded",
        default_data_view: "canonical",
        compare_data_view: "all_revisions",
        data_source_id: "questdb-rehearsal",
        source_binding_id: nil,
        default_source_binding_id: "binding-flight",
        limit_mode: "observed"
      })
      |> RuntimeQueryParams.compact()

    assert params == %{
             "scope_kind" => "contact",
             "scope_id" => "contact-1",
             "time_mode" => "archive",
             "from" => "2026-01-01T00:00:00Z",
             "to" => "2026-01-01T00:05:00Z",
             "realm" => "rehearsal",
             "data_view" => "as_recorded",
             "compare_data_view" => "all_revisions",
             "data_source_id" => "questdb-rehearsal",
             "source_binding_id" => "primary"
           }
  end

  test "serializes multi-select scope ids as durable URL query state" do
    params =
      RuntimeQueryParams.to_params(%{
        scope_kind: "source_endpoint",
        scope_id: "endpoint-alpha",
        scope_ids: ["endpoint-alpha", "endpoint-beta"],
        time_mode: "live",
        realm: "flight",
        default_realm: "flight",
        data_view: "canonical",
        default_data_view: "canonical",
        limit_mode: "observed"
      })
      |> RuntimeQueryParams.compact()

    assert params == %{
             "scope_kind" => "source_endpoint",
             "scope_ids" => "endpoint-alpha,endpoint-beta"
           }
  end

  test "serializes single scope ids without requiring duplicate scope_id input" do
    spacecraft_params =
      RuntimeQueryParams.to_params(%{
        scope_kind: "spacecraft",
        scope_ids: ["sc-1"],
        time_mode: "live",
        realm: "flight",
        default_realm: "flight",
        data_view: "canonical",
        default_data_view: "canonical",
        limit_mode: "observed"
      })
      |> RuntimeQueryParams.compact()

    assert spacecraft_params == %{"spacecraft_id" => "sc-1"}

    endpoint_params =
      RuntimeQueryParams.to_params(%{
        scope_kind: "source_endpoint",
        scope_ids: ["endpoint-alpha"],
        time_mode: "live",
        realm: "flight",
        default_realm: "flight",
        data_view: "canonical",
        default_data_view: "canonical",
        limit_mode: "observed"
      })
      |> RuntimeQueryParams.compact()

    assert endpoint_params == %{
             "scope_kind" => "source_endpoint",
             "scope_id" => "endpoint-alpha"
           }
  end

  test "evidence query owns the active panel when present" do
    params =
      RuntimeQueryParams.to_params(%{
        selected_ref: %{
          "link_id" => "link-1",
          "target" => "telemetry_point",
          "target_id" => "HK.counter"
        },
        evidence_query: %{
          "selected_evidence_kind" => "source_warning",
          "selected_source_request" => "request-1"
        }
      })
      |> RuntimeQueryParams.compact()

    assert params["selected_link"] == "link-1"
    assert params["selected_evidence_kind"] == "source_warning"
    assert params["selected_source_request"] == "request-1"
    assert params["panel"] == "evidence"
  end

  test "constructs from known atom and binary fields only" do
    params =
      RuntimeQueryParams.new(%{
        "scope_kind" => "mission",
        "unknown" => "ignored",
        scope_id: "mission-1",
        from: "ignored"
      })

    assert %RuntimeQueryParams{} = params
    assert params.scope_kind == "mission"
    assert params.scope_id == "mission-1"
    refute Map.has_key?(params, :unknown)
    refute Map.has_key?(params, :from)
  end

  test "current panel query treats typed selection queries as data-link state" do
    assert RuntimeQueryParams.current_panel_query(
             SelectionQuery.new(%{"selected_id" => "point-1"}),
             %{}
           ) == %{
             "panel" => "data_link"
           }

    assert RuntimeQueryParams.current_panel_query(
             %{"selected_id" => "point-1"},
             %{"selected_evidence_kind" => "warning"}
           ) == %{"panel" => "evidence"}
  end
end
