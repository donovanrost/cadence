defmodule Cadence.DataSources.ProbeSchedulerTest do
  use Cadence.DataCase, async: true

  alias Cadence.DataSources.ProbeScheduler

  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  alias Cadence.Management.DataSources

  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  alias Cadence.DataSources.DataSource

  @organization_id "org-source-probe-scheduler"
  @mission_id "mission-source-probe-scheduler"
  @now ~U[2026-06-21 15:00:00Z]

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "run_once probes missing and stale active sources and skips fresh disabled and unscoped sources" do
    missing = persist_source!("scheduler-missing")
    stale = persist_source!("scheduler-stale")
    fresh = persist_source!("scheduler-fresh")
    disabled = persist_source!("scheduler-disabled", status: :disabled)

    unscoped =
      persist_source!("scheduler-unscoped", mission_id: nil, isolation_level: :org_isolated)

    record_physical_health!(stale, :healthy, ~U[2026-06-21 14:58:00Z])
    record_physical_health!(fresh, :healthy, ~U[2026-06-21 14:59:30Z])

    test_pid = self()

    summary =
      ProbeScheduler.run_once(
        list_sources_fun: fn _, _ -> [missing, stale, fresh, disabled, unscoped] end,
        source_health_events?: true,
        source_health_freshness: [default_max_age_ms: 60_000],
        now: @now,
        probe_fun: fn data_source_id, attrs, opts ->
          send(test_pid, {:scheduled_probe, data_source_id, attrs, opts})
          {:ok, :unchanged, %{data_source_id: data_source_id}}
        end
      )

    assert summary.checked == 3
    assert summary.probed == 2
    assert summary.skipped_fresh == 1
    assert summary.skipped_disabled == 1
    assert summary.skipped_unscoped == 1
    assert summary.errors == []

    assert_receive {:scheduled_probe, "scheduler-missing", missing_attrs, missing_opts}
    assert missing_attrs.mission_id == missing.mission_id
    assert missing_attrs.observed_at == @now
    assert Keyword.fetch!(missing_opts, :actor_id) == "data_source_probe_scheduler"
    assert Keyword.fetch!(missing_opts, :payload).source == "data_source_probe_scheduler"

    assert_receive {:scheduled_probe, "scheduler-stale", _attrs, _opts}
    refute_received {:scheduled_probe, "scheduler-fresh", _attrs, _opts}
    refute_received {:scheduled_probe, "scheduler-disabled", _attrs, _opts}
    refute_received {:scheduled_probe, "scheduler-unscoped", _attrs, _opts}
  end

  test "run_once records health through the data source probe path" do
    source = persist_source!("scheduler-real-probe")

    summary =
      ProbeScheduler.run_once(
        list_sources_fun: fn _, _ -> [source] end,
        source_health_events?: true,
        source_health_freshness: [default_max_age_ms: 60_000],
        invalidate_runtime_cache?: false,
        now: @now,
        test_pid: self()
      )

    assert summary.checked == 1
    assert summary.probed == 1
    assert summary.errors == []
    assert_receive {:dashboard_source_test_adapter_probe, "scheduler-real-probe"}

    assert [status] =
             SourceHealth.list_source_health_statuses(@organization_id, @mission_id,
               data_source_id: source.data_source_id
             )

    assert status.source_health == :healthy
    assert status.reason == :source_probe_succeeded
    assert status.payload["source"] == "data_source_probe_scheduler"
  end

  test "run_once honors per-source probe policy freshness and disabled scheduling" do
    strict =
      persist_source!("scheduler-strict-policy",
        metadata: %{
          storage: :test,
          probe_policy: %{id: "strict-policy", stale_after_ms: 10_000}
        }
      )

    relaxed =
      persist_source!("scheduler-relaxed-policy",
        metadata: %{
          storage: :test,
          probe_policy: %{id: "relaxed-policy", stale_after_ms: 180_000}
        }
      )

    disabled_by_policy =
      persist_source!("scheduler-policy-disabled",
        metadata: %{
          storage: :test,
          probe_policy: %{id: "disabled-policy", enabled?: false, stale_after_ms: 10_000}
        }
      )

    record_physical_health!(strict, :healthy, ~U[2026-06-21 14:59:30Z])
    record_physical_health!(relaxed, :healthy, ~U[2026-06-21 14:58:00Z])

    test_pid = self()

    summary =
      ProbeScheduler.run_once(
        list_sources_fun: fn _, _ -> [strict, relaxed, disabled_by_policy] end,
        source_health_events?: true,
        source_health_freshness: [default_max_age_ms: 60_000],
        now: @now,
        probe_fun: fn data_source_id, _attrs, opts ->
          send(test_pid, {:scheduled_probe, data_source_id, Keyword.fetch!(opts, :payload)})
          {:ok, :unchanged, %{data_source_id: data_source_id}}
        end
      )

    assert summary.checked == 3
    assert summary.probed == 1
    assert summary.skipped_fresh == 1
    assert summary.skipped_policy == 1
    assert summary.errors == []

    assert_receive {:scheduled_probe, "scheduler-strict-policy", payload}
    assert payload.source == "data_source_probe_scheduler"
    assert payload.probe_policy_id == "strict-policy"
    assert payload.probe_stale_after_ms == 10_000

    refute_received {:scheduled_probe, "scheduler-relaxed-policy", _payload}
    refute_received {:scheduled_probe, "scheduler-policy-disabled", _payload}
  end

  test "run_once bounds slow BYO probes while managed probes still record health" do
    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref:
                 "secret://org-source-probe-scheduler/data-sources/scheduler-byo-slow",
               organization_id: @organization_id,
               mission_id: @mission_id,
               data_source_id: "scheduler-byo-slow",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/scheduler-byo-slow"}
             })

    byo_source =
      persist_source!("scheduler-byo-slow",
        owner: :customer,
        kind: :byo_tsdb,
        isolation_level: :customer_owned,
        credentials_ref: "secret://org-source-probe-scheduler/data-sources/scheduler-byo-slow"
      )

    managed_source = persist_source!("scheduler-managed-fast")
    test_pid = self()

    summary =
      ProbeScheduler.run_once(
        list_sources_fun: fn _, _ -> [byo_source, managed_source] end,
        source_health_events?: true,
        source_health_freshness: [default_max_age_ms: 60_000],
        invalidate_runtime_cache?: false,
        now: @now,
        max_concurrency: 1,
        probe_timeout_ms: 100,
        probe_fun: fn
          "scheduler-byo-slow", _attrs, _opts ->
            send(test_pid, {:probe_started, "scheduler-byo-slow"})

            receive do
              :release_slow_probe -> flunk("slow BYO probe should be killed by scheduler timeout")
            end

          "scheduler-managed-fast", attrs, opts ->
            send(test_pid, {:probe_started, "scheduler-managed-fast"})

            %{
              organization_id: managed_source.organization_id,
              mission_id: attrs.mission_id,
              logical_source: :unknown,
              data_source_id: managed_source.data_source_id,
              source_health: :healthy,
              reason: :source_probe_succeeded,
              observed_at: attrs.observed_at,
              payload: Keyword.fetch!(opts, :payload)
            }
            |> SourceHealth.record_source_health(opts)
        end
      )

    assert summary.checked == 2
    assert summary.probed == 1
    assert summary.errors == [exit: :timeout]

    assert_receive {:probe_started, "scheduler-byo-slow"}
    assert_receive {:probe_started, "scheduler-managed-fast"}

    assert [managed_status] =
             SourceHealth.list_source_health_statuses(@organization_id, @mission_id,
               data_source_id: "scheduler-managed-fast"
             )

    assert managed_status.source_health == :healthy
    assert managed_status.reason == :source_probe_succeeded
    assert managed_status.payload["source"] == "data_source_probe_scheduler"

    assert [byo_status] =
             SourceHealth.list_source_health_statuses(@organization_id, @mission_id,
               data_source_id: "scheduler-byo-slow"
             )

    assert byo_status.source_health == :unavailable
    assert byo_status.reason == :source_probe_timeout
    assert byo_status.payload["source"] == "data_source_probe_scheduler"
    assert byo_status.payload["probe_kind"] == "scheduler"
    assert byo_status.payload["probe_message"] == "Source probe exceeded scheduler timeout."
    assert byo_status.payload["probe_metadata"]["probe_timeout_ms"] == 100
    assert byo_status.payload["connection_test_result"] == "blocked"
    assert byo_status.payload["connection_test_kind"] == "scheduler_timeout"
  end

  test "run_once does nothing when source health events are disabled" do
    _source = persist_source!("scheduler-disabled-health")

    summary =
      ProbeScheduler.run_once(
        source_health_events?: false,
        probe_fun: fn _data_source_id, _attrs, _opts ->
          flunk("probe_fun should not be called")
        end
      )

    assert summary.checked == 0
    assert summary.probed == 0
    assert summary.skipped_source_health_disabled == 1
  end

  defp persist_source!(data_source_id, attrs \\ []) do
    data_source = %DataSource{
      data_source_id: data_source_id,
      owner: Keyword.get(attrs, :owner, :cadence),
      kind: Keyword.get(attrs, :kind, :managed_tsdb),
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      organization_id: Keyword.get(attrs, :organization_id, @organization_id),
      mission_id: Keyword.get(attrs, :mission_id, @mission_id),
      isolation_level: Keyword.get(attrs, :isolation_level, :mission_isolated),
      credentials_ref: Keyword.get(attrs, :credentials_ref),
      status: Keyword.get(attrs, :status, :active),
      capabilities: %{latest?: true},
      metadata: Keyword.get(attrs, :metadata, %{storage: :test})
    }

    assert {:ok, persisted} = DataSources.persist_data_source(data_source)
    persisted
  end

  defp record_physical_health!(%DataSource{} = source, source_health, observed_at) do
    assert {:ok, _event, _status} =
             %{
               organization_id: source.organization_id,
               mission_id: source.mission_id,
               logical_source: :unknown,
               data_source_id: source.data_source_id,
               source_health: source_health,
               reason: :source_probe_succeeded,
               observed_at: observed_at
             }
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)
  end
end
