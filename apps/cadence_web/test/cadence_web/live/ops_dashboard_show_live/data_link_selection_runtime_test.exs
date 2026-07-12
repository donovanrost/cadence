defmodule CadenceWeb.OpsDashboardShowLive.DataLinkSelectionRuntimeTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection

  describe "runtime selection matching" do
    test "keeps selected refs that match the active live runtime context" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_234,
        "spacecraft_id" => "sc-1",
        "realm" => "rehearsal",
        "data_view" => "canonical",
        "data_source_id" => "questdb-rehearsal",
        "source_binding_id" => "binding-1",
        "limit_mode" => "observed"
      }

      runtime_context =
        runtime_context(%{
          scope_kind: "spacecraft",
          scope_id: "sc-1",
          spacecraft_id: "sc-1",
          realm: "rehearsal",
          data_view: "canonical",
          data_source_id: "questdb-rehearsal",
          source_binding_id: "binding-1",
          limit_mode: "observed"
        })

      assert DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context) ==
               selected_ref

      assert DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               runtime_context
             )
    end

    test "drops selected refs when runtime data context changes" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_234,
        "data_source_id" => "questdb-rehearsal"
      }

      runtime_context = runtime_context(%{data_source_id: "questdb-flight"})

      refute DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context)

      refute DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               runtime_context
             )
    end

    test "keeps setup resource refs when selected resource scope differs from dashboard runtime scope" do
      selected_ref = %{
        "target" => "transport",
        "target_id" => "transport-alpha",
        "scope_kind" => "transport",
        "scope_id" => "transport-alpha",
        "transport_id" => "transport-alpha",
        "realm" => "flight",
        "data_source_id" => "managed-operational",
        "source_binding_id" => "ops-binding"
      }

      runtime_context =
        runtime_context(%{
          scope_kind: "mission",
          scope_id: "mission-1",
          realm: "flight",
          data_source_id: "managed-operational",
          source_binding_id: "ops-binding"
        })

      assert DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context) ==
               selected_ref

      assert DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               runtime_context
             )
    end

    test "drops setup resource refs when same-kind runtime scope changes away from selected resource" do
      selected_ref = %{
        "target" => "link",
        "target_id" => "link-beta",
        "scope_kind" => "link",
        "scope_id" => "link-beta",
        "scope_ids" => "link-alpha,link-beta",
        "scope_link_id" => "link-beta",
        "realm" => "flight",
        "data_source_id" => "managed-operational",
        "source_binding_id" => "ops-binding"
      }

      matching_runtime_context =
        runtime_context(%{
          scope_kind: "link",
          scope_id: "link-alpha",
          scope_ids: ["link-alpha", "link-beta"],
          realm: "flight",
          data_source_id: "managed-operational",
          source_binding_id: "ops-binding"
        })

      changed_runtime_context =
        runtime_context(%{
          scope_kind: "link",
          scope_id: "link-alpha",
          scope_ids: ["link-alpha", "link-gamma"],
          realm: "flight",
          data_source_id: "managed-operational",
          source_binding_id: "ops-binding"
        })

      assert DataLinkSelection.selected_ref_for_runtime_context(
               selected_ref,
               matching_runtime_context
             ) == selected_ref

      refute DataLinkSelection.selected_ref_for_runtime_context(
               selected_ref,
               changed_runtime_context
             )

      refute DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               changed_runtime_context
             )
    end

    test "matches selected refs against archive time bounds" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_500
      }

      runtime_context =
        runtime_context(%{
          time_context: %{
            "mode" => "archive",
            "from" => DateTime.from_unix!(1, :second),
            "to" => DateTime.from_unix!(2, :second)
          }
        })

      assert DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context) ==
               selected_ref

      runtime_context =
        runtime_context(%{
          time_context: %{
            "mode" => "archive",
            "from" => DateTime.from_unix!(2, :second),
            "to" => DateTime.from_unix!(3, :second)
          }
        })

      refute DataLinkSelection.selected_ref_for_runtime_context(selected_ref, runtime_context)
    end

    test "requires query-restored telemetry refs to match concrete scope" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_234,
        "spacecraft_id" => "sc-1"
      }

      assert DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               runtime_context(%{
                 scope_kind: "spacecraft",
                 scope_id: "sc-1",
                 spacecraft_id: "sc-1"
               })
             )

      refute DataLinkSelection.selected_ref_matches_query_runtime_context?(
               selected_ref,
               runtime_context(%{
                 scope_kind: "spacecraft",
                 scope_id: "sc-2",
                 spacecraft_id: "sc-2"
               })
             )
    end

    test "keeps replay selections only when replay context and time bounds match" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_500,
        "time_axis" => "generation_time",
        "replay_run_id" => "replay-run-1"
      }

      matching_context =
        runtime_context(%{
          time_context: %{
            "mode" => "replay_run",
            "axis" => "generation_time",
            "replay_run_id" => "replay-run-1",
            "from" => DateTime.from_unix!(1, :second),
            "to" => DateTime.from_unix!(2, :second)
          }
        })

      assert DataLinkSelection.selected_ref_for_runtime_context(selected_ref, matching_context) ==
               selected_ref

      refute DataLinkSelection.selected_ref_for_runtime_context(
               selected_ref,
               runtime_context(%{
                 time_context: %{
                   "mode" => "replay_run",
                   "axis" => "generation_time",
                   "replay_run_id" => "replay-run-2",
                   "from" => DateTime.from_unix!(1, :second),
                   "to" => DateTime.from_unix!(2, :second)
                 }
               })
             )

      refute DataLinkSelection.selected_ref_for_runtime_context(
               selected_ref,
               runtime_context(%{
                 time_context: %{
                   "mode" => "replay_run",
                   "axis" => "generation_time",
                   "replay_run_id" => "replay-run-1",
                   "from" => DateTime.from_unix!(2, :second),
                   "to" => DateTime.from_unix!(3, :second)
                 }
               })
             )
    end
  end

  describe "stale selection decisions" do
    test "keeps stale-selection queries when selected ref survives runtime context" do
      selected_ref = %{
        "target" => "telemetry_sample",
        "target_id" => "sample-1",
        "timestamp_ms" => 1_234,
        "data_source_id" => "questdb-flight"
      }

      decision =
        DataLinkSelection.stale_selection_decision(
          %{"data_source_id" => "questdb-flight"},
          selected_ref,
          %{"selected_target" => "telemetry_sample"},
          runtime_context(%{data_source_id: "questdb-flight"})
        )

      assert decision == %{action: :keep, query: %{"data_source_id" => "questdb-flight"}}
    end

    test "clears selection query keys when selected ref becomes stale" do
      decision =
        DataLinkSelection.stale_selection_decision(
          %{
            "data_source_id" => "questdb-flight",
            "selected_target" => "telemetry_sample",
            "selected_id" => "sample-1"
          },
          %{
            "target" => "telemetry_sample",
            "target_id" => "sample-1",
            "timestamp_ms" => 1_234,
            "data_source_id" => "questdb-rehearsal"
          },
          %{"selected_target" => "telemetry_sample"},
          runtime_context(%{data_source_id: "questdb-flight"})
        )

      assert decision.action == :clear_stale
      assert decision.query["data_source_id"] == "questdb-flight"

      assert Map.take(decision.query, Map.keys(DataLinkSelection.clear_selection_query())) ==
               DataLinkSelection.clear_selection_query()
    end

    test "clears scoped setup-resource query keys when same-kind scope changes away from selected resource" do
      decision =
        DataLinkSelection.stale_selection_decision(
          %{
            "scope_kind" => "link",
            "scope_ids" => "link-alpha,link-gamma",
            "selected_target" => "link",
            "selected_id" => "link-beta",
            "selected_scope_kind" => "link",
            "selected_scope_id" => "link-beta",
            "selected_scope_ids" => "link-alpha,link-beta",
            "selected_scope_link_id" => "link-beta"
          },
          %{
            "target" => "link",
            "target_id" => "link-beta",
            "scope_kind" => "link",
            "scope_id" => "link-beta",
            "scope_ids" => "link-alpha,link-beta",
            "scope_link_id" => "link-beta"
          },
          %{"selected_target" => "link"},
          runtime_context(%{
            scope_kind: "link",
            scope_id: "link-alpha",
            scope_ids: ["link-alpha", "link-gamma"]
          })
        )

      assert decision.action == :clear_stale
      assert decision.query["scope_kind"] == "link"
      assert decision.query["scope_ids"] == "link-alpha,link-gamma"

      assert Map.take(decision.query, Map.keys(DataLinkSelection.clear_selection_query())) ==
               DataLinkSelection.clear_selection_query()
    end

    test "clears selection query keys without stale UI action when no selection exists" do
      decision =
        DataLinkSelection.stale_selection_decision(
          %{"spacecraft_id" => nil},
          nil,
          nil,
          runtime_context(%{})
        )

      assert decision.action == :none

      assert Map.take(decision.query, Map.keys(DataLinkSelection.clear_selection_query())) ==
               DataLinkSelection.clear_selection_query()
    end
  end

  defp runtime_context(overrides) do
    Map.merge(
      %{
        scope_kind: nil,
        scope_id: nil,
        spacecraft_id: nil,
        time_context: %{"mode" => "live"},
        replay_run_id: nil,
        realm: nil,
        data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        limit_mode: nil,
        data_context: %{}
      },
      overrides
    )
  end
end
