defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractEventTimelineTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSources,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem
  }

  alias Cadence.Jobs.Job
  alias Cadence.OperationalEvents.Event
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)
  @optional_link_context_paths [
    logical_source: [:logical_source],
    scope_kind: [:scope, :primary, :kind],
    time_mode: [:time, :mode],
    time_axis: [:time, :axis],
    realm: [:data, :realm],
    data_source_id: [:data, :data_source_id],
    source_binding_id: [:data, :source_binding_id],
    source_request_id: [:source_request_id]
  ]

  test "golden event timeline fixture resolves telemetry backfill lifecycle evidence" do
    document = load_fixture!("event_timeline_backfill_lifecycle.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request = resolve_request(document, %{"placement_event_timeline" => %{width_px: 720}})
    plan = Engine.plan(request, event_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    [event_request] = plan.planned_source_requests

    assert %{
             logical_source: :events,
             observables: [],
             sampling_mode: :event_history,
             products: [
               :contact_intervals,
               :mission_timeline,
               :source_health_transitions,
               :source_watermark_events,
               :source_capability_postures,
               :telemetry_backfill_lifecycle,
               :telemetry_revision_decisions
             ],
             overlays: [],
             target_points: 720,
             time_axis: :occurred_at,
             data_source_id: "managed_events_projection",
             source_binding_id: "default_flight_events"
           } = request_summary(event_request)

    assert Map.fetch!(event_request.sampling, :families) == [
             :contacts,
             :mission_timeline,
             :source_health,
             :source_watermarks,
             :source_capabilities,
             :telemetry_backfills,
             :telemetry_revisions
           ]

    result =
      Engine.resolve(
        request,
        event_source_registry_opts(
          validate_dashboard_contract?: true,
          source_result_cache?: false,
          source_opts: event_timeline_source_opts(parent)
        )
      )

    assert_received {:backfill_lifecycle_events_called, "org_dashboards", "mission_dashboards",
                     backfill_opts}

    assert Keyword.fetch!(backfill_opts, :realm) == "flight"
    assert Keyword.fetch!(backfill_opts, :spacecraft_id) == "sc_001"
    assert Keyword.fetch!(backfill_opts, :limit) == 500
    assert Keyword.fetch!(backfill_opts, :order) == :asc

    assert_received {:source_capability_posture_events_called, "org_dashboards",
                     "mission_dashboards", source_capability_opts}

    assert Keyword.fetch!(source_capability_opts, :limit) == 500
    assert Keyword.fetch!(source_capability_opts, :order) == :asc

    assert_received {:backfill_workflow_job_called, "backfill-run-golden-started"}

    assert result.dashboard_warnings == []
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 7

    assert %{
             "placement_event_timeline" =>
               %PlacementFrames{
                 primary: primary_frames,
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert Enum.map(primary_frames, & &1.meta.product) == [
             :contact_intervals,
             :mission_timeline,
             :source_health_transitions,
             :source_watermark_events,
             :source_capability_postures,
             :telemetry_backfill_lifecycle,
             :telemetry_revision_decisions
           ]

    source_capability_frame =
      Enum.find(primary_frames, &(&1.meta.product == :source_capability_postures))

    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} =
             source_capability_frame

    assert source_capability_frame.meta.family == :source_capability
    assert source_capability_frame.meta.source_binding_id == "default_flight_events"
    assert source_capability_frame.meta.data_source_id == "managed_events_projection"
    assert source_capability_frame.meta.returned_events == 1

    assert link_targets(source_capability_frame) == [:operational_event]

    assert_link_runtime_context(
      link_by_target(
        source_capability_frame,
        :operational_event,
        "operational_event:source_capability_posture:dashboard-golden:resolve-golden:events-request-1"
      ),
      logical_source: "events",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "occurred_at",
      realm: "flight",
      data_source_id: "managed_events_projection",
      source_binding_id: "default_flight_events",
      source_request_id: source_capability_frame.meta.source_request_id
    )

    backfill_frame =
      Enum.find(primary_frames, &(&1.meta.product == :telemetry_backfill_lifecycle))

    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} = backfill_frame
    assert backfill_frame.meta.family == :telemetry_backfill
    assert backfill_frame.meta.source_binding_id == "default_flight_events"
    assert backfill_frame.meta.data_source_id == "managed_events_projection"
    assert backfill_frame.meta.returned_events == 1

    assert link_targets(backfill_frame) == [
             :telemetry_backfill_lifecycle_event,
             :operational_event
           ]

    assert_link_runtime_context(
      link_by_target(
        backfill_frame,
        :telemetry_backfill_lifecycle_event,
        "backfill-event-golden-started-dispatch-failed"
      ),
      logical_source: "events",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "occurred_at",
      realm: "flight",
      data_source_id: "managed_events_projection",
      source_binding_id: "default_flight_events",
      source_request_id: backfill_frame.meta.source_request_id
    )

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :event_timeline,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             rows: [
               %{
                 category: :telemetry_backfill,
                 kind: :backfill_started,
                 severity: :info,
                 source_record_id: "backfill-event-golden-started-dispatch-failed",
                 backfill_run_id: "backfill-run-golden-started",
                 workflow_run_id: "backfill-run-golden-started",
                 workflow_job_id: "job-golden-started",
                 workflow_job_status: :failed,
                 workflow_job_failure: :source_window_failed,
                 target: :telemetry_backfill_lifecycle_event,
                 data_management: %{
                   badges: [
                     %{
                       kind: :historical_workflow,
                       value: "backfill_started_dispatch_degraded",
                       label: "Backfill dispatch failed",
                       status: :warning,
                       code: "backfill_started_dispatch_degraded",
                       data_link_target: :telemetry_backfill_lifecycle_event,
                       data_link_id: "backfill-event-golden-started-dispatch-failed",
                       workflow_job_id: "job-golden-started",
                       workflow_job_status: "failed",
                       workflow_job_failure: "source_window_failed"
                     }
                   ]
                 }
               },
               %{
                 category: :source_capability,
                 kind: :source_capability_fallback,
                 severity: :warning,
                 source_record_id: "dashboard-golden:resolve-golden:events-request-1",
                 target: :operational_event,
                 target_id:
                   "operational_event:source_capability_posture:dashboard-golden:resolve-golden:events-request-1",
                 logical_source: :events,
                 data_source_id: "managed_events_projection",
                 source_binding_id: "default_flight_events",
                 realm: :flight,
                 dataset: "mission_events",
                 capability_status: :fallback,
                 requested_time_axis: :generation_time,
                 executed_time_axis: :occurred_at,
                 source_execution_status: :resolved,
                 source_execution_cache_status: :miss
               }
             ]
           } = data

    source_capability_row =
      Enum.find(data.rows, &(&1.category == :source_capability))

    assert Enum.any?(
             source_capability_row.links,
             &(&1.target == :operational_event and
                 &1.target_id ==
                   "operational_event:source_capability_posture:dashboard-golden:resolve-golden:events-request-1")
           )

    assert data.data_management.badges == [
             hd(hd(data.rows).data_management.badges)
           ]
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
    |> Document.from_map()
  end

  defp resolve_request(%Document{} = document, placement_sizes) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{placement_sizes: placement_sizes}
    }
  end

  defp event_source_registry_opts(opts) do
    Keyword.merge(
      [
        data_sources: [
          DataSources.default_events_data_source()
        ],
        data_bindings: [
          DataSources.default_flight_events_binding()
        ]
      ],
      opts
    )
  end

  defp event_timeline_source_opts(parent) do
    %{
      events: [
        scheduled_contacts_fun: &empty_event_rows/3,
        realized_contacts_fun: &empty_event_rows/3,
        mission_events_fun: &empty_event_rows/3,
        source_health_events_fun: &empty_event_rows/3,
        source_watermark_events_fun: &empty_event_rows/3,
        source_capability_posture_events_fun: fn organization_id, mission_id, opts ->
          send(
            parent,
            {:source_capability_posture_events_called, organization_id, mission_id, opts}
          )

          [
            Event.from_source_capability_posture(%{
              organization_id: organization_id,
              mission_id: mission_id,
              source_capability_posture_id: "dashboard-golden:resolve-golden:events-request-1",
              dashboard_id: "dashboard-golden",
              dashboard_version: 7,
              resolve_id: "resolve-golden",
              source_request_id: "events-request-1",
              logical_source: :events,
              data_source_id: "managed_events_projection",
              source_binding_id: "default_flight_events",
              realm: :flight,
              dataset: "mission_events",
              status: :fallback,
              requested_sampling: :event_history,
              supported_sampling: [:event_history],
              requested_products: [:source_capability_postures],
              supported_products: [:source_capability_postures],
              requested_time_axis: :generation_time,
              executed_time_axis: :occurred_at,
              supported_time_axes: [:occurred_at],
              fallbacks: [:occurred_at_axis],
              unsupported: [:generation_time_axis],
              source_execution_status: :resolved,
              source_execution_cache_status: :miss,
              source_execution_operator_action: :inspect_source_capability,
              source_execution_runtime_action: :use_occurred_at_axis,
              source_execution_warning_codes: [:unsupported_source_capability],
              observed_at: ~U[2026-06-17 12:01:00Z]
            })
          ]
        end,
        telemetry_backfill_lifecycle_events_fun: fn organization_id, mission_id, opts ->
          send(parent, {:backfill_lifecycle_events_called, organization_id, mission_id, opts})

          [
            BackfillLifecycleEvent.new(%{
              backfill_lifecycle_event_id: "backfill-event-golden-started-dispatch-failed",
              backfill_run_id: "backfill-run-golden-started",
              organization_id: organization_id,
              mission_id: mission_id,
              realm: :flight,
              data_source_id: "managed_questdb_primary",
              binding_id: "default_flight_telemetry",
              observable_id: "tlm.hk.battery_voltage",
              point_id: "tlm.hk.battery_voltage",
              spacecraft_id: "sc_001",
              event_type: :backfill_started,
              source_from: ~U[2026-06-17 11:00:00Z],
              source_to: ~U[2026-06-17 11:30:00Z],
              receipt_from: ~U[2026-06-17 11:00:00Z],
              receipt_to: ~U[2026-06-17 11:30:00Z],
              sample_count: 42,
              authority: :authoritative,
              reason: :operator_requested,
              actor_id: "user-golden-1",
              actor_kind: :user,
              occurred_at: ~U[2026-06-17 12:00:00Z],
              payload: %{
                "run_id" => "backfill-run-golden-started",
                "selected_sample_count" => 42,
                "projection_effect" => "latest_value_refresh",
                "write_validity_state" => "canonical",
                "record_current_values" => true,
                "refresh_latest_value" => true
              }
            })
          ]
        end,
        telemetry_backfill_workflow_job_fun: fn event ->
          send(parent, {:backfill_workflow_job_called, event.backfill_run_id})

          Job.new(%{
            job_id: "job-golden-started",
            mission_id: event.mission_id,
            job_type: :telemetry_historical_data_workflow,
            run_id: event.backfill_run_id,
            status: :failed,
            payload: %{"attrs" => %{"backfill_run_id" => event.backfill_run_id}},
            attempt_count: 1,
            failure_reason: :source_window_failed,
            started_at: ~U[2026-06-17 12:00:00Z],
            completed_at: ~U[2026-06-17 12:00:02Z]
          })
        end,
        telemetry_revision_decision_events_fun: &empty_event_rows/3
      ]
    }
  end

  defp empty_event_rows(_organization_id, _mission_id, _opts), do: []

  defp request_summary(request) do
    %{
      logical_source: request.logical_source,
      observables: request.observables,
      sampling_mode: request.sampling.mode,
      products: Map.get(request.sampling, :products, []),
      overlays: request.overlays,
      target_points: Map.get(request.sampling, :target_points),
      time_axis: request.time_context.axis,
      data_source_id: request.metadata.capability_provenance.data_source_id,
      source_binding_id: request.metadata.capability_provenance.binding_id
    }
  end

  defp link_targets(%Frame{meta: meta}) do
    meta
    |> Map.get(:links, [])
    |> Enum.map(& &1.target)
  end

  defp link_by_target(%Frame{meta: meta}, target, target_id) do
    Enum.find(
      Map.get(meta, :links, []),
      &(&1.target == target and &1.target_id == target_id)
    )
  end

  defp assert_link_runtime_context(link, opts) do
    refute is_nil(link)

    assert_context_texts(link, [
      {[:organization_id], "org_dashboards"},
      {[:mission_id], "mission_dashboards"}
    ])

    assert_context_texts(link, optional_context_texts(opts))

    assert context_value(link.context, [:scope, :primary, :ids]) == [
             Keyword.fetch!(opts, :scope_id)
           ]
  end

  defp optional_context_texts(opts) do
    for {key, path} <- @optional_link_context_paths,
        expected = Keyword.get(opts, key),
        not is_nil(expected),
        do: {path, expected}
  end

  defp assert_context_texts(link, expected_values) do
    Enum.each(expected_values, fn {path, expected} ->
      assert context_text(context_value(link.context, path)) == expected
    end)
  end

  defp context_value(context, path) when is_map(context) and is_list(path) do
    Enum.reduce(path, context, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key, Map.get(acc, Atom.to_string(key)))
        _other -> nil
      end
    end)
  end

  defp context_text(nil), do: nil
  defp context_text(value) when is_atom(value), do: Atom.to_string(value)
  defp context_text(value) when is_binary(value), do: value
  defp context_text(value) when is_integer(value), do: Integer.to_string(value)
end
