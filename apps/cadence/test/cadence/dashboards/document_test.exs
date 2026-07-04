defmodule Cadence.Dashboards.DocumentTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards
  alias Cadence.Dashboards.{Document, WidgetDef, WidgetRegistry}

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  describe "golden dashboard documents" do
    test "loads and validates Tier 0 dashboard fixtures" do
      for fixture <- [
            "value_tile_latest.v1.json",
            "time_series_with_limits.v1.json",
            "repeated_spacecraft_status.v1.json",
            "replay_context.v1.json"
          ] do
        document = load_fixture!(fixture)

        assert %Document{schema_version: 1, placements: [_ | _]} = document
        assert %{valid?: true, errors: [], warnings: []} = Dashboards.validate_document(document)
      end
    end

    test "normalizes widget bindings from fixture JSON" do
      document = load_fixture!("time_series_with_limits.v1.json")

      [placement] = document.placements

      assert placement.layout == %{x: 0, y: 0, w: 8, h: 4, min_w: nil, min_h: nil}
      assert placement.widget_def.widget_type_id == "cadence.time_series"

      assert placement.widget_def.binding.observables == [
               "tlm.hk.battery_voltage",
               "tlm.hk.bus_current"
             ]

      assert placement.widget_def.binding.scope_mode == :context
      assert placement.widget_def.binding.source == :telemetry
      assert placement.widget_def.binding.sampling == :decimated_envelope
      assert placement.widget_def.binding.overlays == [:limits, :events, :quality]
    end

    test "normalizes operational observable widget binding source from persisted JSON" do
      widget_def =
        WidgetDef.from_map(%{
          "widget_type_id" => "cadence.status_matrix",
          "binding" => %{
            "source" => "operational_observables",
            "observables" => ["contacts.phase"]
          }
        })

      assert widget_def.binding.source == :operational_observables
      assert widget_def.binding.observables == ["contacts.phase"]
    end

    test "normalizes constellation health sampling from persisted JSON" do
      widget_def =
        WidgetDef.from_map(%{
          "widget_type_id" => "cadence.constellation_health",
          "binding" => %{"sampling" => "constellation_health"}
        })

      assert widget_def.binding.sampling == :constellation_health
    end

    test "normalizes event timeline source and sampling from persisted JSON" do
      widget_def =
        WidgetDef.from_map(%{
          "widget_type_id" => "cadence.event_timeline",
          "binding" => %{"source" => "events", "sampling" => "event_history"}
        })

      assert widget_def.binding.source == :events
      assert widget_def.binding.sampling == :event_history
      assert widget_def.binding.observables == []
    end

    test "normalizes state timeline limits source from persisted JSON" do
      widget_def =
        WidgetDef.from_map(%{
          "widget_type_id" => "cadence.state_timeline",
          "binding" => %{
            "source" => "limits",
            "sampling" => "event_history",
            "observables" => ["HK.battery_voltage"]
          }
        })

      assert widget_def.binding.source == :limits
      assert widget_def.binding.sampling == :event_history
      assert widget_def.binding.value_type == :engineering
      assert widget_def.binding.observables == ["HK.battery_voltage"]
    end

    test "serializes canonical document shape for persistence" do
      document = load_fixture!("value_tile_latest.v1.json")

      round_tripped =
        document
        |> Document.to_map()
        |> Jason.encode!()
        |> Jason.decode!()
        |> Document.from_map()

      assert round_tripped == document
    end

    test "migrates schema-less canonical document maps to the current schema" do
      attrs =
        "value_tile_latest.v1.json"
        |> load_fixture_map!()
        |> Map.delete("schema_version")

      assert {:ok, %Dashboards.DocumentMigration.Result{} = result} =
               Dashboards.migrate_document_map(attrs)

      assert result.changed?
      assert result.source_schema_version == 0
      assert result.target_schema_version == 1
      assert result.migrations == ["dashboard_document.v0_to_v1"]
      assert %Document{schema_version: 1, placements: [_ | _]} = result.document

      assert %{valid?: true, errors: [], warnings: []} =
               Dashboards.validate_document(result.document)
    end

    test "migrates legacy widget arrays to canonical placements" do
      legacy = %{
        "dashboard_id" => "dashboard_legacy_widgets",
        "organization_id" => "org_dashboards",
        "mission_id" => "mission_dashboards",
        "name" => "Legacy Widgets",
        "grid" => %{"columns" => 12, "row_height_px" => 64, "gap_px" => 8},
        "widgets" => [
          %{
            "widget_id" => "legacy_counter",
            "type" => "value_tile",
            "title" => "Counter",
            "point_id" => "HK.counter",
            "layout" => %{"x" => 0, "y" => 0, "w" => 2, "h" => 2}
          },
          %{
            "widget_id" => "legacy_spectrum",
            "type" => "partner.spectrum_waterfall",
            "title" => "Spectrum",
            "point_id" => "RF.spectrum",
            "layout" => %{"x" => 2, "y" => 0, "w" => 4, "h" => 3}
          }
        ],
        "metadata" => %{"version" => 1}
      }

      assert {:ok, %Dashboards.DocumentMigration.Result{} = result} =
               Dashboards.migrate_document_map(legacy)

      assert result.changed?

      assert result.migrations == [
               "dashboard_document.v0_to_v1",
               "dashboard_document.legacy_widgets_to_placements"
             ]

      assert %Document{placements: [counter, spectrum]} = result.document
      assert counter.placement_id == "legacy_counter"
      assert counter.widget_def.widget_type_id == "cadence.value_tile"
      assert counter.widget_def.binding.observables == ["HK.counter"]
      assert spectrum.placement_id == "legacy_spectrum"
      assert spectrum.widget_def.widget_type_id == "partner.spectrum_waterfall"

      validation = Dashboards.validate_document(result.document)
      assert validation.valid?
      assert [%{code: :unknown_widget_type, details: details}] = validation.warnings
      assert details.placement_id == "legacy_spectrum"
    end

    test "retains unknown widget types as validation warnings" do
      document = load_fixture!("unknown_widget_retained.v1.json")

      assert [placement] = document.placements
      assert placement.widget_def.widget_type_id == "partner.spectrum_waterfall"

      result = Dashboards.validate_document(document)

      assert result.valid?
      assert result.errors == []
      assert [%{code: :unknown_widget_type, details: details}] = result.warnings
      assert details.placement_id == "placement_legacy"
      assert details.widget_type_id == "partner.spectrum_waterfall"
    end

    test "rejects invalid runtime default contexts" do
      document =
        "value_tile_latest.v1.json"
        |> load_fixture!()
        |> put_in([Access.key!(:defaults), "time", "mode"], "unsupported")
        |> put_in([Access.key!(:defaults), "data", "realm"], "lab")
        |> put_in([Access.key!(:defaults), "scope", "primary", "kind"], "antenna")
        |> put_in([Access.key!(:defaults), "limits", "semantics_mode"], "latest")

      result = Dashboards.validate_document(document)

      refute result.valid?

      assert %{code: :invalid_runtime_default_context, details: %{context: :time, errors: time}} =
               Enum.find(result.errors, &(&1.details[:context] == :time))

      assert :unsupported_time_mode in time

      assert %{code: :invalid_runtime_default_context, details: %{context: :data, errors: data}} =
               Enum.find(result.errors, &(&1.details[:context] == :data))

      assert :unsupported_data_realm in data

      assert %{code: :invalid_runtime_default_context, details: %{context: :scope, errors: scope}} =
               Enum.find(result.errors, &(&1.details[:context] == :scope))

      assert :unsupported_scope_kind in scope

      assert %{
               code: :invalid_runtime_default_context,
               details: %{context: :limits, errors: limits}
             } = Enum.find(result.errors, &(&1.details[:context] == :limits))

      assert :unsupported_limit_semantics_mode in limits
    end
  end

  describe "widget registry" do
    test "exposes first-party widget contracts" do
      assert {:ok, type} = WidgetRegistry.fetch_type("cadence.time_series", :latest)

      assert type.version == 1
      assert type.data_contract.live_mode == :poll_latest
      assert type.binding_schema.max_observables == 8
      assert type.layout_contract.min_w == 4
      assert type.drilldown_contract.preserve_context?

      assert {:error, :unknown_widget_type} =
               WidgetRegistry.fetch_type("partner.unknown", :latest)

      assert {:error, :unsupported_widget_version} =
               WidgetRegistry.fetch_type("cadence.time_series", 99)
    end

    test "declares operational source overrides on widgets that support operational data" do
      assert {:ok, value_tile} = WidgetRegistry.fetch_type("cadence.value_tile", :latest)
      assert {:ok, status_matrix} = WidgetRegistry.fetch_type("cadence.status_matrix", :latest)
      assert {:ok, time_series} = WidgetRegistry.fetch_type("cadence.time_series", :latest)

      assert [value_frame] = value_tile.data_contract.frames
      assert [value_override] = value_frame.source_overrides
      assert value_override.source == :operational_observables
      assert value_override.accepted_shapes == [:matrix]

      assert value_override.products == [
               :transport_bitrate,
               :link_rf,
               :commanding,
               :runtime_ingress
             ]

      assert [status_frame] = status_matrix.data_contract.frames
      assert [status_override] = status_frame.source_overrides
      assert status_override.source == :operational_observables

      assert status_override.products == [
               :contacts_phase,
               :connection_state,
               :ground_station,
               :link_rf,
               :transport_bitrate,
               :commanding,
               :runtime_ingress
             ]

      assert [series_frame] = time_series.data_contract.frames
      assert [series_override] = series_frame.source_overrides
      assert series_override.source == :operational_observables
      assert series_override.accepted_shapes == [:wide]
      assert series_override.temporal?
      assert series_override.sampling == :raw_series
      assert series_override.products == [:transport_bitrate, :link_rf, :runtime_ingress]
      assert series_override.observable_value_kinds == [:metric]
    end

    test "migrates current-version options as a no-op" do
      options = %{"legend" => true}

      assert {:ok, 1, ^options} =
               WidgetRegistry.migrate_options("cadence.time_series", 1, options)

      assert {:error, :unsupported_widget_version} =
               WidgetRegistry.migrate_options("cadence.time_series", 0, options)
    end
  end

  describe "document validation" do
    test "mutates placements by canonical placement id" do
      document = load_fixture!("value_tile_latest.v1.json")
      [placement] = document.placements

      renamed_placement = %{
        placement
        | widget_def: %{placement.widget_def | title: "Renamed Battery"}
      }

      updated = Document.put_placement(document, renamed_placement)

      assert [%{placement_id: placement_id, widget_def: %{title: "Renamed Battery"}}] =
               updated.placements

      assert placement_id == placement.placement_id

      removed = Document.remove_placement(updated, placement.placement_id)

      assert removed.placements == []
    end

    test "applies layout payloads to placements and clamps to widget minimums" do
      document = load_fixture!("value_tile_latest.v1.json")
      [placement] = document.placements

      updated =
        Document.apply_layouts(document, [
          %{
            "widget_id" => placement.placement_id,
            "x" => 99,
            "y" => 99,
            "w" => 1,
            "h" => 1
          },
          %{"widget_id" => "unknown", "x" => 0, "y" => 0, "w" => 12, "h" => 12}
        ])

      assert [%{layout: layout}] = updated.placements
      assert layout.x == 10
      assert layout.y == 23
      assert layout.w == 2
      assert layout.h == 2
    end

    test "rejects known widgets below their minimum layout size" do
      attrs =
        "time_series_with_limits.v1.json"
        |> load_fixture_map!()
        |> put_in(["placements", Access.at(0), "layout"], %{
          "x" => 0,
          "y" => 0,
          "w" => 3,
          "h" => 2
        })

      result =
        attrs
        |> Document.from_map()
        |> Dashboards.validate_document()

      refute result.valid?
      assert [%{code: :placement_below_widget_minimum, details: details}] = result.errors
      assert details.placement_id == "placement_power_trend"
      assert details.minimum == %{w: 4, h: 3}
    end

    test "accepts declared operational widget frame source overrides" do
      value_tile_attrs =
        "value_tile_latest.v1.json"
        |> load_fixture_map!()
        |> put_in(
          ["placements", Access.at(0), "content", "widget_def", "binding"],
          %{
            "source" => "operational_observables",
            "observables" => ["comms.transport.downlink_bitrate"],
            "scope_mode" => "context",
            "data_mode" => "context",
            "value_type" => "engineering",
            "sampling" => "latest",
            "overlays" => []
          }
        )

      status_matrix_attrs =
        "value_tile_latest.v1.json"
        |> load_fixture_map!()
        |> put_in(["placements", Access.at(0), "layout"], %{
          "x" => 0,
          "y" => 0,
          "w" => 4,
          "h" => 3
        })
        |> put_in(
          ["placements", Access.at(0), "content", "widget_def", "widget_type_id"],
          "cadence.status_matrix"
        )
        |> put_in(
          ["placements", Access.at(0), "content", "widget_def", "binding"],
          %{
            "source" => "operational_observables",
            "observables" => ["contacts.phase", "ground.station.connection_state"],
            "scope_mode" => "context",
            "data_mode" => "context",
            "value_type" => "engineering",
            "sampling" => "latest",
            "overlays" => []
          }
        )

      for attrs <- [value_tile_attrs, status_matrix_attrs] do
        result =
          attrs
          |> Document.from_map()
          |> Dashboards.validate_document()

        assert result.valid?
        assert result.errors == []
      end
    end

    test "rejects persisted time-series bindings with nonmetric operational observables" do
      attrs =
        "time_series_with_limits.v1.json"
        |> load_fixture_map!()
        |> put_in(
          ["placements", Access.at(0), "content", "widget_def", "binding"],
          %{
            "source" => "operational_observables",
            "observables" => ["contacts.phase"],
            "scope_mode" => "context",
            "data_mode" => "context",
            "value_type" => "engineering",
            "sampling" => "decimated_envelope",
            "overlays" => []
          }
        )

      result =
        attrs
        |> Document.from_map()
        |> Dashboards.validate_document()

      refute result.valid?

      assert [
               %{code: :unsupported_widget_frame_contract, details: details}
             ] = result.errors

      assert details.placement_id == "placement_power_trend"
      assert details.widget_type_id == "cadence.time_series"
      assert details.requested_source == :operational_observables
      assert details.contract_source == :telemetry
      assert details.supported_products == [:transport_bitrate, :link_rf, :runtime_ingress]
      assert details.supported_value_kinds == [:metric]
      assert details.requested_products == [:contacts_phase]
      assert details.requested_value_kinds == [:state]
      assert details.unsupported_observables == ["contacts.phase"]
    end

    test "rejects persisted operational observables outside widget frame products" do
      attrs =
        "value_tile_latest.v1.json"
        |> load_fixture_map!()
        |> put_in(
          ["placements", Access.at(0), "content", "widget_def", "binding"],
          %{
            "source" => "operational_observables",
            "observables" => ["comms.transport.connection_state"],
            "scope_mode" => "context",
            "data_mode" => "context",
            "value_type" => "engineering",
            "sampling" => "latest",
            "overlays" => []
          }
        )

      result =
        attrs
        |> Document.from_map()
        |> Dashboards.validate_document()

      refute result.valid?

      assert [
               %{code: :unsupported_widget_frame_contract, details: details}
             ] = result.errors

      assert details.placement_id == "placement_battery_voltage"
      assert details.widget_type_id == "cadence.value_tile"
      assert details.unsupported_observables == ["comms.transport.connection_state"]

      assert details.supported_products == [
               :transport_bitrate,
               :link_rf,
               :commanding,
               :runtime_ingress
             ]

      assert details.supported_value_kinds == [:metric]
      assert details.requested_products == [:connection_state]
      assert details.requested_value_kinds == [:state]
    end

    test "rejects duplicate placement ids" do
      attrs = load_fixture_map!("value_tile_latest.v1.json")
      [placement] = attrs["placements"]
      attrs = Map.put(attrs, "placements", [placement, placement])

      result =
        attrs
        |> Document.from_map()
        |> Dashboards.validate_document()

      refute result.valid?
      assert Enum.any?(result.errors, &(&1.code == :duplicate_placement_ids))
    end

    test "rejects unsupported repeat bounds" do
      attrs =
        "repeated_spacecraft_status.v1.json"
        |> load_fixture_map!()
        |> put_in(["placements", Access.at(0), "repeat", "max_instances"], 99)

      result =
        attrs
        |> Document.from_map()
        |> Dashboards.validate_document()

      refute result.valid?
      assert [%{code: :repeat_instance_limit_exceeded}] = result.errors
    end
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
  end

  defp load_fixture_map!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end
end
