defmodule CadenceWeb.OpsDashboardShowLive.WidgetDataContractTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  test "engine-backed widgets expose stable no-data contracts" do
    placement_frames = %PlacementFrames{primary: []}

    for {widget_type, kind} <- [
          value_tile: :point,
          status_matrix: :status_matrix,
          data_table: :data_table,
          state_timeline: :state_timeline,
          event_timeline: :event_timeline,
          constellation_health: :constellation
        ] do
      data = WidgetPresentation.data(nil, placement_frames, render_widget(widget_type))

      assert %{
               kind: ^kind,
               lifecycle_state: :no_data,
               stale?: false,
               unresolved?: false,
               engine_backed?: true,
               source_status: %{state: :no_data, severity: :info, data_state: :no_data}
             } = data

      assert %{state: :no_data} = data.lifecycle
    end
  end

  test "time series exposes a stable chart backfill contract" do
    assert %{
             version: 1,
             series: [
               %{
                 id: "tlm.hk.battery_voltage",
                 observable_id: "tlm.hk.battery_voltage",
                 source: :telemetry,
                 frame_id: "frame-voltage-history",
                 time_axis: :receipt_time,
                 sampling: :decimated_envelope,
                 points: [[1_781_697_600_000, 12.25, %{sample_id: "sample-1"}]]
               }
             ]
           } =
             WidgetPresentation.backfill(
               nil,
               time_series_frames(),
               render_widget(:time_series)
             )
  end

  test "operational context time series zero-point frames preserve source status" do
    data =
      WidgetPresentation.data(
        nil,
        operational_time_series_no_data_frames(),
        %RenderWidget{
          type: :time_series,
          binding: %{source: :operational_observables, mode: :context}
        }
      )

    assert %{
             kind: :point,
             sample: nil,
             lifecycle_state: :no_data,
             unresolved?: false,
             engine_backed?: true,
             source_status: %{
               state: :no_data,
               data_state: :no_data,
               logical_sources: [:operational_observables],
               data_source_ids: ["managed_operational_observables_archive_no_data"],
               source_binding_ids: ["archive_operational_observables_no_data"],
               realms: [:flight],
               time_modes: [:archive],
               scope_kinds: [:link],
               scope_ids: ["link-alpha"],
               empty_reason: :scope_no_data
             }
           } = data
  end

  test "engine-backed widgets expose missing snapshots as degraded source status" do
    data =
      WidgetPresentation.data(
        nil,
        status_matrix_frames() |> with_frame_warning_codes([:missing_snapshot]),
        render_widget(:status_matrix)
      )

    assert %{
             kind: :status_matrix,
             lifecycle_state: :stale,
             stale?: true,
             unresolved?: false,
             engine_backed?: true,
             source_status: %{
               state: :unknown,
               severity: :warning,
               warning_codes: [:missing_snapshot],
               stale?: true
             }
           } = data

    assert %{state: :stale, severity: :warning, warning_codes: [:missing_snapshot]} =
             data.lifecycle
  end

  defp time_series_frames do
    %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-voltage-history",
          source: :telemetry,
          shape: :wide,
          time_axis: :receipt_time,
          scope: %{primary: %{kind: :spacecraft, ids: ["sc-alpha"]}},
          fields: [
            %Field{name: "bucket_start", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "tlm.hk.battery_voltage_value",
              kind: :number,
              values: [12.25],
              metadata: %{
                observable_id: "tlm.hk.battery_voltage",
                label: "Battery voltage",
                unit: "V",
                sample_ids: ["sample-1"],
                quality_states: [:good]
              }
            }
          ],
          meta: %{
            observable_id: "tlm.hk.battery_voltage",
            unit: "V",
            sampling: :decimated_envelope,
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight",
            links: []
          }
        }
      ]
    }
  end

  defp operational_time_series_no_data_frames do
    %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-link-snr-history",
          source: :operational_observables,
          shape: :wide,
          time_axis: :occurred_at,
          scope: %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}},
          fields: [
            %Field{
              name: "time",
              kind: :time,
              values: [],
              metadata: %{axis: :occurred_at}
            },
            %Field{
              name: "link.snr_db",
              kind: :number,
              values: [],
              metadata: %{
                observable_id: "link.snr_db",
                label: "RF SNR",
                unit: "dB",
                resource_id: "link-alpha",
                scope_kind: :link,
                link_id: "link-alpha"
              }
            }
          ],
          meta: %{
            source_request_id: "source-request-link-snr",
            source_request_context: %{
              source_request_id: "source-request-link-snr",
              logical_source: :operational_observables,
              data_source_id: "managed_operational_observables_archive_no_data",
              source_binding_id: "archive_operational_observables_no_data",
              realm: :flight,
              time_mode: :archive,
              scope_kind: :link,
              scope_ids: ["link-alpha"]
            },
            logical_source: :operational_observables,
            data_source_id: "managed_operational_observables_archive_no_data",
            source_binding_id: "archive_operational_observables_no_data",
            realm: :flight,
            time_mode: :archive,
            sampling: :raw_series,
            resource_id: "link-alpha",
            scope_kind: :link,
            link_id: "link-alpha",
            returned_points: 0,
            warning_codes: [],
            links: []
          }
        }
      ]
    }
  end

  defp status_matrix_frames do
    %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-contact-phase",
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{name: "observable_id", kind: :string, values: ["contacts.phase"]},
            %Field{name: "contact_id", kind: :string, values: ["contact-1"]},
            %Field{name: "contact_kind", kind: :enum, values: [:scheduled]},
            %Field{name: "phase", kind: :enum, values: [:active]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:fresh]},
            %Field{name: "age_ms", kind: :number, values: [300_000]}
          ],
          meta: %{
            observable_id: "contacts.phase",
            supported_capability: :contacts_phase,
            logical_source: :operational_observables,
            data_source_id: "managed_operational_observables",
            source_binding_id: "default_flight_operational_observables",
            links: [
              %DataLink{
                link_id: "contact:contact-1",
                target: :contact,
                target_id: "contact-1",
                label: "Contact"
              }
            ]
          }
        }
      ]
    }
  end

  defp render_widget(widget_type) do
    %RenderWidget{
      type: widget_type,
      binding: widget_binding(widget_type)
    }
  end

  defp widget_binding(widget_type) when widget_type in [:status_matrix, :data_table] do
    %{
      source: :operational_observables,
      mode: :context,
      point_id: "contacts.phase",
      point_ids: ["contacts.phase"]
    }
  end

  defp widget_binding(:event_timeline), do: %{source: :events, mode: :context}

  defp widget_binding(:constellation_health),
    do: %{source: :operational_observables, mode: :constellation}

  defp widget_binding(_widget_type), do: %{source: :telemetry, mode: :fixed}

  defp with_frame_warning_codes(
         %PlacementFrames{primary: [%Frame{} = first_frame | rest]} = frames,
         codes
       ) do
    warning_codes = List.wrap(codes)

    %{
      frames
      | primary: [
          %Frame{
            first_frame
            | meta: Map.put(first_frame.meta || %{}, :warning_codes, warning_codes)
          }
          | rest
        ]
    }
  end

  defp with_frame_warning_codes(%PlacementFrames{} = frames, _codes), do: frames
end
