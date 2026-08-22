defmodule Cadence.Dashboards.PublishReadinessTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{Document, Placement, WidgetDef}

  alias Cadence.DataSources.{SourceHealthEvent, SourceHealthStatus}

  alias Cadence.Management.DataSources

  alias Cadence.DataSources.{DataBinding, DataSource}

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  test "accepts structurally valid dashboard when default sources can satisfy planned requests" do
    document = load_fixture!("value_tile_latest.v1.json")

    assert %{valid?: true, errors: []} =
             Dashboards.validate_publish_readiness(
               document.organization_id,
               document.mission_id,
               document,
               registry_opts()
             )
  end

  test "blocks publish when a planned source request has no matching binding" do
    document = load_fixture!("value_tile_latest.v1.json")

    validation =
      Dashboards.validate_publish_readiness(
        document.organization_id,
        document.mission_id,
        document,
        data_sources: default_data_sources(),
        data_bindings: []
      )

    refute validation.valid?

    assert [
             %{
               code: :unready_publish_source_request,
               details: %{source_warning_code: :missing_source_binding}
             }
             | _rest
           ] = validation.errors
  end

  test "blocks publish when physical source capabilities cannot satisfy widget sampling" do
    document = load_fixture!("value_tile_latest.v1.json")
    %DataSource{} = telemetry_source = DataSources.default_managed_data_source()

    validation =
      Dashboards.validate_publish_readiness(
        document.organization_id,
        document.mission_id,
        document,
        registry_opts(
          telemetry_source: %DataSource{
            telemetry_source
            | capabilities: %{latest?: false, range_scan?: true}
          }
        )
      )

    refute validation.valid?

    assert %{
             code: :unready_publish_source_request,
             details: %{
               source_warning_code: :unsupported_source_capability,
               details: details
             }
           } =
             Enum.find(
               validation.errors,
               &(&1.details.source_warning_code == :unsupported_source_capability)
             )

    assert details.logical_source == :telemetry
    assert details.requested_sampling == :latest
    assert details.source_binding_id == "default_flight_telemetry"
    assert details.data_source_id == "managed_questdb_primary"
  end

  test "blocks operational metric history publish with source product guidance" do
    document = load_fixture!("operational_rf_metric_time_series.v1.json")

    %DataSource{} = default_source = DataSources.default_operational_observables_data_source()
    operational_source = %DataSource{default_source | capabilities: %{range_scan?: false}}

    validation =
      Dashboards.validate_publish_readiness(
        document.organization_id,
        document.mission_id,
        document,
        registry_opts(operational_source: operational_source)
      )

    refute validation.valid?

    assert %{
             code: :unready_publish_source_request,
             details: %{
               source_warning_code: :unsupported_source_capability,
               placement_id: "placement_link_snr_history",
               details: details
             }
           } =
             Enum.find(
               validation.errors,
               &(&1.details.source_warning_code == :unsupported_source_capability)
             )

    assert details.logical_source == :operational_observables
    assert details.requested_sampling == :raw_series
    assert details.supported_sampling == [:constellation_health, :latest, :event_history]
    assert details.requested_observables == ["link.snr_db"]
    assert details.unsupported_observables == ["link.snr_db"]
    assert details.requested_products == [:transport_bitrate, :link_rf, :runtime_ingress]
    assert details.requested_source_products == [:link_rf_metric_history]
    assert details.requested_product_families == [:link_rf]
    assert details.source_binding_id == "default_flight_operational_observables"
    assert details.data_source_id == "managed_operational_observables"
  end

  test "blocks operational metric history publish when source supports the wrong history product" do
    document = load_fixture!("operational_rf_metric_time_series.v1.json")

    %DataSource{} = default_source = DataSources.default_operational_observables_data_source()

    operational_source = %DataSource{
      default_source
      | capabilities: %{
          latest?: true,
          range_scan?: true,
          supported_products: [:transport_bitrate_history]
        }
    }

    validation =
      Dashboards.validate_publish_readiness(
        document.organization_id,
        document.mission_id,
        document,
        registry_opts(operational_source: operational_source)
      )

    refute validation.valid?

    assert %{
             code: :unready_publish_source_request,
             details: %{
               source_warning_code: :unsupported_source_capability,
               placement_id: "placement_link_snr_history",
               details: details
             }
           } =
             Enum.find(
               validation.errors,
               &(&1.details.source_warning_code == :unsupported_source_capability)
             )

    assert details.logical_source == :operational_observables
    assert details.requested_sampling == :raw_series
    assert :raw_series in details.supported_sampling
    assert details.requested_products == [:transport_bitrate, :link_rf, :runtime_ingress]
    assert details.requested_source_products == [:link_rf_metric_history]
    assert details.supported_products == [:transport_bitrate_history]
    assert details.requested_product_families == [:link_rf]
    assert details.supported_product_families == [:transport_bitrate]
    assert details.source_binding_id == "default_flight_operational_observables"
    assert details.data_source_id == "managed_operational_observables"
  end

  test "blocks publish when source connection test readiness fails" do
    document = load_fixture!("value_tile_latest.v1.json")

    validation =
      Dashboards.validate_publish_readiness(
        document.organization_id,
        document.mission_id,
        document,
        registry_opts(
          source_health_statuses: [
            source_health_status("managed_questdb_primary",
              payload: %{
                connection_test_result: "failed",
                connection_test_kind: "adapter_io",
                connection_test_message: "Adapter connection test failed."
              }
            )
          ]
        )
      )

    refute validation.valid?

    assert %{
             code: :unready_publish_source_request,
             details: %{
               source_warning_code: :source_connection_failed,
               details: details
             }
           } =
             Enum.find(
               validation.errors,
               &(&1.details.source_warning_code == :source_connection_failed)
             )

    assert details.data_source_id == "managed_questdb_primary"
    assert details.source_health == :healthy
    assert details.connection_test_result == "failed"
    assert details.connection_test_kind == "adapter_io"
    assert details.connection_test_message == "Adapter connection test failed."
  end

  test "blocks publish when operational observables cannot satisfy dashboard scope" do
    document =
      "value_tile_latest.v1.json"
      |> load_fixture!()
      |> Document.replace_placements([
        %Placement{
          placement_id: "placement_ground_state",
          layout: %{x: 0, y: 0, w: 6, h: 3},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.state_timeline",
            widget_type_version: 1,
            title: "Ground station state",
            binding: %{
              source: :operational_observables,
              observables: ["ground.station.connection_state"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :event_history,
              overlays: []
            },
            options: %{precision: 0, window_seconds: 300}
          }
        }
      ])

    validation =
      Dashboards.validate_publish_readiness(
        document.organization_id,
        document.mission_id,
        document,
        registry_opts()
      )

    refute validation.valid?

    assert %{
             code: :unready_publish_source_request,
             details: %{
               source_warning_code: :unsupported_observable_scope,
               details: details
             }
           } =
             Enum.find(
               validation.errors,
               &(&1.details.source_warning_code == :unsupported_observable_scope)
             )

    assert details.logical_source == :operational_observables
    assert details.requested_scope_kind == :spacecraft
    assert details.requested_scope_ids == []
    assert details.unsupported_observables == ["ground.station.connection_state"]

    assert details.supported_scopes == %{
             "ground.station.connection_state" => [
               :ground_station,
               :mission,
               :source_endpoint,
               :transport,
               :link
             ]
           }
  end

  defp registry_opts(opts \\ []) do
    telemetry_source =
      Keyword.get(opts, :telemetry_source, DataSources.default_managed_data_source())

    operational_source =
      Keyword.get(
        opts,
        :operational_source,
        DataSources.default_operational_observables_data_source()
      )

    [
      data_sources: [
        telemetry_source,
        DataSources.default_limits_data_source(),
        operational_source,
        DataSources.default_events_data_source()
      ],
      data_bindings: default_data_bindings(),
      source_health_statuses: Keyword.get(opts, :source_health_statuses, [])
    ]
  end

  defp default_data_sources do
    [
      DataSources.default_managed_data_source(),
      DataSources.default_limits_data_source(),
      DataSources.default_operational_observables_data_source(),
      DataSources.default_events_data_source()
    ]
  end

  defp default_data_bindings do
    [
      DataSources.default_flight_telemetry_binding(),
      DataSources.default_flight_limits_binding(),
      DataSources.default_flight_operational_observables_binding(),
      DataSources.default_flight_events_binding()
    ]
    |> Enum.map(&scope_binding/1)
  end

  defp scope_binding(%DataBinding{} = binding) do
    %DataBinding{
      binding
      | organization_id: "org_dashboards",
        mission_id: "mission_dashboards"
    }
  end

  defp source_health_status(data_source_id, opts) do
    observed_at = Keyword.get(opts, :observed_at, DateTime.utc_now())

    %SourceHealthStatus{
      source_health_key:
        SourceHealthEvent.source_health_key(%{
          organization_id: "org_dashboards",
          mission_id: "mission_dashboards",
          logical_source: :telemetry,
          data_source_id: data_source_id,
          source_binding_id: nil,
          realm: nil,
          dataset: nil
        }),
      source_health_event_id: "source-health-event-#{data_source_id}",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      logical_source: :telemetry,
      data_source_id: data_source_id,
      source_health: Keyword.get(opts, :source_health, :healthy),
      reason: Keyword.get(opts, :reason, :source_probe_succeeded),
      observed_at: observed_at,
      last_seen_at: Keyword.get(opts, :last_seen_at, observed_at),
      transition_count: 1,
      payload: Keyword.get(opts, :payload, %{})
    }
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
    |> Document.put_version(1)
  end
end
