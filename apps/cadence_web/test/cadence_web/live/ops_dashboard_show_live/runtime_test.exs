defmodule CadenceWeb.OpsDashboardShowLive.RuntimeTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DataLink,
    Field,
    Frame,
    PlacementFrames,
    RenderItem,
    RenderWidget,
    RuntimeCoordinator
  }

  alias CadenceWeb.OpsDashboardShowLive
  alias CadenceWeb.OpsDashboardShowLive.Runtime
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesWidgetMarkers

  test "accepted active resolve applies the engine result and cleans pending runtime state" do
    result = engine_result(:context_change, "placement-new")

    socket =
      socket(
        coordinator:
          RuntimeCoordinator.new(
            status: :resolving,
            generation: 2,
            active_resolve_id: 2,
            active_mode: :context_change
          ),
        pending_appends: %{1 => %{previous: true}, 2 => %{current: true}},
        pending_chart_remounts: %{2 => true, 3 => true}
      )

    socket = Runtime.resolve_finished(socket, 2, result)

    assert socket.assigns.dashboard_engine_result == result
    assert socket.assigns.dashboard_engine_frames_by_placement == result.frames_by_placement
    assert socket.assigns.dashboard_runtime_resolved?
    assert socket.assigns.chart_epoch == 1
    assert socket.assigns.dashboard_runtime_pending_appends == %{1 => %{previous: true}}
    assert socket.assigns.dashboard_runtime_pending_chart_remounts == %{3 => true}
    assert socket.assigns.dashboard_runtime_coordinator.status == :idle
    assert [%{action: :accept_result, resolve_id: 2}] = socket.assigns.dashboard_runtime_decisions
  end

  test "stale resolve success is ignored and only its pending runtime state is cleaned" do
    previous_result = engine_result(:initial, "placement-old")
    stale_result = engine_result(:context_change, "placement-stale")

    socket =
      socket(
        coordinator:
          RuntimeCoordinator.new(
            status: :resolving,
            generation: 2,
            active_resolve_id: 2,
            active_mode: :context_change
          ),
        resolved?: true,
        chart_epoch: 4,
        engine_result: previous_result,
        pending_appends: %{1 => %{stale: true}, 2 => %{active: true}},
        pending_chart_remounts: %{1 => true, 2 => true}
      )

    socket = Runtime.resolve_finished(socket, 1, stale_result)

    assert socket.assigns.dashboard_engine_result == previous_result

    assert socket.assigns.dashboard_engine_frames_by_placement ==
             previous_result.frames_by_placement

    assert socket.assigns.dashboard_runtime_resolved?
    assert socket.assigns.chart_epoch == 4
    assert socket.assigns.dashboard_runtime_pending_appends == %{2 => %{active: true}}
    assert socket.assigns.dashboard_runtime_pending_chart_remounts == %{2 => true}
    assert socket.assigns.dashboard_runtime_coordinator.active_resolve_id == 2

    assert [
             %{action: :ignore_result, resolve_id: 1, reason: :obsolete_resolve}
           ] = socket.assigns.dashboard_runtime_decisions
  end

  test "accepted live tick resolve pushes marker-only appends from pending marker snapshots" do
    widget = %RenderWidget{type: :time_series}
    previous_frames = marker_append_frames(events: [])
    current_frames = marker_append_frames()

    socket =
      socket(
        coordinator:
          RuntimeCoordinator.new(
            status: :resolving,
            generation: 7,
            active_resolve_id: 7,
            active_mode: :live_tick
          ),
        resolved?: true,
        render_items: [%RenderItem{placement_id: "placement-1", widget: widget}],
        pending_appends: %{
          7 => %{
            previous_data: %{"placement-1" => %{sample: %{sample_id: "sample-1"}}},
            previous_markers: %{
              "placement-1" => TimeSeriesWidgetMarkers.snapshot(previous_frames, widget)
            }
          }
        }
      )

    socket =
      Runtime.resolve_finished(socket, 7, %{
        resolve_mode: :live_tick,
        frames_by_placement: %{"placement-1" => current_frames}
      })

    assert %{
             live_temp: %{
               push_events: [
                 [
                   "tlm:append",
                   %{
                     "series" => %{},
                     "markers" => %{
                       "placement-1" => %{
                         event_markers: [%{mission_event_id: "mission-event-1"}]
                       }
                     }
                   }
                 ]
               ]
             }
           } = socket.private

    assert socket.assigns.dashboard_runtime_pending_appends == %{}
  end

  test "active resolve failure records degradation and preserves the last accepted dashboard state" do
    previous_result = engine_result(:initial, "placement-old")

    socket =
      socket(
        coordinator:
          RuntimeCoordinator.new(
            status: :resolving,
            generation: 5,
            active_resolve_id: 5,
            active_mode: :live_tick
          ),
        resolved?: true,
        chart_epoch: 2,
        engine_result: previous_result,
        pending_appends: %{5 => %{previous: true}},
        pending_chart_remounts: %{5 => true}
      )

    socket = Runtime.resolve_failed(socket, 5, {:shutdown, :source_timeout})

    assert socket.assigns.dashboard_engine_result == previous_result
    assert socket.assigns.dashboard_runtime_resolved?
    assert socket.assigns.chart_epoch == 2
    assert socket.assigns.dashboard_runtime_pending_appends == %{}
    assert socket.assigns.dashboard_runtime_pending_chart_remounts == %{}
    assert socket.assigns.dashboard_runtime_coordinator.status == :idle

    assert [
             %{
               action: :record_degradation,
               resolve_id: 5,
               reason: :resolve_failed,
               details: %{
                 async_exit_reason: {:shutdown, :source_timeout},
                 finished_at: %DateTime{},
                 finished_monotonic_ms: finished_monotonic_ms
               }
             }
           ] = socket.assigns.dashboard_runtime_decisions

    assert is_integer(finished_monotonic_ms)
  end

  test "stale resolve failure is ignored and does not disturb active pending state" do
    previous_result = engine_result(:initial, "placement-old")

    socket =
      socket(
        coordinator:
          RuntimeCoordinator.new(
            status: :resolving,
            generation: 6,
            active_resolve_id: 6,
            active_mode: :context_change
          ),
        resolved?: true,
        engine_result: previous_result,
        pending_appends: %{4 => %{stale: true}, 6 => %{active: true}},
        pending_chart_remounts: %{4 => true, 6 => true}
      )

    socket = Runtime.resolve_failed(socket, 4, :obsolete_timeout)

    assert socket.assigns.dashboard_engine_result == previous_result
    assert socket.assigns.dashboard_runtime_resolved?
    assert socket.assigns.dashboard_runtime_pending_appends == %{6 => %{active: true}}
    assert socket.assigns.dashboard_runtime_pending_chart_remounts == %{6 => true}
    assert socket.assigns.dashboard_runtime_coordinator.active_resolve_id == 6
    assert [%{action: :ignore_result, resolve_id: 4}] = socket.assigns.dashboard_runtime_decisions
  end

  test "dashboard terminate cancels active resolves and pending tick timer" do
    test_pid = self()
    dashboard_resolve_pid = waiting_process()
    unrelated_pid = waiting_process()
    dashboard_ref = Process.monitor(dashboard_resolve_pid)
    unrelated_ref = Process.monitor(unrelated_pid)
    tick_timer_ref = Process.send_after(test_pid, :dashboard_tick_timer_fired, 10_000)

    socket =
      %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, dashboard_tick_timer_ref: tick_timer_ref},
        private: %{
          live_async: %{
            Runtime.async_name(42) => {make_ref(), dashboard_resolve_pid, :start},
            :other_async => {make_ref(), unrelated_pid, :start}
          }
        }
      }

    assert :ok = OpsDashboardShowLive.terminate(:normal, socket)

    assert_receive {:DOWN, ^dashboard_ref, :process, ^dashboard_resolve_pid,
                    {:shutdown, :dashboard_live_view_terminated}}

    refute_receive :dashboard_tick_timer_fired, 50
    refute_receive {:DOWN, ^unrelated_ref, :process, ^unrelated_pid, _reason}, 50

    Process.exit(unrelated_pid, :kill)
    assert_receive {:DOWN, ^unrelated_ref, :process, ^unrelated_pid, :killed}
  end

  defp socket(opts) do
    engine_result = Keyword.get(opts, :engine_result, engine_result(:initial, "placement-old"))

    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        chart_epoch: Keyword.get(opts, :chart_epoch, 0),
        dashboard_engine_result: engine_result,
        dashboard_engine_frames_by_placement: engine_result.frames_by_placement,
        dashboard_render_items: Keyword.get(opts, :render_items, []),
        dashboard_runtime_coordinator: Keyword.get(opts, :coordinator, RuntimeCoordinator.new()),
        dashboard_runtime_decisions: [],
        dashboard_runtime_pending_appends: Keyword.get(opts, :pending_appends, %{}),
        dashboard_runtime_pending_chart_remounts: Keyword.get(opts, :pending_chart_remounts, %{}),
        dashboard_runtime_resolved?: Keyword.get(opts, :resolved?, false),
        widget_data: %{}
      }
    }
  end

  defp engine_result(resolve_mode, placement_id) do
    %{
      resolve_mode: resolve_mode,
      frames_by_placement: %{placement_id => %PlacementFrames{}}
    }
  end

  defp marker_append_frames(opts \\ []) do
    %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :scalar,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "counter_value",
              kind: :number,
              values: [7],
              metadata: %{sample_ids: ["sample-1"]}
            }
          ]
        }
      ],
      overlays: %{
        events: Keyword.get(opts, :events, marker_append_event_frames())
      }
    }
  end

  defp marker_append_event_frames do
    [
      %Frame{
        source: :events,
        shape: :events,
        fields: [
          %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-17 12:05:00Z]]},
          %Field{name: "category", kind: :enum, values: [:mission_timeline]},
          %Field{name: "kind", kind: :enum, values: [:operator_note]},
          %Field{name: "severity", kind: :enum, values: [:info]},
          %Field{name: "title", kind: :string, values: ["AOS confirmed"]},
          %Field{name: "source_record_id", kind: :string, values: ["mission-event-1"]}
        ],
        meta: %{
          family: :mission_timeline,
          links: [
            %DataLink{
              link_id: "mission-event:mission-event-1",
              target: :mission_event,
              target_id: "mission-event-1",
              label: "Mission event"
            }
          ]
        }
      }
    ]
  end

  defp waiting_process do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end
end
