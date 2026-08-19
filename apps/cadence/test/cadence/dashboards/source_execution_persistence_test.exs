defmodule Cadence.Dashboards.SourceExecutionPersistenceTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    Engine,
    HydratedResolveRequest,
    SourceCircuitBreaker,
    SourceExecutionSemantics
  }

  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  alias Cadence.DataSources.{DataBinding, DataSource}

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  test "BYO source timeout opens only that physical source circuit while managed source still executes" do
    persist_mission_scope("org_dashboards", "mission_dashboards")

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "secret://org_dashboards/dashboard/customer-byo-questdb",
               organization_id: "org_dashboards",
               mission_id: "mission_dashboards",
               data_source_id: "customer-byo-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/byo-questdb"}
             })

    breaker = start_supervised!({SourceCircuitBreaker, name: nil})
    request = resolve_request(byo_managed_telemetry_execution_document())

    source_opts = %{
      telemetry: [
        test_pid: self(),
        sleep_ms_by_sampling: %{latest: 200}
      ]
    }

    first =
      Engine.resolve_hydrated(request,
        data_sources: [byo_test_adapter_data_source(), managed_test_adapter_data_source()],
        data_bindings: [byo_telemetry_binding(), managed_telemetry_binding()],
        source_opts: source_opts,
        source_execution_max_concurrency: 2,
        source_circuit_breaker: breaker,
        source_health_events?: false,
        record_source_health_events?: false,
        source_watermark_events?: false,
        now_ms: 10_000
      )

    first_outcomes =
      first
      |> SourceExecutionSemantics.summarize()
      |> Map.fetch!(:outcomes)

    assert Enum.frequencies_by(first_outcomes, & &1.metadata.data_source_id) == %{
             "customer-byo-questdb" => 1,
             "managed-questdb" => 1
           }

    assert Enum.any?(first_outcomes, fn outcome ->
             outcome.metadata.data_source_id == "customer-byo-questdb" and
               outcome.status == :source_execution_failed and
               outcome.warning_codes == [:source_unavailable] and
               outcome.operator_action == :inspect_source_failure and
               outcome.runtime_action == :retry_source_execution and
               outcome.actionable? and
               outcome.retryable?
           end)

    assert Enum.any?(first_outcomes, fn outcome ->
             outcome.metadata.data_source_id == "managed-questdb" and
               outcome.status == :cache_disabled and
               outcome.warning_codes == []
           end)

    first_byo_warning =
      Enum.find(first.dashboard_warnings, fn warning ->
        warning.code == :source_unavailable and
          warning.details.data_source_id == "customer-byo-questdb"
      end)

    assert first_byo_warning.details.reason =~ "timeout after 50ms"

    flush_test_adapter_messages()

    second =
      Engine.resolve_hydrated(request,
        data_sources: [byo_test_adapter_data_source(), managed_test_adapter_data_source()],
        data_bindings: [byo_telemetry_binding(), managed_telemetry_binding()],
        source_opts: source_opts,
        source_execution_max_concurrency: 2,
        source_circuit_breaker: breaker,
        source_health_events?: false,
        record_source_health_events?: false,
        source_watermark_events?: false,
        now_ms: 10_001
      )

    second_outcomes =
      second
      |> SourceExecutionSemantics.summarize()
      |> Map.fetch!(:outcomes)

    assert Enum.any?(second_outcomes, fn outcome ->
             outcome.metadata.data_source_id == "customer-byo-questdb" and
               outcome.status == :source_degraded and
               outcome.warning_codes == [:source_degraded] and
               outcome.operator_action == :inspect_source_health and
               outcome.runtime_action == :wait_for_source_health
           end)

    assert Enum.any?(second_outcomes, fn outcome ->
             outcome.metadata.data_source_id == "managed-questdb" and
               outcome.status == :cache_disabled and
               outcome.warning_codes == []
           end)

    byo_warning =
      Enum.find(second.dashboard_warnings, fn warning ->
        warning.code == :source_degraded and
          warning.details.data_source_id == "customer-byo-questdb"
      end)

    assert byo_warning.details.circuit_state == :open
    assert byo_warning.details.failure_count == 1
    assert byo_warning.details.failure_threshold == 1
    assert byo_warning.details.retry_after_ms == 70_000
    assert byo_warning.details.last_failure_reason == :source_unavailable

    assert_received {:dashboard_source_test_adapter_request, "managed-questdb", :raw_series}
    refute_received {:dashboard_source_test_adapter_request, "customer-byo-questdb", :latest}
  end

  defp resolve_request(%Document{} = document) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
    }
    |> HydratedResolveRequest.new!()
  end

  defp byo_managed_telemetry_execution_document do
    latest_attrs = load_fixture_map!("value_tile_latest.v1.json")
    [latest_placement] = latest_attrs["placements"]
    [history_placement] = load_fixture_map!("time_series_with_limits.v1.json")["placements"]

    latest_placement =
      latest_placement
      |> put_in(["content", "widget_def", "binding", "overlays"], [])
      |> Map.put("data_override", %{
        "realm" => "flight",
        "source_contexts" => %{
          "telemetry" => %{
            "data_source_id" => "customer-byo-questdb",
            "source_binding_id" => "customer-byo-telemetry",
            "dataset" => "customer-flight"
          }
        }
      })

    history_placement =
      history_placement
      |> put_in(["content", "widget_def", "binding", "sampling"], "raw_series")
      |> put_in(["content", "widget_def", "binding", "overlays"], [])
      |> Map.put("data_override", %{
        "realm" => "flight",
        "source_contexts" => %{
          "telemetry" => %{
            "data_source_id" => "managed-questdb",
            "source_binding_id" => "managed-telemetry",
            "dataset" => "flight"
          }
        }
      })

    latest_attrs
    |> put_in(["defaults", "overlays", "limits"], false)
    |> Map.put("placements", [latest_placement, history_placement])
    |> Document.from_map()
  end

  defp byo_test_adapter_data_source do
    %DataSource{
      data_source_id: "customer-byo-questdb",
      owner: :customer,
      kind: :byo_tsdb,
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      isolation_level: :customer_owned,
      credentials_ref: "secret://org_dashboards/dashboard/customer-byo-questdb",
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      capabilities: %{latest?: true, range_scan?: true},
      metadata: %{
        dashboard_policy: %{
          execution: %{timeout_ms: 50},
          circuit_breaker: %{failure_threshold: 1, backoff_ms: 60_000}
        }
      }
    }
  end

  defp managed_test_adapter_data_source do
    %DataSource{
      data_source_id: "managed-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      isolation_level: :shared,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      capabilities: %{latest?: true, range_scan?: true}
    }
  end

  defp telemetry_binding(data_source_id) do
    %DataBinding{
      binding_id: "flight-telemetry",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: "flight"
    }
  end

  defp byo_telemetry_binding do
    %DataBinding{
      telemetry_binding("customer-byo-questdb")
      | binding_id: "customer-byo-telemetry",
        dataset: "customer-flight"
    }
  end

  defp managed_telemetry_binding do
    %DataBinding{
      telemetry_binding("managed-questdb")
      | binding_id: "managed-telemetry",
        dataset: "flight"
    }
  end

  defp load_fixture_map!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end

  defp flush_test_adapter_messages do
    receive do
      {:dashboard_source_test_adapter_request, _data_source_id, _sampling} ->
        flush_test_adapter_messages()
    after
      0 -> :ok
    end
  end
end
