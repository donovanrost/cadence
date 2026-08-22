defmodule CadenceWeb.OpsDashboardShowLive.RuntimeContextTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeContext

  test "builds a context from atom and binary keyed maps" do
    context =
      RuntimeContext.new(%{
        "scope_kind" => "mission",
        "scope_id" => "mission-1",
        "scope_ids" => ["mission-1"],
        "time_mode" => "archive",
        "unknown" => "ignored",
        dashboard_time_mode: "ignored"
      })

    assert %RuntimeContext{} = context
    assert context.scope_kind == "mission"
    assert context.scope_id == "mission-1"
    assert context.scope_ids == ["mission-1"]
    assert context.time_mode == "archive"
    refute Map.has_key?(context, :unknown)
    refute Map.has_key?(context, :dashboard_time_mode)
  end

  test "detects runtime context changes from the resolved context maps" do
    context =
      RuntimeContext.new(%{
        scope_context: %{"primary" => %{"kind" => "mission", "ids" => ["mission-1"]}},
        time_context: %{"mode" => "live"},
        data_context: %{"realm" => "flight"},
        limit_context: %{"semantics_mode" => "observed"}
      })

    assigns = %{
      dashboard_scope_context: context.scope_context,
      dashboard_time_context: context.time_context,
      dashboard_data_context: context.data_context,
      dashboard_limit_context: context.limit_context
    }

    refute RuntimeContext.changed?(assigns, context)

    assert RuntimeContext.changed?(
             %{assigns | dashboard_time_context: %{"mode" => "archive"}},
             context
           )
  end

  test "projects runtime context into LiveView runtime assigns" do
    context =
      RuntimeContext.new(%{
        scope_kind: "spacecraft",
        scope_id: "sc-1",
        scope_ids: ["sc-1", "sc-2"],
        scope_context: %{"primary" => %{"kind" => "spacecraft", "ids" => ["sc-1"]}},
        spacecraft_id: "sc-1",
        time_mode: "replay_run",
        time_from: nil,
        time_to: nil,
        replay_run_id: "replay-1",
        time_validation: "valid",
        realm: "replay",
        data_view: "all_revisions",
        compare_data_view: "canonical",
        data_source_id: "questdb-replay",
        source_binding_id: "replay-binding",
        limit_mode: "observed",
        limit_mode_fallback: %{
          "requested_mode" => "projected",
          "applied_mode" => "observed",
          "reason" => "unsupported_limit_semantics_mode"
        },
        time_context: %{"mode" => "replay_run", "replay_run_id" => "replay-1"},
        data_context: %{"realm" => "replay"},
        limit_context: %{"semantics_mode" => "observed"}
      })

    assert RuntimeContext.field_assigns(context) == %{
             context_spacecraft_id: "sc-1",
             context_scope_kind: "spacecraft",
             context_scope_id: "sc-1",
             context_scope_ids: ["sc-1", "sc-2"],
             dashboard_scope_context: context.scope_context,
             dashboard_time_mode: "replay_run",
             dashboard_time_axis: nil,
             dashboard_time_from: nil,
             dashboard_time_to: nil,
             dashboard_replay_run_id: "replay-1",
             dashboard_time_validation: "valid",
             dashboard_data_realm: "replay",
             dashboard_data_view: "all_revisions",
             dashboard_compare_data_view: "canonical",
             dashboard_data_source_id: "questdb-replay",
             dashboard_source_binding_id: "replay-binding",
             dashboard_limit_mode: "observed",
             dashboard_limit_mode_fallback: context.limit_mode_fallback,
             dashboard_hidden_marker_categories: [],
             dashboard_time_context: context.time_context,
             dashboard_data_context: context.data_context,
             dashboard_limit_context: context.limit_context
           }
  end
end
