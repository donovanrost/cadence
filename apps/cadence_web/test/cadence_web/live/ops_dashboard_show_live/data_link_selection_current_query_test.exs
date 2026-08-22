defmodule CadenceWeb.OpsDashboardShowLive.DataLinkSelectionCurrentQueryTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection

  describe "panel query helpers" do
    test "builds compact current queries from runtime context and selected refs" do
      query =
        base_query_attrs(%{
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
        |> DataLinkSelection.current_query()
        |> DataLinkSelection.compact_query()

      assert query == %{
               "spacecraft_id" => "sc-1",
               "selected_link" => "link-1",
               "selected_target" => "telemetry_point",
               "selected_id" => "HK.counter",
               "selected_placement" => "placement-1",
               "selected_time" => 12_345,
               "panel" => "data_link"
             }
    end

    test "builds current queries for non-default runtime context" do
      query =
        base_query_attrs(%{
          scope_kind: "contact",
          scope_id: "contact-1",
          time_mode: "archive",
          time_from: "2026-01-01T00:00:00Z",
          time_to: "2026-01-01T00:05:00Z",
          realm: "rehearsal",
          default_realm: "flight",
          data_view: "as_recorded",
          default_data_view: "canonical",
          data_source_id: "questdb-rehearsal",
          source_binding_id: nil,
          default_source_binding_id: "binding-flight",
          limit_mode: "observed"
        })
        |> DataLinkSelection.current_query()
        |> DataLinkSelection.compact_query()

      assert query == %{
               "scope_kind" => "contact",
               "scope_id" => "contact-1",
               "time_mode" => "archive",
               "from" => "2026-01-01T00:00:00Z",
               "to" => "2026-01-01T00:05:00Z",
               "realm" => "rehearsal",
               "data_view" => "as_recorded",
               "data_source_id" => "questdb-rehearsal",
               "source_binding_id" => "primary"
             }
    end
  end

  defp base_query_attrs(overrides) do
    Map.merge(
      %{
        selected_ref: nil,
        selection_query: nil,
        evidence_query: nil,
        scope_kind: nil,
        scope_id: nil,
        time_mode: "live",
        time_from: nil,
        time_to: nil,
        replay_run_id: nil,
        realm: "flight",
        default_realm: "flight",
        data_view: "canonical",
        default_data_view: "canonical",
        data_source_id: nil,
        source_binding_id: nil,
        default_source_binding_id: nil,
        limit_mode: "observed"
      },
      overrides
    )
  end
end
