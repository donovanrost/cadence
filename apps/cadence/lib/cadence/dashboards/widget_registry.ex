defmodule Cadence.Dashboards.WidgetRegistry do
  @moduledoc """
  First-party dashboard widget registry.

  v0 keeps this compiled-in and explicit. User-authored widget grammar and
  external distribution come later.
  """

  alias Cadence.Dashboards.{RuntimeCacheKey, WidgetType}

  @type fetch_error :: :unknown_widget_type | :unsupported_widget_version

  @spec list_types() :: [WidgetType.t()]
  def list_types, do: Map.values(types())

  @spec version() :: binary()
  def version do
    "widget-registry:" <> RuntimeCacheKey.fingerprint(ordered_types())
  end

  @spec fetch_type(binary(), pos_integer() | :latest | nil) ::
          {:ok, WidgetType.t()} | {:error, fetch_error()}
  def fetch_type(widget_type_id, version \\ :latest) when is_binary(widget_type_id) do
    case Map.fetch(types(), widget_type_id) do
      {:ok, %WidgetType{} = type} ->
        if version in [:latest, nil, type.version] do
          {:ok, type}
        else
          {:error, :unsupported_widget_version}
        end

      :error ->
        {:error, :unknown_widget_type}
    end
  end

  @spec migrate_options(binary(), pos_integer(), map()) ::
          {:ok, pos_integer(), map()} | {:error, fetch_error()}
  def migrate_options(widget_type_id, from_version, options)
      when is_binary(widget_type_id) and is_integer(from_version) and is_map(options) do
    case fetch_type(widget_type_id, :latest) do
      {:ok, type} when from_version == type.version -> {:ok, type.version, options}
      {:ok, _type} -> {:error, :unsupported_widget_version}
      {:error, reason} -> {:error, reason}
    end
  end

  defp types do
    Map.new(
      [
        value_tile(),
        time_series(),
        status_matrix(),
        data_table(),
        state_timeline(),
        event_timeline(),
        constellation_health()
      ],
      fn type ->
        {type.widget_type_id, type}
      end
    )
  end

  defp ordered_types do
    types()
    |> Map.values()
    |> Enum.sort_by(&{&1.widget_type_id, &1.version})
  end

  defp value_tile do
    %WidgetType{
      widget_type_id: "cadence.value_tile",
      version: 1,
      name: "Value Tile",
      category: :telemetry,
      icon: "hero-square-2-stack",
      trust: :first_party,
      data_contract: %{
        frames: [
          %{
            role: :primary,
            source: :telemetry,
            accepted_shapes: [:scalar],
            temporal?: false,
            sampling: :latest,
            source_overrides: [
              %{
                source: :operational_observables,
                accepted_shapes: [:matrix],
                temporal?: false,
                sampling: :latest,
                products: [:transport_bitrate, :link_rf, :commanding, :runtime_ingress],
                observable_value_kinds: [:metric]
              }
            ]
          }
        ],
        overlays: [%{role: :limits, source: :limits, required?: false}],
        live_mode: :poll_latest
      },
      binding_schema: %{
        min_observables: 1,
        max_observables: 1,
        observable_kinds: [:metric],
        scope_modes: [:context, :override],
        data_modes: [:context, :override],
        value_types: [:engineering, :raw],
        sampling_modes: [:latest],
        allowed_overlays: [:limits, :quality]
      },
      options_schema: [
        %{key: "precision", type: :integer, default: 2, min: 0, max: 6},
        %{key: "show_unit", type: :boolean, default: true}
      ],
      layout_contract: %{min_w: 2, min_h: 2, preferred_w: 3, preferred_h: 2, resize: :both},
      drilldown_contract: %{
        primary_action: :explore,
        supported_targets: [:telemetry_point, :limit_event, :explore],
        selection_modes: [:placement, :field, :warning],
        preserve_context?: true
      },
      renderer: %{locus: :client_hook, hook: "DashboardValueTile"}
    }
  end

  defp time_series do
    %WidgetType{
      widget_type_id: "cadence.time_series",
      version: 1,
      name: "Time Series",
      category: :telemetry,
      icon: "hero-chart-line",
      trust: :first_party,
      data_contract: %{
        frames: [
          %{
            role: :primary,
            source: :telemetry,
            accepted_shapes: [:wide],
            temporal?: true,
            sampling: :decimated_envelope,
            source_overrides: [
              %{
                source: :operational_observables,
                accepted_shapes: [:wide],
                temporal?: true,
                sampling: :raw_series,
                products: [:transport_bitrate, :link_rf, :runtime_ingress],
                observable_value_kinds: [:metric]
              }
            ]
          }
        ],
        overlays: [
          %{role: :limits, source: :limits, required?: false},
          %{role: :events, source: :events, required?: false}
        ],
        live_mode: :poll_latest
      },
      binding_schema: %{
        min_observables: 1,
        max_observables: 8,
        observable_kinds: [:metric],
        scope_modes: [:context, :override, :repeat],
        data_modes: [:context, :override],
        value_types: [:engineering, :raw],
        sampling_modes: [:raw_series, :decimated_envelope],
        allowed_overlays: [:limits, :events, :quality]
      },
      options_schema: [
        %{key: "show_min_max_band", type: :boolean, default: true},
        %{key: "legend", type: :boolean, default: false}
      ],
      layout_contract: %{min_w: 4, min_h: 3, preferred_w: 6, preferred_h: 4, resize: :both},
      drilldown_contract: %{
        primary_action: :explore,
        supported_targets: [:telemetry_point, :limit_event, :mission_event, :explore],
        selection_modes: [:placement, :field, :timestamp, :event, :warning],
        preserve_context?: true
      },
      renderer: %{locus: :client_hook, hook: "DashboardTimeSeries"}
    }
  end

  defp status_matrix do
    %WidgetType{
      widget_type_id: "cadence.status_matrix",
      version: 1,
      name: "Status Matrix",
      category: :operations,
      icon: "hero-table-cells",
      trust: :first_party,
      data_contract: %{
        frames: [
          %{
            role: :primary,
            source: :telemetry,
            accepted_shapes: [:scalar, :matrix, :long],
            temporal?: false,
            sampling: :latest,
            source_overrides: [
              %{
                source: :operational_observables,
                accepted_shapes: [:matrix],
                temporal?: false,
                sampling: :latest,
                products: [
                  :contacts_phase,
                  :connection_state,
                  :ground_station,
                  :link_rf,
                  :transport_bitrate,
                  :commanding,
                  :runtime_ingress
                ],
                observable_value_kinds: [:metric, :state]
              }
            ]
          }
        ],
        overlays: [%{role: :limits, source: :limits, required?: false}],
        live_mode: :poll_latest
      },
      binding_schema: %{
        min_observables: 1,
        max_observables: 24,
        observable_kinds: [:metric, :state],
        scope_modes: [:context, :override, :repeat],
        data_modes: [:context, :override],
        value_types: [:engineering, :raw],
        sampling_modes: [:latest],
        allowed_overlays: [:limits, :quality]
      },
      options_schema: [],
      layout_contract: %{min_w: 4, min_h: 3, preferred_w: 6, preferred_h: 4, resize: :both},
      drilldown_contract: %{
        primary_action: :inspect,
        supported_targets: [:telemetry_point, :operational_observable, :explore],
        selection_modes: [:placement, :field, :warning],
        preserve_context?: true
      },
      renderer: %{locus: :client_hook, hook: "DashboardStatusMatrix"}
    }
  end

  defp data_table do
    %WidgetType{
      widget_type_id: "cadence.data_table",
      version: 1,
      name: "Data Table",
      category: :operations,
      icon: "hero-table-cells",
      trust: :first_party,
      data_contract: %{
        frames: [
          %{
            role: :primary,
            source: :telemetry,
            accepted_shapes: [:scalar, :matrix, :long],
            temporal?: false,
            sampling: :latest,
            source_overrides: [
              %{
                source: :operational_observables,
                accepted_shapes: [:matrix],
                temporal?: false,
                sampling: :latest,
                products: [
                  :contacts_phase,
                  :connection_state,
                  :ground_station,
                  :link_rf,
                  :transport_bitrate,
                  :commanding,
                  :runtime_ingress
                ],
                observable_value_kinds: [:metric, :state]
              }
            ]
          }
        ],
        overlays: [%{role: :limits, source: :limits, required?: false}],
        live_mode: :poll_latest
      },
      binding_schema: %{
        min_observables: 1,
        max_observables: 24,
        observable_kinds: [:metric, :state],
        scope_modes: [:context, :override, :repeat],
        data_modes: [:context, :override],
        value_types: [:engineering, :raw],
        sampling_modes: [:latest],
        allowed_overlays: [:limits, :quality]
      },
      options_schema: [
        %{key: "precision", type: :integer, default: 2, min: 0, max: 6}
      ],
      layout_contract: %{min_w: 4, min_h: 3, preferred_w: 6, preferred_h: 4, resize: :both},
      drilldown_contract: %{
        primary_action: :inspect,
        supported_targets: [:telemetry_point, :operational_observable, :explore],
        selection_modes: [:placement, :field, :warning],
        preserve_context?: true
      },
      renderer: %{locus: :server_component, component: "DataTable"}
    }
  end

  defp state_timeline do
    %WidgetType{
      widget_type_id: "cadence.state_timeline",
      version: 1,
      name: "State Timeline",
      category: :operations,
      icon: "hero-bars-3",
      trust: :first_party,
      data_contract: %{
        frames: [
          %{
            role: :primary,
            source: :limits,
            accepted_shapes: [:events, :scalar],
            temporal?: true,
            sampling: :event_history,
            products: [:event_history],
            source_overrides: [
              %{
                source: :operational_observables,
                accepted_shapes: [:events],
                temporal?: true,
                sampling: :event_history,
                products: [
                  :contacts_phase,
                  :connection_state,
                  :ground_station,
                  :link_rf,
                  :transport_execution_state
                ],
                observable_value_kinds: [:state]
              }
            ]
          }
        ],
        overlays: [],
        live_mode: :appendable
      },
      binding_schema: %{
        min_observables: 1,
        max_observables: 24,
        observable_kinds: [:metric, :state],
        scope_modes: [:context, :override],
        data_modes: [:context, :override],
        value_types: [:engineering, :raw],
        sampling_modes: [:event_history],
        allowed_overlays: [:quality]
      },
      options_schema: [],
      layout_contract: %{min_w: 4, min_h: 3, preferred_w: 6, preferred_h: 4, resize: :both},
      drilldown_contract: %{
        primary_action: :inspect,
        supported_targets: [
          :telemetry_point,
          :operational_observable,
          :telemetry_sample,
          :limit_event,
          :limit_definition,
          :contact,
          :explore
        ],
        selection_modes: [:placement, :field, :timestamp, :warning],
        preserve_context?: true
      },
      renderer: %{locus: :server_component, component: "StateTimeline"}
    }
  end

  defp event_timeline do
    %WidgetType{
      widget_type_id: "cadence.event_timeline",
      version: 1,
      name: "Event Timeline",
      category: :operations,
      icon: "hero-bars-3-bottom-left",
      trust: :first_party,
      data_contract: %{
        frames: [
          %{
            role: :primary,
            source: :events,
            accepted_shapes: [:events, :intervals],
            temporal?: true,
            sampling: :event_history,
            products: [
              :contact_intervals,
              :mission_timeline,
              :source_health_transitions,
              :source_watermark_events,
              :source_capability_postures,
              :telemetry_backfill_lifecycle,
              :telemetry_revision_decisions
            ],
            families: [
              :contacts,
              :mission_timeline,
              :source_health,
              :source_watermarks,
              :source_capabilities,
              :telemetry_backfills,
              :telemetry_revisions
            ]
          }
        ],
        overlays: [],
        live_mode: :poll_latest
      },
      binding_schema: %{
        min_observables: 0,
        max_observables: 0,
        observable_kinds: [],
        scope_modes: [:context],
        data_modes: [:context],
        value_types: [],
        sampling_modes: [:event_history],
        allowed_overlays: []
      },
      options_schema: [],
      layout_contract: %{min_w: 4, min_h: 3, preferred_w: 6, preferred_h: 4, resize: :both},
      drilldown_contract: %{
        primary_action: :inspect,
        supported_targets: [
          :mission_event,
          :source_health_event,
          :source_watermark_event,
          :telemetry_revision_decision_event,
          :telemetry_backfill_lifecycle_event,
          :contact
        ],
        selection_modes: [:placement, :event, :warning],
        preserve_context?: true
      },
      renderer: %{locus: :server_component, component: "EventTimeline"}
    }
  end

  defp constellation_health do
    %WidgetType{
      widget_type_id: "cadence.constellation_health",
      version: 1,
      name: "Constellation Health",
      category: :operations,
      icon: "hero-squares-2x2",
      trust: :first_party,
      data_contract: %{
        frames: [
          %{
            role: :primary,
            source: :operational_observables,
            accepted_shapes: [:matrix],
            temporal?: false,
            sampling: :constellation_health,
            products: [:constellation_health]
          }
        ],
        overlays: [],
        live_mode: :poll_latest
      },
      binding_schema: %{
        min_observables: 0,
        max_observables: 0,
        observable_kinds: [:metric, :state],
        scope_modes: [:context, :repeat],
        data_modes: [:context],
        value_types: [:engineering, :raw],
        sampling_modes: [:constellation_health],
        allowed_overlays: []
      },
      options_schema: [],
      layout_contract: %{min_w: 4, min_h: 3, preferred_w: 8, preferred_h: 4, resize: :both},
      drilldown_contract: %{
        primary_action: :inspect,
        supported_targets: [:telemetry_point, :explore],
        selection_modes: [:placement, :field, :warning],
        preserve_context?: true
      },
      renderer: %{locus: :client_hook, hook: "DashboardConstellationHealth"}
    }
  end
end
