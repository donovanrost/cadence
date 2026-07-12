defmodule Cadence.Dashboards.RuntimeInvalidationRelevanceTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    Document,
    Placement,
    RuntimeCacheKey,
    RuntimeInvalidation.Event,
    RuntimeInvalidationRelevance,
    SourceWatermark,
    WidgetDef
  }

  test "matches scoped telemetry invalidations against document observable and active source identity" do
    document = telemetry_document()
    context = runtime_context()

    matching =
      invalidation(:source_watermark_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        data_source_id: "flight-source",
        source_binding_id: "flight-binding"
      )

    wrong_observable =
      invalidation(:source_watermark_changed,
        logical_source: :telemetry,
        observable: "HK.voltage",
        data_source_id: "flight-source",
        source_binding_id: "flight-binding"
      )

    wrong_source =
      invalidation(:source_watermark_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        data_source_id: "other-source"
      )

    assert RuntimeInvalidationRelevance.event_matches?(
             matching,
             scope(),
             mission(),
             document,
             context
           )

    refute RuntimeInvalidationRelevance.event_matches?(
             wrong_observable,
             scope(),
             mission(),
             document,
             context
           )

    refute RuntimeInvalidationRelevance.event_matches?(
             wrong_source,
             scope(),
             mission(),
             document,
             context
           )
  end

  test "matches active source identity from source-result cache key metadata" do
    document = telemetry_document()

    context =
      runtime_context(%{
        engine_result: %DashboardResolveResult{
          plan_metadata: %{
            cache: %{
              source_result_keys_by_request_id: %{
                "request-1" =>
                  cache_key(
                    data_source_id: "cache-source",
                    source_binding_id: "cache-binding"
                  )
              }
            }
          }
        }
      })

    matching =
      invalidation(:source_watermark_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        source_id: "cache-source",
        binding_id: "cache-binding"
      )

    assert RuntimeInvalidationRelevance.event_matches?(
             matching,
             scope(),
             mission(),
             document,
             context
           )
  end

  test "ignores telemetry invalidations for documents without telemetry primary data" do
    document = non_telemetry_document()
    context = runtime_context()

    events = [
      invalidation(:data_source_binding_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        data_source_id: "flight-source"
      ),
      invalidation(:source_health_changed,
        logical_source: :telemetry,
        data_source_id: "flight-source",
        source_health: :degraded
      ),
      invalidation(:source_watermark_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        data_source_id: "flight-source"
      )
    ]

    for event <- events do
      refute RuntimeInvalidationRelevance.event_matches?(
               event,
               scope(),
               mission(),
               document,
               context
             )

      assert %{matches?: false, reason: :document_not_relevant} =
               RuntimeInvalidationRelevance.event_relevance(
                 event,
                 scope(),
                 mission(),
                 document,
                 context
               )

      assert [] = RuntimeInvalidationRelevance.affected_placements(event, document)
    end
  end

  test "honors realm but lets data source binding changes move to a new source identity" do
    document = telemetry_document()
    context = runtime_context(%{data_realm: :rehearsal})

    wrong_realm =
      invalidation(:data_source_binding_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        realm: :flight,
        data_source_id: "new-source"
      )

    matching_realm_new_source =
      invalidation(:data_source_binding_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        realm: "rehearsal",
        data_source_id: "new-source"
      )

    refute RuntimeInvalidationRelevance.event_matches?(
             wrong_realm,
             scope(),
             mission(),
             document,
             context
           )

    assert RuntimeInvalidationRelevance.event_matches?(
             matching_realm_new_source,
             scope(),
             mission(),
             document,
             context
           )
  end

  test "matches event and limit invalidations only when the document uses those overlays" do
    overlay_document = telemetry_document(overlays: [:events, :limits])
    plain_document = telemetry_document()

    event_invalidation = invalidation(:events_changed, logical_source: :events)

    limit_invalidation =
      invalidation(:limit_definition_changed,
        logical_source: :limits,
        observable: "HK.counter"
      )

    assert RuntimeInvalidationRelevance.event_matches?(
             event_invalidation,
             scope(),
             mission(),
             overlay_document,
             runtime_context()
           )

    assert RuntimeInvalidationRelevance.event_matches?(
             limit_invalidation,
             scope(),
             mission(),
             overlay_document,
             runtime_context()
           )

    refute RuntimeInvalidationRelevance.event_matches?(
             event_invalidation,
             scope(),
             mission(),
             plain_document,
             runtime_context()
           )

    refute RuntimeInvalidationRelevance.event_matches?(
             limit_invalidation,
             scope(),
             mission(),
             plain_document,
             runtime_context()
           )
  end

  test "refresh policy suppresses stale context events and non-live boundaries" do
    stale_event =
      invalidation(:source_watermark_changed,
        occurred_at: DateTime.from_unix!(1_700_000_000, :second)
      )

    fresh_event =
      invalidation(:source_watermark_changed,
        occurred_at: DateTime.from_unix!(1_700_000_020, :second)
      )

    context =
      runtime_context(%{
        context_since: DateTime.from_unix!(1_700_000_010, :second),
        time_mode: "live"
      })

    refute RuntimeInvalidationRelevance.refresh_allowed?(stale_event, context)
    assert RuntimeInvalidationRelevance.refresh_allowed?(fresh_event, context)

    assert %{allowed?: false, reason: :stale_for_context} =
             RuntimeInvalidationRelevance.refresh_relevance(stale_event, context)

    assert %{allowed?: true, reason: :allowed} =
             RuntimeInvalidationRelevance.refresh_relevance(fresh_event, context)

    refute RuntimeInvalidationRelevance.refresh_allowed?(
             invalidation(:historical_data_changed),
             context
           )

    assert %{allowed?: false, reason: :non_live_boundary} =
             RuntimeInvalidationRelevance.refresh_relevance(
               invalidation(:historical_data_changed),
               context
             )
  end

  test "refresh policy allows live dashboard version changes" do
    context =
      runtime_context(%{
        context_since: DateTime.from_unix!(1_700_000_010, :second),
        time_mode: "live"
      })

    event =
      invalidation(:dashboard_version_changed,
        dashboard_id: "dashboard-1",
        document_version: 2,
        lifecycle_action: :published,
        occurred_at: DateTime.from_unix!(1_700_000_020, :second)
      )

    assert RuntimeInvalidationRelevance.refresh_allowed?(event, context)

    assert RuntimeInvalidationRelevance.event_matches?(
             event,
             scope(),
             mission(),
             telemetry_document(),
             context
           )
  end

  test "refresh policy allows live telemetry revision state changes" do
    context =
      runtime_context(%{
        context_since: DateTime.from_unix!(1_700_000_010, :second),
        time_mode: "live"
      })

    event =
      invalidation(:telemetry_revision_state_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        observation_identity_id: "obs-1",
        occurred_at: DateTime.from_unix!(1_700_000_020, :second)
      )

    assert RuntimeInvalidationRelevance.refresh_allowed?(event, context)

    assert RuntimeInvalidationRelevance.event_matches?(
             event,
             scope(),
             mission(),
             telemetry_document(),
             context
           )

    assert "refresh_source_result" =
             event
             |> RuntimeInvalidationRelevance.notice()
             |> RuntimeInvalidationRelevance.notice_refresh_action()
  end

  test "live refresh decisions cover dashboard runtime domain boundaries" do
    context =
      runtime_context(%{
        context_since: DateTime.from_unix!(1_700_000_010, :second),
        time_mode: "live"
      })

    matrix = [
      {
        :catalog_revision_changed,
        telemetry_document(),
        [logical_source: :telemetry, observable: "HK.counter"],
        "refresh_plan"
      },
      {
        :limit_definition_changed,
        telemetry_document(overlays: [:limits]),
        [logical_source: :limits, observable: "HK.counter"],
        "refresh_source_result"
      },
      {
        :data_source_binding_changed,
        telemetry_document(),
        [logical_source: :telemetry, observable: "HK.counter", data_source_id: "new-source"],
        "refresh_plan"
      },
      {
        :source_watermark_changed,
        telemetry_document(),
        [
          logical_source: :telemetry,
          observable: "HK.counter",
          data_source_id: "flight-source",
          source_binding_id: "flight-binding"
        ],
        "refresh_source_result"
      },
      {
        :source_health_changed,
        telemetry_document(),
        [
          logical_source: :telemetry,
          observable: "HK.counter",
          data_source_id: "flight-source",
          source_binding_id: "flight-binding",
          source_health: :healthy
        ],
        "refresh_source_result"
      },
      {
        :source_health_changed,
        telemetry_document(),
        [
          logical_source: :telemetry,
          observable: "HK.counter",
          data_source_id: "flight-source",
          source_binding_id: "flight-binding",
          source_health: :degraded
        ],
        "wait_for_source_health"
      },
      {
        :events_changed,
        telemetry_document(overlays: [:events]),
        [logical_source: :events],
        "refresh_source_result"
      }
    ]

    for {boundary, document, filters, refresh_action} <- matrix do
      event =
        boundary
        |> invalidation(filters ++ [occurred_at: DateTime.from_unix!(1_700_000_020, :second)])

      assert RuntimeInvalidationRelevance.event_matches?(
               event,
               scope(),
               mission(),
               document,
               context
             )

      assert %{matches?: true, reason: :matched} =
               RuntimeInvalidationRelevance.event_relevance(
                 event,
                 scope(),
                 mission(),
                 document,
                 context
               )

      assert %{allowed?: true, reason: :allowed} =
               RuntimeInvalidationRelevance.refresh_relevance(event, context)

      assert refresh_action ==
               event
               |> RuntimeInvalidationRelevance.notice()
               |> RuntimeInvalidationRelevance.notice_refresh_action()
    end
  end

  test "affected placements identify primary, overlay, and broad dashboard impact" do
    document = impact_document()

    telemetry_event =
      invalidation(:source_watermark_changed,
        logical_source: :telemetry,
        observable: "HK.counter"
      )

    assert [
             %{
               placement_id: "placement-counter",
               widget_type_id: "cadence.value_tile",
               logical_source: :telemetry,
               impact_reason: :primary_source
             }
           ] = RuntimeInvalidationRelevance.affected_placements(telemetry_event, document)

    limits_event =
      invalidation(:limit_definition_changed,
        logical_source: :limits,
        observable: "HK.counter"
      )

    assert [
             %{placement_id: "placement-counter", impact_reason: :overlay},
             %{placement_id: "placement-state-timeline", impact_reason: :primary_source}
           ] = RuntimeInvalidationRelevance.affected_placements(limits_event, document)

    events_event = invalidation(:events_changed, logical_source: :events)

    assert [
             %{placement_id: "placement-counter", impact_reason: :overlay},
             %{placement_id: "placement-event-timeline", impact_reason: :primary_source}
           ] = RuntimeInvalidationRelevance.affected_placements(events_event, document)

    operational_event =
      invalidation(:source_watermark_changed,
        logical_source: :operational_observables,
        observable: "contacts.phase"
      )

    assert [
             %{
               placement_id: "placement-contact-phase",
               impact_reason: :primary_source,
               logical_source: :operational_observables
             }
           ] = RuntimeInvalidationRelevance.affected_placements(operational_event, document)

    broad_event = invalidation(:catalog_revision_changed)
    broad_impacts = RuntimeInvalidationRelevance.affected_placements(broad_event, document)

    assert RuntimeInvalidationRelevance.affected_placement_summary(broad_impacts) == %{
             count: 6,
             placement_ids: [
               "placement-counter",
               "placement-voltage",
               "placement-state-timeline",
               "placement-event-timeline",
               "placement-contact-phase",
               "placement-constellation"
             ],
             widget_type_ids: [
               "cadence.value_tile",
               "cadence.time_series",
               "cadence.state_timeline",
               "cadence.event_timeline",
               "cadence.status_matrix",
               "cadence.constellation_health"
             ],
             impact_reasons: [:catalog_revision]
           }
  end

  test "archive refresh policy follows historical data overlap" do
    context =
      runtime_context(%{
        time_mode: "archive",
        time_context: %{
          "axis" => "generation_time",
          "from" => "2026-06-21T10:00:00Z",
          "to" => "2026-06-21T10:10:00Z"
        }
      })

    overlapping =
      invalidation(:historical_data_changed,
        time_range: %{
          axis: :generation_time,
          from: "2026-06-21T10:05:00Z",
          to: "2026-06-21T10:15:00Z"
        }
      )

    non_overlapping =
      invalidation(:historical_data_changed,
        time_range: %{
          axis: :generation_time,
          from: "2026-06-21T10:11:00Z",
          to: "2026-06-21T10:15:00Z"
        }
      )

    wrong_axis =
      invalidation(:historical_data_changed,
        time_range: %{
          axis: :receipt_time,
          from: "2026-06-21T10:05:00Z",
          to: "2026-06-21T10:15:00Z"
        }
      )

    assert RuntimeInvalidationRelevance.refresh_allowed?(overlapping, context)
    refute RuntimeInvalidationRelevance.refresh_allowed?(non_overlapping, context)
    assert RuntimeInvalidationRelevance.refresh_allowed?(wrong_axis, context)

    assert %{allowed?: true, reason: :allowed} =
             RuntimeInvalidationRelevance.refresh_relevance(overlapping, context)

    assert %{allowed?: false, reason: :snapshot_time_mismatch} =
             RuntimeInvalidationRelevance.refresh_relevance(non_overlapping, context)
  end

  test "replay invalidations match only the active replay run when scoped" do
    document = telemetry_document()

    context =
      runtime_context(%{
        time_mode: "replay_run",
        replay_run_id: "replay-run-1",
        time_context: %{
          "mode" => "replay_run",
          "axis" => "generation_time",
          "replay_run_id" => "replay-run-1"
        }
      })

    matching =
      invalidation(:historical_data_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        replay_run_id: "replay-run-1"
      )

    wrong_replay =
      invalidation(:historical_data_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        replay_run_id: "replay-run-2"
      )

    unscoped =
      invalidation(:historical_data_changed,
        logical_source: :telemetry,
        observable: "HK.counter"
      )

    live_context = runtime_context(%{time_mode: "live", replay_run_id: nil})

    assert RuntimeInvalidationRelevance.event_matches?(
             matching,
             scope(),
             mission(),
             document,
             context
           )

    assert %{matches?: true, context_matches?: true, reason: :matched} =
             RuntimeInvalidationRelevance.event_relevance(
               matching,
               scope(),
               mission(),
               document,
               context
             )

    refute RuntimeInvalidationRelevance.event_matches?(
             wrong_replay,
             scope(),
             mission(),
             document,
             context
           )

    assert %{matches?: false, context_matches?: false, reason: :replay_run_mismatch} =
             RuntimeInvalidationRelevance.event_relevance(
               wrong_replay,
               scope(),
               mission(),
               document,
               context
             )

    assert RuntimeInvalidationRelevance.event_matches?(
             unscoped,
             scope(),
             mission(),
             document,
             context
           )

    refute RuntimeInvalidationRelevance.event_matches?(
             matching,
             scope(),
             mission(),
             document,
             live_context
           )

    assert %{matches?: false, reason: :replay_run_mismatch} =
             RuntimeInvalidationRelevance.event_relevance(
               matching,
               scope(),
               mission(),
               document,
               live_context
             )
  end

  test "source watermark replay invalidations match atom-keyed runtime context only for active replay run" do
    document = telemetry_document()

    context =
      runtime_context(%{
        data_realm: :replay,
        data_context: %{replay_run_id: "replay-run-1"},
        time_context: %{mode: :replay_run, axis: :generation_time, replay_run_id: "replay-run-1"},
        time_mode: "replay_run"
      })

    matching =
      invalidation(:source_watermark_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        data_source_id: "flight-source",
        source_binding_id: "flight-binding",
        realm: :replay,
        replay_run_id: "replay-run-1"
      )

    wrong_replay =
      invalidation(:source_watermark_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        data_source_id: "flight-source",
        source_binding_id: "flight-binding",
        realm: :replay,
        replay_run_id: "replay-run-2"
      )

    assert RuntimeInvalidationRelevance.event_matches?(
             matching,
             scope(),
             mission(),
             document,
             context
           )

    assert %{matches?: false, context_matches?: false, reason: :replay_run_mismatch} =
             RuntimeInvalidationRelevance.event_relevance(
               wrong_replay,
               scope(),
               mission(),
               document,
               context
             )
  end

  test "source health replay invalidations match atom-keyed runtime context only for active replay run" do
    document = telemetry_document()

    context =
      runtime_context(%{
        data_realm: :replay,
        time_context: %{mode: :replay_run, axis: :generation_time, replay_run_id: "health-run-1"},
        time_mode: "replay_run"
      })

    matching =
      invalidation(:source_health_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        data_source_id: "flight-source",
        source_binding_id: "flight-binding",
        realm: :replay,
        replay_run_id: "health-run-1",
        source_health: :degraded
      )

    wrong_replay =
      invalidation(:source_health_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        data_source_id: "flight-source",
        source_binding_id: "flight-binding",
        realm: :replay,
        replay_run_id: "health-run-2",
        source_health: :healthy
      )

    assert RuntimeInvalidationRelevance.event_matches?(
             matching,
             scope(),
             mission(),
             document,
             context
           )

    assert %{matches?: false, context_matches?: false, reason: :replay_run_mismatch} =
             RuntimeInvalidationRelevance.event_relevance(
               wrong_replay,
               scope(),
               mission(),
               document,
               context
             )
  end

  test "summarizes recent dashboard invalidation events" do
    document = telemetry_document()

    events = [
      recent_event(:source_watermark_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        measurements: %{total: 2}
      ),
      recent_event(:source_watermark_changed,
        logical_source: :telemetry,
        observable: "HK.voltage",
        measurements: %{total: 9}
      ),
      recent_event(:source_health_changed,
        logical_source: :telemetry,
        observable: "HK.counter",
        measurements: %{"total" => 1}
      ),
      %{source: :other, metadata: %{}}
    ]

    summary =
      RuntimeInvalidationRelevance.summarize_recent_events(events, scope(), mission(), document)

    assert summary.event_count == 2
    assert summary.artifact_count == 3
    assert summary.boundaries == %{source_health_changed: 1, source_watermark_changed: 1}

    assert RuntimeInvalidationRelevance.boundary_summary(summary) ==
             "source_health_changed:1 source_watermark_changed:1"
  end

  test "treats PubSub events and runtime health telemetry events consistently" do
    document = telemetry_document()
    context = runtime_context()
    occurred_at = DateTime.from_unix!(1_700_000_500, :second)

    pubsub_event =
      Event.new(
        :source_watermark_changed,
        [:source_result, :frame],
        %{
          organization_id: "org-1",
          mission_id: "mission-1",
          logical_source: :telemetry,
          observable: "HK.counter",
          data_source_id: "flight-source"
        },
        %{},
        %{total: 1},
        occurred_at: occurred_at
      )

    runtime_health_event = %{
      source: :dashboards_runtime_invalidation,
      observed_at: occurred_at,
      metadata: Event.to_telemetry_metadata(pubsub_event, :runtime_cache),
      measurements: pubsub_event.measurements,
      runtime_event: pubsub_event
    }

    assert RuntimeInvalidationRelevance.event_matches?(
             pubsub_event,
             scope(),
             mission(),
             document,
             context
           )

    assert RuntimeInvalidationRelevance.recent_event_matches_dashboard?(
             runtime_health_event,
             scope(),
             mission(),
             document
           )

    assert RuntimeInvalidationRelevance.summarize_recent_events(
             [runtime_health_event],
             scope(),
             mission(),
             document
           ) == %{event_count: 1, artifact_count: 1, boundaries: %{source_watermark_changed: 1}}
  end

  test "builds operator notice values" do
    event = invalidation(:events_changed, measurements: %{total: 4})

    notice = RuntimeInvalidationRelevance.notice(event)

    assert notice.boundary == :events_changed
    assert notice.invalidated_artifacts == 4
    assert RuntimeInvalidationRelevance.notice_boundary(notice) == "events_changed"
    assert RuntimeInvalidationRelevance.notice_refresh_reason(notice) == "runtime_invalidation"
    assert RuntimeInvalidationRelevance.notice_refresh_action(notice) == "refresh_source_result"
    assert RuntimeInvalidationRelevance.remounts_charts?(event)
  end

  test "builds refresh action taxonomy from invalidation boundaries and source health" do
    assert "refresh_plan" =
             :dashboard_version_changed
             |> invalidation()
             |> RuntimeInvalidationRelevance.notice()
             |> RuntimeInvalidationRelevance.notice_refresh_action()

    assert "refresh_source_result" =
             :source_watermark_changed
             |> invalidation()
             |> RuntimeInvalidationRelevance.notice()
             |> RuntimeInvalidationRelevance.notice_refresh_action()

    assert "wait_for_source_health" =
             :source_health_changed
             |> invalidation(source_health: :degraded)
             |> RuntimeInvalidationRelevance.notice()
             |> RuntimeInvalidationRelevance.notice_refresh_action()

    assert "refresh_source_result" =
             :source_health_changed
             |> invalidation(source_health: :healthy)
             |> RuntimeInvalidationRelevance.notice()
             |> RuntimeInvalidationRelevance.notice_refresh_action()
  end

  defp scope, do: %{organization_id: "org-1"}
  defp mission, do: %{mission_id: "mission-1"}

  defp telemetry_document(opts \\ []) do
    overlays = Keyword.get(opts, :overlays, [])

    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard",
      placements: [
        %Placement{
          placement_id: "placement-1",
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            title: "Counter",
            binding: %{observables: ["HK.counter"], overlays: overlays}
          }
        }
      ]
    }
  end

  defp non_telemetry_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Constellation Dashboard",
      placements: [
        %Placement{
          placement_id: "placement-constellation",
          widget_def: %WidgetDef{
            widget_type_id: "cadence.constellation_health",
            title: "Fleet",
            binding: %{source: :operational_observables}
          }
        }
      ]
    }
  end

  defp impact_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Impact Dashboard",
      placements: [
        impact_placement(
          "placement-counter",
          "cadence.value_tile",
          %{source: :telemetry, observables: ["HK.counter"], overlays: [:limits, :events]}
        ),
        impact_placement(
          "placement-voltage",
          "cadence.time_series",
          %{source: :telemetry, observables: ["HK.voltage"]}
        ),
        impact_placement(
          "placement-state-timeline",
          "cadence.state_timeline",
          %{source: :limits, observables: ["HK.counter"]}
        ),
        impact_placement(
          "placement-event-timeline",
          "cadence.event_timeline",
          %{source: :events}
        ),
        impact_placement(
          "placement-contact-phase",
          "cadence.status_matrix",
          %{source: :operational_observables, observables: ["contacts.phase"]}
        ),
        impact_placement(
          "placement-constellation",
          "cadence.constellation_health",
          %{source: :operational_observables}
        )
      ]
    }
  end

  defp impact_placement(placement_id, widget_type_id, binding) do
    %Placement{
      placement_id: placement_id,
      widget_def: %WidgetDef{
        widget_type_id: widget_type_id,
        title: placement_id,
        binding: binding
      }
    }
  end

  defp runtime_context(overrides \\ %{}) do
    Map.merge(
      %{
        data_realm: :flight,
        engine_result: %DashboardResolveResult{
          watermarks: [
            %SourceWatermark{
              data_source_id: "flight-source",
              source_binding_id: "flight-binding"
            }
          ]
        },
        time_context: %{"mode" => "live"},
        time_mode: "live",
        context_since: DateTime.from_unix!(1_700_000_000, :second),
        edit_mode?: false
      },
      overrides
    )
  end

  defp invalidation(boundary, attrs \\ []) do
    measurements = Keyword.get(attrs, :measurements, %{total: 0})
    occurred_at = Keyword.get(attrs, :occurred_at, DateTime.utc_now())

    filters =
      attrs
      |> Keyword.drop([:measurements, :occurred_at])
      |> Map.new()
      |> Map.put_new(:organization_id, "org-1")
      |> Map.put_new(:mission_id, "mission-1")

    %{
      boundary: boundary,
      filters: filters,
      measurements: measurements,
      occurred_at: occurred_at
    }
  end

  defp recent_event(boundary, attrs) do
    measurements = Keyword.get(attrs, :measurements, %{total: 0})

    %{
      source: :dashboards_runtime_invalidation,
      metadata: %{
        boundary: boundary,
        filters:
          attrs
          |> Keyword.drop([:measurements])
          |> Map.new()
          |> Map.put_new(:organization_id, "org-1")
          |> Map.put_new(:mission_id, "mission-1")
      },
      measurements: measurements
    }
  end

  defp cache_key(opts) do
    data_source_id = Keyword.fetch!(opts, :data_source_id)
    source_binding_id = Keyword.fetch!(opts, :source_binding_id)

    %RuntimeCacheKey{
      layer: :source_result,
      fingerprint: "fingerprint",
      parts: %{
        data_source: %{data_source_id: data_source_id},
        source_binding: %{binding_id: source_binding_id, data_source_id: data_source_id}
      }
    }
  end
end
