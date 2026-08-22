defmodule Cadence.Observability.GrafanaIngressLoadTestDashboardTest do
  use Cadence.UnitCase, async: true

  @root Path.expand("../../../../..", __DIR__)
  @dashboard_path Path.join(
                    @root,
                    "dev/grafana/provisioning/dashboards/json/cadence-ingress-load-test.json"
                  )
  @overview_path Path.join(
                   @root,
                   "dev/grafana/provisioning/dashboards/json/cadence-sre-overview.json"
                 )

  @required_metric_names [
    "cadence_telemetry_ingress_received_bytes_total",
    "cadence_telemetry_ingress_processed_bytes_total",
    "cadence_telemetry_ingress_receive_size_bytes_bucket",
    "cadence_telemetry_ingress_receive_operation_duration_seconds_bucket",
    "cadence_telemetry_ingress_queue_size_bytes",
    "cadence_telemetry_ingress_queue_oldest_age_seconds",
    "cadence_telemetry_ingress_journal_retained_bytes",
    "cadence_telemetry_ingress_journal_capacity_bytes",
    "cadence_telemetry_ingress_journal_lag_bytes",
    "cadence_telemetry_ingress_journal_utilization_ratio",
    "cadence_telemetry_ingress_journal_appended_bytes_total",
    "cadence_telemetry_ingress_journal_append_duration_seconds_bucket",
    "cadence_telemetry_ingress_journal_append_queue_wait_duration_seconds_bucket",
    "cadence_telemetry_ingress_journal_record_size_bytes_bucket",
    "cadence_telemetry_ingress_journal_processing_batch_size_bytes_bucket",
    "cadence_telemetry_ingress_journal_maintenance_duration_seconds_bucket",
    "cadence_telemetry_ingress_journal_maintenance_queue_wait_duration_seconds_bucket",
    "cadence_telemetry_ingress_journal_checkpoint_duration_seconds_bucket",
    "cadence_telemetry_ingress_journal_reclaim_duration_seconds_bucket",
    "cadence_telemetry_ingress_journal_entry_count",
    "cadence_telemetry_ingress_journal_segment_count",
    "cadence_telemetry_ingress_journal_mailbox_depth",
    "cadence_telemetry_ingress_journal_checkpoint_inflight",
    "cadence_telemetry_ingress_archive_archived_bytes_total",
    "cadence_telemetry_ingress_archive_batch_size_bucket",
    "cadence_telemetry_ingress_archive_duration_seconds_bucket",
    "cadence_telemetry_ingress_archive_queue_size_bytes",
    "cadence_telemetry_ingress_archive_attempt_total",
    "cadence_telemetry_ingress_processing_duration_seconds_bucket",
    "cadence_telemetry_persistence_duration_seconds_bucket",
    "beam_scheduler_utilization_ratio",
    "beam_reductions_total",
    "beam_gc_collection_total",
    "beam_gc_reclaimed_total"
  ]

  test "provisions the live ingress load-test measurement contract" do
    dashboard = decode!(@dashboard_path)
    panels = dashboard["panels"]
    panel_ids = Enum.map(panels, & &1["id"])
    queries = panel_queries(panels)

    assert dashboard["uid"] == "cadence-ingress-load-test"
    assert dashboard["refresh"] == "5s"
    assert dashboard["time"] == %{"from" => "now-15m", "to" => "now"}
    assert panel_ids == Enum.uniq(panel_ids)
    assert Enum.all?(panels, &valid_grid_position?/1)

    Enum.each(@required_metric_names, fn metric_name ->
      assert Enum.any?(queries, &String.contains?(&1, metric_name)),
             "dashboard does not query #{metric_name}"
    end)

    assert Enum.any?(queries, &String.contains?(&1, "vector($target_mbps * 1000000)"))
    refute Enum.any?(queries, &String.contains?(&1, "run_id"))

    assert dashboard["templating"]["list"]
           |> Enum.map(& &1["name"])
           |> MapSet.new() == MapSet.new(["service", "direction", "protocol", "target_mbps"])

    service_variable = Enum.find(dashboard["templating"]["list"], &(&1["name"] == "service"))

    assert service_variable["current"] == %{
             "text" => "cadence-ingress-benchmark",
             "value" => "cadence-ingress-benchmark"
           }
  end

  test "links the SRE overview and ingress load-test dashboard in both directions" do
    dashboard = decode!(@dashboard_path)
    overview = decode!(@overview_path)

    assert link?(dashboard, "/d/cadence-sre-overview/cadence-sre-overview")
    assert link?(overview, "/d/cadence-ingress-load-test/cadence-ingress-load-test")

    service_variable = Enum.find(overview["templating"]["list"], &(&1["name"] == "service"))
    assert service_variable["definition"] == "label_values(beam_memory_usage_bytes, service_name)"
  end

  defp decode!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp panel_queries(panels) do
    panels
    |> Enum.flat_map(&Map.get(&1, "targets", []))
    |> Enum.map(&Map.fetch!(&1, "expr"))
  end

  defp valid_grid_position?(%{"gridPos" => grid_position}) do
    Enum.all?(["h", "w", "x", "y"], &(is_integer(grid_position[&1]) and grid_position[&1] >= 0))
  end

  defp valid_grid_position?(_panel), do: false

  defp link?(dashboard, url) do
    Enum.any?(dashboard["links"], &(&1["url"] == url))
  end
end
