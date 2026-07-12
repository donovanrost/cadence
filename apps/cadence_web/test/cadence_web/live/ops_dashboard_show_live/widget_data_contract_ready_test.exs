defmodule CadenceWeb.OpsDashboardShowLive.WidgetDataContractReadyTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @widget_contracts [
    {:value_tile, :point, :value_tile_frames},
    {:time_series, :point, :time_series_frames},
    {:status_matrix, :status_matrix, :status_matrix_frames},
    {:data_table, :data_table, :status_matrix_frames},
    {:state_timeline, :state_timeline, :state_timeline_frames},
    {:event_timeline, :event_timeline, :event_timeline_frames},
    {:constellation_health, :constellation, :constellation_frames}
  ]

  for {widget_type, kind, fixture_fun} <- @widget_contracts do
    test "#{widget_type} exposes stable ready widget-data contract" do
      data =
        WidgetPresentation.data(
          nil,
          apply(__MODULE__, unquote(fixture_fun), []),
          render_widget(unquote(widget_type))
        )

      assert_ready_contract(data, unquote(kind))
      assert_widget_payload_contract(unquote(widget_type), data)
    end
  end

  test "engine-backed widgets promote stale frame warnings into widget lifecycle" do
    for {widget_type, kind, fixture_fun} <- @widget_contracts do
      data =
        WidgetPresentation.data(
          nil,
          apply(__MODULE__, fixture_fun, []) |> with_frame_warning_codes([:stale_data]),
          render_widget(widget_type)
        )

      assert %{
               kind: ^kind,
               lifecycle_state: :stale,
               stale?: true,
               unresolved?: false,
               engine_backed?: true,
               source_status: %{
                 state: :stale,
                 severity: :warning,
                 warning_codes: [:stale_data],
                 stale?: true
               }
             } = data

      assert %{state: :stale, severity: :warning, warning_codes: [:stale_data]} =
               data.lifecycle
    end
  end

  def value_tile_frames do
    %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-voltage-latest",
          source: :telemetry,
          shape: :scalar,
          time_axis: :receipt_time,
          scope: %{primary: %{kind: :spacecraft, ids: ["sc-alpha"]}},
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "tlm.hk.battery_voltage",
              kind: :number,
              values: [12.25],
              metadata: %{
                observable_id: "tlm.hk.battery_voltage",
                unit: "V",
                sample_ids: ["sample-1"],
                quality_states: [:good],
                links: [telemetry_sample_link("sample-1")]
              }
            }
          ],
          meta: %{
            observable_id: "tlm.hk.battery_voltage",
            unit: "V",
            warning_codes: [],
            links: []
          }
        }
      ],
      overlays: %{
        limits: [
          %Frame{
            frame_id: "frame-limit-latest",
            source: :limits,
            shape: :scalar,
            fields: [
              %Field{name: "normalized_state", kind: :enum, values: [:green]},
              %Field{name: "limit_state", kind: :enum, values: [:green]},
              %Field{name: "violation", kind: :boolean, values: [false]}
            ],
            meta: %{limit_event_id: "limit-event-1", links: []}
          }
        ]
      }
    }
  end

  def time_series_frames do
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

  def status_matrix_frames do
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

  def state_timeline_frames do
    %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-limit-history",
          source: :limits,
          shape: :events,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "limit_event_id", kind: :string, values: ["limit-event-1"]},
            %Field{name: "sample_id", kind: :string, values: ["sample-1"]},
            %Field{name: "normalized_state", kind: :enum, values: [:green]},
            %Field{name: "limit_state", kind: :enum, values: [:green]},
            %Field{name: "violation", kind: :boolean, values: [false]}
          ],
          meta: %{observable_id: "tlm.hk.battery_voltage", links: []}
        }
      ]
    }
  end

  def event_timeline_frames do
    %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-mission-events",
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
    }
  end

  def constellation_frames do
    %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-constellation",
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "spacecraft_id",
              kind: :string,
              values: ["sc-alpha", "sc-beta"]
            },
            %Field{name: "worst_state", kind: :enum, values: [:green, :red]}
          ],
          meta: %{supported_capability: :constellation_health}
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

  defp assert_ready_contract(data, kind) do
    assert %{
             kind: ^kind,
             lifecycle_state: :ready,
             stale?: false,
             unresolved?: false,
             engine_backed?: true,
             source_status: %{state: :fresh, severity: :ok, data_state: :ready}
           } = data

    assert %{state: :ready, severity: :ok} = data.lifecycle
  end

  defp assert_widget_payload_contract(:value_tile, data) do
    assert %{
             sample: %{sample_id: "sample-1", engineering_value: 12.25},
             limit_event: %{limit_event_id: "limit-event-1"}
           } = data
  end

  defp assert_widget_payload_contract(:time_series, data) do
    assert %{sample: %{sample_id: "sample-1", engineering_value: 12.25}} = data
  end

  defp assert_widget_payload_contract(:status_matrix, data) do
    assert %{rows: [%{observable_id: "contacts.phase:contact-1"}], links: [%{target: :contact}]} =
             data
  end

  defp assert_widget_payload_contract(:data_table, data) do
    assert %{rows: [%{observable_id: "contacts.phase:contact-1"}], links: [%{target: :contact}]} =
             data
  end

  defp assert_widget_payload_contract(:state_timeline, data) do
    assert %{rows: [%{limit_event_id: "limit-event-1"}], lanes: [%{lane_key: _lane_key}]} = data
  end

  defp assert_widget_payload_contract(:event_timeline, data) do
    assert %{rows: [%{source_record_id: "mission-event-1"}], links: [%{target: :mission_event}]} =
             data
  end

  defp assert_widget_payload_contract(:constellation_health, data) do
    assert %{
             counts: %{green: 1, red: 1},
             spacecraft: [
               %{spacecraft_id: "sc-alpha", worst_state: :green},
               %{spacecraft_id: "sc-beta", worst_state: :red}
             ]
           } = data
  end

  defp telemetry_sample_link(sample_id) do
    %DataLink{
      link_id: "sample-link:#{sample_id}",
      target: :telemetry_sample,
      target_id: sample_id,
      label: "Telemetry sample"
    }
  end
end
