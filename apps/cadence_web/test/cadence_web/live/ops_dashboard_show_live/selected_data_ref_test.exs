defmodule CadenceWeb.OpsDashboardShowLive.SelectedDataRefTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.SelectedDataRef

  test "normalizes empty refs and preserves payload maps" do
    assert SelectedDataRef.new(%{"target" => "telemetry_sample", "target_id" => ""}) == %{
             "target" => "telemetry_sample"
           }

    assert SelectedDataRef.new(%{}) == nil
    refute SelectedDataRef.present?(nil)
  end

  test "reads string-keyed and atom-keyed selected refs" do
    assert SelectedDataRef.value(%{"target" => "telemetry_sample"}, "target") ==
             "telemetry_sample"

    assert SelectedDataRef.value(%{target: "telemetry_sample"}, "target") == "telemetry_sample"
    assert SelectedDataRef.observable_id(%{point_id: "HK.counter"}) == "HK.counter"
    assert SelectedDataRef.observable_id(%{"observable_id" => "HK.voltage"}) == "HK.voltage"
  end

  test "filters refs for placements without changing global refs" do
    global_ref = %{"target" => "telemetry_sample"}
    placement_ref = %{"target" => "telemetry_sample", "placement_id" => "placement-1"}

    assert SelectedDataRef.for_placement(global_ref, "placement-1") == global_ref
    assert SelectedDataRef.for_placement(placement_ref, "placement-1") == placement_ref
    assert SelectedDataRef.for_placement(placement_ref, "placement-2") == nil
  end

  test "matches selected refs against runtime data and time context" do
    selected_ref = %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "timestamp_ms" => 1_234,
      "scope_kind" => "spacecraft",
      "scope_id" => "sc-1",
      "spacecraft_id" => "sc-1",
      "realm" => "flight",
      "data_source_id" => "questdb-flight"
    }

    runtime_context =
      runtime_context(%{
        scope_kind: "spacecraft",
        scope_id: "sc-1",
        spacecraft_id: "sc-1",
        realm: "flight",
        data_source_id: "questdb-flight"
      })

    assert SelectedDataRef.matches_query_runtime_context?(selected_ref, runtime_context)
    assert SelectedDataRef.for_runtime_context(selected_ref, runtime_context) == selected_ref

    refute SelectedDataRef.matches_query_runtime_context?(
             selected_ref,
             runtime_context(%{scope_kind: "spacecraft", scope_id: "sc-2", spacecraft_id: "sc-2"})
           )

    refute SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{realm: "rehearsal"})
           )
  end

  test "does not reject scoped targets when runtime scope is not concrete" do
    selected_ref = %{
      "target" => "contact",
      "target_id" => "contact-1",
      "timestamp_ms" => 1_234
    }

    assert SelectedDataRef.matches_runtime_context?(selected_ref, runtime_context(%{}))
    assert SelectedDataRef.matches_query_runtime_context?(selected_ref, runtime_context(%{}))
  end

  test "keeps latest contact refs without timestamp selection when scope matches" do
    selected_ref = %{
      "target" => "contact",
      "target_id" => "contact-1",
      "scope_kind" => "contact",
      "scope_id" => "contact-1",
      "realm" => "flight",
      "data_source_id" => "managed-operational",
      "source_binding_id" => "ops-binding"
    }

    runtime_context =
      runtime_context(%{
        scope_kind: "contact",
        scope_id: "contact-1",
        realm: "flight",
        data_source_id: "managed-operational",
        source_binding_id: "ops-binding"
      })

    assert SelectedDataRef.matches_runtime_context?(selected_ref, runtime_context)
    assert SelectedDataRef.matches_query_runtime_context?(selected_ref, runtime_context)
    assert SelectedDataRef.for_runtime_context(selected_ref, runtime_context) == selected_ref

    refute SelectedDataRef.matches_query_runtime_context?(
             selected_ref,
             runtime_context(%{
               scope_kind: "contact",
               scope_id: "contact-2",
               realm: "flight",
               data_source_id: "managed-operational",
               source_binding_id: "ops-binding"
             })
           )
  end

  test "keeps non-timestamped operational resource refs in live context" do
    selected_ref = %{
      "target" => "transport",
      "target_id" => "transport-alpha",
      "realm" => "flight",
      "data_source_id" => "managed-operational",
      "source_binding_id" => "ops-binding"
    }

    runtime_context =
      runtime_context(%{
        realm: "flight",
        data_source_id: "managed-operational",
        source_binding_id: "ops-binding"
      })

    assert SelectedDataRef.matches_runtime_context?(selected_ref, runtime_context)
    assert SelectedDataRef.matches_query_runtime_context?(selected_ref, runtime_context)
    assert SelectedDataRef.for_runtime_context(selected_ref, runtime_context) == selected_ref
  end

  test "drops scoped operational resource refs when same-kind runtime scope no longer contains them" do
    selected_ref = %{
      "target" => "transport",
      "target_id" => "transport-beta",
      "scope_kind" => "transport",
      "scope_id" => "transport-beta",
      "scope_ids" => "transport-alpha,transport-beta",
      "realm" => "flight"
    }

    assert SelectedDataRef.matches_query_runtime_context?(
             selected_ref,
             runtime_context(%{
               scope_kind: "transport",
               scope_id: "transport-alpha",
               scope_ids: ["transport-alpha", "transport-beta"],
               realm: "flight"
             })
           )

    refute SelectedDataRef.matches_query_runtime_context?(
             selected_ref,
             runtime_context(%{
               scope_kind: "transport",
               scope_id: "transport-alpha",
               scope_ids: ["transport-alpha", "transport-gamma"],
               realm: "flight"
             })
           )

    assert SelectedDataRef.matches_query_runtime_context?(
             selected_ref,
             runtime_context(%{
               scope_kind: "mission",
               scope_id: "mission-1",
               realm: "flight"
             })
           )
  end

  test "still requires timestamps for observation and event refs" do
    refute SelectedDataRef.matches_runtime_context?(
             %{"target" => "telemetry_sample", "target_id" => "sample-1"},
             runtime_context(%{})
           )

    refute SelectedDataRef.matches_runtime_context?(
             %{"target" => "limit_event", "target_id" => "limit-event-1"},
             runtime_context(%{})
           )

    refute SelectedDataRef.matches_runtime_context?(
             %{"target" => "operational_event", "target_id" => "operational-event-1"},
             runtime_context(%{})
           )
  end

  test "matches operational event refs against scoped runtime context" do
    selected_ref = %{
      "target" => "operational_event",
      "target_id" => "operational-event-1",
      "timestamp_ms" => 1_500,
      "scope_kind" => "source_endpoint",
      "scope_id" => "endpoint-alpha",
      "spacecraft_id" => "sc-alpha",
      "realm" => "replay",
      "replay_run_id" => "replay-run-1"
    }

    assert SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{
               scope_kind: "source_endpoint",
               scope_id: "endpoint-alpha",
               spacecraft_id: "sc-alpha",
               realm: "replay",
               replay_run_id: "replay-run-1",
               time_context: %{
                 "mode" => "replay_run",
                 "from" => DateTime.from_unix!(1, :second),
                 "to" => DateTime.from_unix!(2, :second)
               }
             })
           )

    refute SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{
               scope_kind: "source_endpoint",
               scope_id: "endpoint-beta",
               spacecraft_id: "sc-alpha",
               realm: "replay",
               replay_run_id: "replay-run-1",
               time_context: %{
                 "mode" => "replay_run",
                 "from" => DateTime.from_unix!(1, :second),
                 "to" => DateTime.from_unix!(2, :second)
               }
             })
           )
  end

  test "matches required-scope refs against multi-id runtime scope" do
    selected_ref = %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "timestamp_ms" => 1_234,
      "scope_kind" => "transport",
      "scope_id" => "transport-beta"
    }

    runtime_context =
      runtime_context(%{
        scope_kind: "transport",
        scope_id: "transport-alpha",
        scope_ids: ["transport-alpha", "transport-beta"]
      })

    assert SelectedDataRef.matches_query_runtime_context?(selected_ref, runtime_context)
    assert SelectedDataRef.matches_runtime_context?(selected_ref, runtime_context)

    refute SelectedDataRef.matches_query_runtime_context?(
             selected_ref,
             runtime_context(%{
               scope_kind: "transport",
               scope_id: "transport-alpha",
               scope_ids: ["transport-alpha", "transport-gamma"]
             })
           )
  end

  test "matches query-restored refs whose selected scope set contains runtime primary scope" do
    selected_ref = %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "timestamp_ms" => 1_234,
      "scope_kind" => "transport",
      "scope_id" => "transport-beta",
      "scope_ids" => "transport-alpha,transport-beta"
    }

    assert SelectedDataRef.matches_query_runtime_context?(
             selected_ref,
             runtime_context(%{
               scope_kind: "transport",
               scope_id: "transport-alpha"
             })
           )
  end

  test "matches compare selected refs against compare data view" do
    selected_ref = %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "timestamp_ms" => 1_234,
      "series_role" => "compare",
      "data_view" => "canonical"
    }

    assert SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{data_view: "all_revisions", compare_data_view: "canonical"})
           )

    refute SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{data_view: "all_revisions", compare_data_view: "recomputed"})
           )
  end

  test "does not treat time axis metadata as a stale-selection filter" do
    selected_ref = %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "timestamp_ms" => 1_234,
      "time_axis" => "receipt_time"
    }

    assert SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{time_context: %{"mode" => "live", "axis" => "receipt_time"}})
           )

    assert SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{time_context: %{"mode" => "live", "axis" => "generation_time"}})
           )
  end

  test "matches selected refs against archive bounds" do
    selected_ref = %{"target" => "telemetry_sample", "timestamp_ms" => 1_500}

    assert SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{
               time_context: %{
                 "mode" => "archive",
                 "from" => DateTime.from_unix!(1, :second),
                 "to" => DateTime.from_unix!(2, :second)
               }
             })
           )

    refute SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{
               time_context: %{
                 "mode" => "archive",
                 "from" => DateTime.from_unix!(2, :second),
                 "to" => DateTime.from_unix!(3, :second)
               }
             })
           )
  end

  test "matches selected refs against replay run context and bounds" do
    selected_ref = %{
      "target" => "telemetry_sample",
      "target_id" => "sample-1",
      "timestamp_ms" => 1_500,
      "replay_run_id" => "replay-run-1",
      "time_axis" => "generation_time"
    }

    assert SelectedDataRef.matches_runtime_context?(
             selected_ref,
             runtime_context(%{
               time_context: %{
                 "mode" => "replay_run",
                 "axis" => "generation_time",
                 "replay_run_id" => "replay-run-1",
                 "from" => DateTime.from_unix!(1, :second),
                 "to" => DateTime.from_unix!(2, :second)
               }
             })
           )

    refute SelectedDataRef.matches_runtime_context?(
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

    refute SelectedDataRef.matches_runtime_context?(
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

  test "derives pause archive ranges from integer and string timestamps" do
    assert SelectedDataRef.archive_range(%{"timestamp_ms" => 1_000}) ==
             {:ok, "1969-12-31T23:57:31.000Z", "1970-01-01T00:02:31.000Z"}

    assert SelectedDataRef.archive_range(%{timestamp_ms: "1000"}) ==
             {:ok, "1969-12-31T23:57:31.000Z", "1970-01-01T00:02:31.000Z"}

    assert SelectedDataRef.archive_range(%{"timestamp_ms" => "bad"}) == :error
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
        compare_data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        limit_mode: nil,
        data_context: %{}
      },
      overrides
    )
  end
end
