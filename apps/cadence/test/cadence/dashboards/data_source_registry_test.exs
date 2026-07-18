defmodule Cadence.Dashboards.DataSourceRegistryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    DashboardAction,
    DataBinding,
    DataSource,
    DataSourceRegistry,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    RuntimeCacheKey,
    SourceFacts,
    SourceHealthEvent,
    SourceHealthStatus
  }

  test "resolves default flight telemetry binding to managed QuestDB source" do
    request = source_request()

    assert {:ok, %ResolvedSourceBinding{} = resolved} = DataSourceRegistry.resolve(request)
    assert resolved.binding.binding_id == "default_flight_telemetry"
    assert resolved.binding.realm == :flight
    assert resolved.binding.logical_source == :telemetry
    assert resolved.data_source.data_source_id == "managed_questdb_primary"
    assert resolved.data_source.kind == :managed_tsdb
    assert resolved.data_source.isolation_level == :shared
  end

  test "resolves default flight limits binding to managed limits projection source" do
    request = source_request(logical_source: :limits, sampling: %{mode: :latest_state})

    assert {:ok, %ResolvedSourceBinding{} = resolved} = DataSourceRegistry.resolve(request)
    assert resolved.binding.binding_id == "default_flight_limits"
    assert resolved.binding.realm == :flight
    assert resolved.binding.logical_source == :limits
    assert resolved.binding.dataset == "telemetry_latest_limit_states"
    assert resolved.data_source.data_source_id == "managed_limits_projection"
    assert resolved.data_source.kind == :projection
    assert resolved.data_source.adapter == Cadence.Dashboards.Sources.Limits
    assert resolved.data_source.isolation_level == :shared
  end

  test "resolves default flight operational observables binding" do
    request =
      source_request(
        logical_source: :operational_observables,
        observables: [],
        sampling: %{mode: :constellation_health}
      )

    assert {:ok, %ResolvedSourceBinding{} = resolved} = DataSourceRegistry.resolve(request)
    assert resolved.binding.binding_id == "default_flight_operational_observables"
    assert resolved.binding.realm == :flight
    assert resolved.binding.logical_source == :operational_observables
    assert resolved.binding.dataset == "operational_observables"
    assert resolved.data_source.data_source_id == "managed_operational_observables"
    assert resolved.data_source.kind == :projection
    assert resolved.data_source.adapter == Cadence.Dashboards.Sources.OperationalObservables
    assert resolved.data_source.isolation_level == :shared
  end

  test "resolves default flight events binding to managed event projection source" do
    request =
      source_request(
        logical_source: :events,
        observables: [],
        sampling: %{mode: :event_history}
      )

    assert {:ok, %ResolvedSourceBinding{} = resolved} = DataSourceRegistry.resolve(request)
    assert resolved.binding.binding_id == "default_flight_events"
    assert resolved.binding.realm == :flight
    assert resolved.binding.logical_source == :events
    assert resolved.binding.dataset == "mission_events"
    assert resolved.data_source.data_source_id == "managed_events_projection"
    assert resolved.data_source.kind == :projection
    assert resolved.data_source.adapter == Cadence.Dashboards.Sources.Events
    assert resolved.data_source.isolation_level == :shared
  end

  test "selects the most specific organization and mission binding" do
    bindings = [
      binding("default", nil, nil, "managed_questdb_primary", 0),
      binding("org", "org-1", nil, "org-questdb", 0),
      binding("mission", "org-1", "mission-1", "mission-questdb", 0)
    ]

    data_sources = [
      data_source("managed_questdb_primary", :shared),
      data_source("org-questdb", :org_isolated),
      data_source("mission-questdb", :mission_isolated)
    ]

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: data_sources,
               data_bindings: bindings
             )

    assert resolved.binding.binding_id == "mission"
    assert resolved.data_source.data_source_id == "mission-questdb"
    assert resolved.data_source.isolation_level == :mission_isolated
  end

  test "uses priority within the same binding specificity" do
    bindings = [
      binding("secondary", "org-1", "mission-1", "secondary", 10),
      binding("primary", "org-1", "mission-1", "primary", 0)
    ]

    data_sources = [
      data_source("secondary", :mission_isolated),
      data_source("primary", :mission_isolated)
    ]

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: data_sources,
               data_bindings: bindings
             )

    assert resolved.binding.binding_id == "primary"
    assert resolved.data_source.data_source_id == "primary"
  end

  test "skips current binding candidates with fresh unavailable source health" do
    bindings = [
      binding("primary", "org-1", "mission-1", "primary", 0),
      binding("secondary", "org-1", "mission-1", "secondary", 10)
    ]

    data_sources = [
      data_source("primary", :mission_isolated),
      data_source("secondary", :mission_isolated)
    ]

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: data_sources,
               data_bindings: bindings,
               source_health_statuses: [
                 source_health_status("primary", :unavailable, :source_connection_failed)
               ],
               now: ~U[2026-06-21 12:00:10Z]
             )

    assert resolved.binding.binding_id == "secondary"
    assert resolved.data_source.data_source_id == "secondary"
    assert resolved.source_selection.eligible_candidate_count == 1

    assert [
             %{
               binding_id: "primary",
               decision: :rejected,
               reasons: [:source_unavailable],
               source_health: :unavailable,
               source_health_reason: :source_connection_failed,
               source_health_freshness: :fresh
             },
             %{binding_id: "secondary", decision: :selected}
           ] = resolved.source_selection.candidates
  end

  test "allows current bindings when unavailable source health is stale" do
    bindings = [
      binding("primary", "org-1", "mission-1", "primary", 0),
      binding("secondary", "org-1", "mission-1", "secondary", 10)
    ]

    data_sources = [
      data_source("primary", :mission_isolated),
      data_source("secondary", :mission_isolated)
    ]

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: data_sources,
               data_bindings: bindings,
               source_health_statuses: [
                 source_health_status("primary", :unavailable, :source_connection_failed,
                   observed_at: ~U[2026-06-21 12:00:00Z],
                   last_seen_at: ~U[2026-06-21 12:00:00Z]
                 )
               ],
               source_health_freshness: %{default_max_age_ms: 1_000},
               now: ~U[2026-06-21 12:00:10Z]
             )

    assert resolved.binding.binding_id == "primary"

    assert [
             %{
               binding_id: "primary",
               decision: :selected,
               reasons: [],
               source_health: :unknown,
               source_health_reason: :source_health_stale,
               source_health_freshness: :stale,
               raw_source_health: :unavailable,
               raw_source_health_reason: :source_connection_failed
             },
             %{binding_id: "secondary", decision: :not_selected, reasons: [:lower_priority]}
           ] = resolved.source_selection.candidates
  end

  test "returns source unavailable warning when every matching current candidate is unavailable" do
    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: [data_source("primary", :mission_isolated)],
               data_bindings: [binding("primary", "org-1", "mission-1", "primary", 0)],
               source_health_statuses: [
                 source_health_status("primary", :unavailable, :source_connection_failed)
               ],
               now: ~U[2026-06-21 12:00:10Z]
             )

    assert warning.code == :source_unavailable
    assert warning.severity == :error
    assert warning.details.binding_id == "primary"
    assert warning.details.data_source_id == "primary"
    assert warning.details.source_health == :unavailable
    assert warning.details.source_health_reason == :source_connection_failed
    assert warning.details.source_health_freshness == :fresh
    assert warning.details.source_selection.eligible_candidate_count == 0
  end

  test "readiness policy can block degraded current binding candidates" do
    bindings = [
      binding("primary", "org-1", "mission-1", "primary", 0),
      binding("secondary", "org-1", "mission-1", "secondary", 10)
    ]

    data_sources = [
      data_source("primary", :mission_isolated),
      data_source("secondary", :mission_isolated)
    ]

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: data_sources,
               data_bindings: bindings,
               source_health_statuses: [
                 source_health_status("primary", :degraded, :source_schema_probe_failed)
               ],
               source_readiness_policy: [
                 policy_id: :strict_ops,
                 block_source_health: [:unavailable, :degraded],
                 block_freshness: [:fresh]
               ],
               now: ~U[2026-06-21 12:00:10Z]
             )

    assert resolved.binding.binding_id == "secondary"

    assert resolved.source_selection.source_readiness_policy == %{
             policy_id: :strict_ops,
             block_source_health: [:unavailable, :degraded],
             block_freshness: [:fresh],
             block_connection_test: [:failed, :blocked]
           }

    assert [
             %{
               binding_id: "primary",
               decision: :rejected,
               reasons: [:source_degraded],
               source_readiness_policy_id: :strict_ops,
               source_health: :degraded,
               source_health_reason: :source_schema_probe_failed,
               source_health_freshness: :fresh
             },
             %{binding_id: "secondary", decision: :selected}
           ] = resolved.source_selection.candidates
  end

  test "readiness policy can require known source health before selection" do
    bindings = [
      binding("primary", "org-1", "mission-1", "primary", 0),
      binding("secondary", "org-1", "mission-1", "secondary", 10)
    ]

    data_sources = [
      data_source("primary", :mission_isolated),
      data_source("secondary", :mission_isolated)
    ]

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: data_sources,
               data_bindings: bindings,
               source_health_statuses: [
                 source_health_status("secondary", :healthy, :source_probe_succeeded)
               ],
               source_readiness_policy: %{
                 "policy_id" => "known-health-required",
                 "block_source_health" => ["unknown"],
                 "block_freshness" => ["missing"]
               },
               now: ~U[2026-06-21 12:00:10Z]
             )

    assert resolved.binding.binding_id == "secondary"

    assert resolved.source_selection.source_readiness_policy == %{
             policy_id: "known_health_required",
             block_source_health: [:unknown],
             block_freshness: [:missing],
             block_connection_test: [:failed, :blocked]
           }

    assert [
             %{
               binding_id: "primary",
               decision: :rejected,
               reasons: [:source_health_unknown],
               source_readiness_policy_id: "known_health_required",
               source_health: :unknown,
               source_health_reason: :source_health_missing,
               source_health_freshness: :missing
             },
             %{binding_id: "secondary", decision: :selected}
           ] = resolved.source_selection.candidates
  end

  test "readiness policy can block candidates with failed connection tests" do
    bindings = [
      binding("primary", "org-1", "mission-1", "primary", 0),
      binding("secondary", "org-1", "mission-1", "secondary", 10)
    ]

    data_sources = [
      data_source("primary", :mission_isolated),
      data_source("secondary", :mission_isolated)
    ]

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: data_sources,
               data_bindings: bindings,
               source_health_statuses: [
                 source_health_status("primary", :healthy, :source_probe_succeeded,
                   payload: %{
                     connection_test_result: "failed",
                     connection_test_kind: "adapter_io",
                     connection_test_message: "Adapter connection test failed."
                   }
                 )
               ],
               now: ~U[2026-06-21 12:00:10Z]
             )

    assert resolved.binding.binding_id == "secondary"

    assert [
             %{
               binding_id: "primary",
               decision: :rejected,
               reasons: [:connection_test_failed],
               source_readiness_policy_id: :default,
               source_health: :healthy,
               source_health_reason: :source_probe_succeeded,
               source_health_freshness: :fresh,
               connection_test_result: "failed",
               connection_test_kind: "adapter_io",
               connection_test_message: "Adapter connection test failed."
             },
             %{binding_id: "secondary", decision: :selected}
           ] = resolved.source_selection.candidates
  end

  test "strict degraded readiness policy returns source degraded warning when no source is ready" do
    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: [data_source("primary", :mission_isolated)],
               data_bindings: [binding("primary", "org-1", "mission-1", "primary", 0)],
               source_health_statuses: [
                 source_health_status("primary", :degraded, :source_schema_probe_failed)
               ],
               source_readiness_policy: [
                 policy_id: :strict_ops,
                 block_source_health: [:unavailable, :degraded],
                 block_freshness: [:fresh]
               ],
               now: ~U[2026-06-21 12:00:10Z]
             )

    assert warning.code == :source_degraded
    assert warning.severity == :error
    assert warning.details.binding_id == "primary"
    assert warning.details.data_source_id == "primary"
    assert warning.details.source_health == :degraded
    assert warning.details.source_health_reason == :source_schema_probe_failed
    assert warning.details.source_health_freshness == :fresh
  end

  test "source-health readiness warnings carry source context and actions" do
    scenarios = [
      %{
        code: :source_unavailable,
        status: source_health_status("primary", :unavailable, :source_connection_failed),
        reasons: [:source_unavailable],
        source_health: :unavailable,
        source_health_reason: :source_connection_failed,
        opts: []
      },
      %{
        code: :source_degraded,
        status: source_health_status("primary", :degraded, :source_schema_probe_failed),
        reasons: [:source_degraded],
        source_health: :degraded,
        source_health_reason: :source_schema_probe_failed,
        opts: [
          source_readiness_policy: [
            policy_id: :strict_ops,
            block_source_health: [:unavailable, :degraded],
            block_freshness: [:fresh]
          ]
        ]
      },
      %{
        code: :source_connection_failed,
        status:
          source_health_status("primary", :healthy, :source_probe_succeeded,
            payload: %{
              connection_test_result: "failed",
              connection_test_kind: "adapter_io",
              connection_test_message: "Adapter connection test failed."
            }
          ),
        reasons: [:connection_test_failed],
        source_health: :healthy,
        source_health_reason: :source_probe_succeeded,
        connection_test_result: "failed",
        connection_test_kind: "adapter_io",
        connection_test_message: "Adapter connection test failed.",
        opts: []
      }
    ]

    for scenario <- scenarios do
      assert {:error, warning} =
               DataSourceRegistry.resolve(
                 source_request(),
                 Keyword.merge(
                   [
                     data_sources: [data_source("primary", :mission_isolated)],
                     data_bindings: [binding("primary", "org-1", "mission-1", "primary", 0)],
                     source_health_statuses: [scenario.status],
                     now: ~U[2026-06-21 12:00:10Z]
                   ],
                   scenario.opts
                 )
               )

      assert warning.code == scenario.code
      assert warning.severity == :error
      assert warning.scope == :dashboard

      assert warning.details.binding_id == "primary"
      assert warning.details.data_source_id == "primary"
      assert warning.details.source_health == scenario.source_health
      assert warning.details.source_health_reason == scenario.source_health_reason
      assert warning.details.source_health_freshness == :fresh
      assert warning.details.connection_test_result == Map.get(scenario, :connection_test_result)
      assert warning.details.connection_test_kind == Map.get(scenario, :connection_test_kind)

      assert warning.details.connection_test_message ==
               Map.get(scenario, :connection_test_message)

      assert %{
               eligible_candidate_count: 0,
               candidates: [%{binding_id: "primary", reasons: reasons}]
             } = warning.details.source_selection

      assert reasons == scenario.reasons

      assert_source_health_warning_actions(warning.details, scenario)
    end
  end

  test "uses explicit source binding context before priority selection" do
    bindings = [
      binding("primary", "org-1", "mission-1", "primary", 0),
      binding("rehearsal", "org-1", "mission-1", "rehearsal", 10)
    ]

    data_sources = [
      data_source("primary", :mission_isolated),
      data_source("rehearsal", :mission_isolated)
    ]

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(
               source_request(data_context: %{realm: :flight, source_binding_id: "rehearsal"}),
               data_sources: data_sources,
               data_bindings: bindings
             )

    assert resolved.binding.binding_id == "rehearsal"
    assert resolved.data_source.data_source_id == "rehearsal"
  end

  test "defaults replay-run source requests to replay realm instead of flight" do
    replay_binding = %DataBinding{
      binding("replay-binding", "org-1", "mission-1", "replay-tsdb", 0)
      | realm: :replay,
        dataset: "replay"
    }

    flight_binding = binding("flight-binding", "org-1", "mission-1", "flight-tsdb", 0)

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(
               source_request(
                 data_context: %{},
                 time_context: %{mode: :replay_run, replay_run_id: "replay-run-1"}
               ),
               data_sources: [
                 data_source("flight-tsdb", :mission_isolated),
                 data_source("replay-tsdb", :mission_isolated)
               ],
               data_bindings: [flight_binding, replay_binding]
             )

    assert resolved.realm == :replay
    assert resolved.dataset == "replay"
    assert resolved.binding.binding_id == "replay-binding"

    assert %{
             requested_realm: :replay,
             requested_time_mode: :replay_run,
             replay_run_id: "replay-run-1",
             selected_source_binding_id: "replay-binding",
             selected_data_source_id: "replay-tsdb"
           } = resolved.source_selection
  end

  test "requires a replay run id for replay-run source requests" do
    assert {:error, warning} =
             DataSourceRegistry.resolve(
               source_request(data_context: %{}, time_context: %{mode: :replay_run})
             )

    assert warning.code == :missing_replay_run_id
    assert warning.severity == :error
    assert warning.message == "Replay source requests require a replay run id"
    assert warning.details.time_mode == :replay_run
    assert warning.details.requested_time_mode == :replay_run
    assert warning.details.realm == :replay

    assert_warning_actions(warning.details, %{
      "logical_source" => "telemetry",
      "realm" => "replay",
      "time_mode" => "replay_run"
    })
  end

  test "rejects replay-run requests that explicitly select flight realm" do
    assert {:error, warning} =
             DataSourceRegistry.resolve(
               source_request(
                 data_context: %{realm: :flight},
                 time_context: %{mode: :replay_run, replay_run_id: "replay-run-1"}
               )
             )

    assert warning.code == :replay_source_required
    assert warning.severity == :error
    assert warning.message == "Replay source requests require a replay realm"
    assert warning.details.realm == :flight
    assert warning.details.replay_run_id == "replay-run-1"

    assert_warning_actions(warning.details, %{
      "logical_source" => "telemetry",
      "realm" => "flight",
      "time_mode" => "replay_run",
      "replay_run_id" => "replay-run-1"
    })
  end

  test "returns replay-specific warning when no replay source binding matches" do
    assert {:error, warning} =
             DataSourceRegistry.resolve(
               source_request(
                 data_context: %{},
                 time_context: %{mode: :replay_run, replay_run_id: "replay-run-1"}
               ),
               data_sources: [data_source("flight-tsdb", :mission_isolated)],
               data_bindings: [binding("flight-binding", "org-1", "mission-1", "flight-tsdb", 0)]
             )

    assert warning.code == :missing_replay_source_binding
    assert warning.severity == :error
    assert warning.message == "No replay source binding matches request"
    assert warning.details.replay_run_id == "replay-run-1"

    assert %{
             requested_realm: :replay,
             requested_time_mode: :replay_run,
             replay_run_id: "replay-run-1",
             candidate_count: 1,
             eligible_candidate_count: 0,
             candidates: [
               %{
                 binding_id: "flight-binding",
                 decision: :rejected,
                 reasons: [:realm_mismatch]
               }
             ]
           } = warning.details.source_selection

    assert_warning_actions(warning.details, %{
      "logical_source" => "telemetry",
      "realm" => "replay",
      "time_mode" => "replay_run",
      "replay_run_id" => "replay-run-1"
    })
  end

  test "replay source readiness warning actions preserve replay run context" do
    replay_binding = %DataBinding{
      binding("replay-binding", "org-1", "mission-1", "replay-tsdb", 0)
      | realm: :replay,
        dataset: "replay"
    }

    assert {:error, warning} =
             DataSourceRegistry.resolve(
               source_request(
                 data_context: %{},
                 time_context: %{mode: :replay_run, replay_run_id: "replay-run-1"}
               ),
               data_sources: [data_source("replay-tsdb", :mission_isolated)],
               data_bindings: [replay_binding],
               source_health_statuses: [
                 source_health_status("replay-tsdb", :unavailable, :replay_source_failed,
                   source_binding_id: "replay-binding",
                   realm: :replay,
                   dataset: "replay",
                   replay_run_id: "replay-run-1"
                 )
               ],
               now: ~U[2026-06-21 12:00:10Z]
             )

    assert warning.code == :source_unavailable
    assert warning.details.replay_run_id == "replay-run-1"
    assert warning.details.source_health_reason == :replay_source_failed

    assert_warning_actions(warning.details, %{
      "logical_source" => "telemetry",
      "data_source_id" => "replay-tsdb",
      "source_binding_id" => "replay-binding",
      "realm" => "replay",
      "time_mode" => "replay_run",
      "replay_run_id" => "replay-run-1"
    })
  end

  test "returns structured warning for missing source binding" do
    request = source_request(data_context: %{realm: :rehearsal})

    assert {:error, warning} =
             DataSourceRegistry.resolve(request, data_sources: [], data_bindings: [])

    assert warning.code == :missing_source_binding
    assert warning.severity == :error

    details = Map.delete(warning.details, :actions)

    assert Map.take(details, [
             :source_request_id,
             :organization_id,
             :mission_id,
             :logical_source,
             :realm,
             :requested_realm
           ]) == %{
             source_request_id: "source-request-1",
             organization_id: "org-1",
             mission_id: "mission-1",
             logical_source: :telemetry,
             realm: :rehearsal,
             requested_realm: :rehearsal
           }

    assert details.source_selection == %{
             strategy: :current_binding,
             source_readiness_policy: %{
               policy_id: :default,
               block_source_health: [:unavailable],
               block_freshness: [:fresh],
               block_connection_test: [:failed, :blocked]
             },
             logical_source: :telemetry,
             requested_realm: :rehearsal,
             candidate_count: 0,
             eligible_candidate_count: 0,
             candidates: []
           }

    assert_warning_actions(warning.details, %{
      "logical_source" => "telemetry",
      "realm" => "rehearsal"
    })
  end

  test "returns structured warning for binding that references an unknown data source" do
    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: [],
               data_bindings: [binding("broken", "org-1", "mission-1", "missing", 0)]
             )

    assert warning.code == :missing_data_source

    details = Map.delete(warning.details, :actions)

    assert Map.take(details, [
             :source_request_id,
             :binding_id,
             :data_source_id,
             :requested_realm
           ]) == %{
             source_request_id: "source-request-1",
             binding_id: "broken",
             data_source_id: "missing",
             requested_realm: :flight
           }

    assert %{
             strategy: :current_binding,
             selected_source_binding_id: "broken",
             candidates: [%{binding_id: "broken", decision: :selected}]
           } = details.source_selection

    assert_warning_actions(warning.details, %{
      "data_source_id" => "missing",
      "source_binding_id" => "broken"
    })
  end

  test "returns structured warning for binding that references a disabled data source" do
    disabled_source = %DataSource{
      data_source("disabled-questdb", :mission_isolated)
      | organization_id: "org-1",
        mission_id: "mission-1",
        status: :disabled,
        disabled_at: ~U[2026-06-21 19:00:00Z]
    }

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: [disabled_source],
               data_bindings: [
                 binding("disabled-binding", "org-1", "mission-1", "disabled-questdb", 0)
               ]
             )

    assert warning.code == :disabled_data_source
    assert warning.severity == :error

    details = Map.delete(warning.details, :actions)

    assert Map.take(details, [
             :source_request_id,
             :binding_id,
             :data_source_id,
             :source_status,
             :disabled_at,
             :requested_realm
           ]) == %{
             source_request_id: "source-request-1",
             binding_id: "disabled-binding",
             data_source_id: "disabled-questdb",
             source_status: :disabled,
             disabled_at: ~U[2026-06-21 19:00:00Z],
             requested_realm: :flight
           }

    assert %{
             strategy: :current_binding,
             selected_source_binding_id: "disabled-binding",
             selected_data_source_id: "disabled-questdb",
             selected_data_source_status: :disabled,
             candidates: [%{binding_id: "disabled-binding", decision: :selected}]
           } = details.source_selection

    assert_warning_actions(warning.details, %{
      "data_source_id" => "disabled-questdb",
      "source_binding_id" => "disabled-binding"
    })
  end

  test "returns structured warning before dispatching unsafe BYO source configuration" do
    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               data_sources: [
                 %DataSource{
                   data_source_id: "unsafe-customer-questdb",
                   owner: :customer,
                   kind: :byo_tsdb,
                   adapter: Cadence.Dashboards.Sources.Telemetry,
                   organization_id: "org-1",
                   isolation_level: :customer_owned,
                   metadata: %{connection: %{api_key: "plaintext"}}
                 }
               ],
               data_bindings: [
                 binding(
                   "unsafe-customer-binding",
                   "org-1",
                   "mission-1",
                   "unsafe-customer-questdb",
                   0
                 )
               ]
             )

    assert warning.code == :invalid_data_source_configuration
    assert warning.severity == :error
    assert warning.details.binding_id == "unsafe-customer-binding"
    assert warning.details.data_source_id == "unsafe-customer-questdb"

    assert %{field: :credentials_ref, message: "must be set for BYO TSDB data sources"} in warning.details.errors

    assert %{
             field: :metadata,
             message: "must not embed credentials or secrets; use credentials_ref"
           } in warning.details.errors
  end

  test "resolves telemetry source facts without frame resolution" do
    test_pid = self()

    latest_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      send(test_pid, :latest_called)
      nil
    end

    history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      send(test_pid, :history_called)
      []
    end

    watermark_fun = fn organization_id, mission_id, point_id, opts ->
      send(test_pid, {:watermark_called, organization_id, mission_id, point_id, opts})

      %{
        complete_through: ~U[2026-06-17 12:00:00Z],
        latest_receipt_time: ~U[2026-06-17 12:00:05Z],
        retention_starts_at: ~U[2026-06-17 11:00:00Z],
        confidence: :best_effort
      }
    end

    assert {:ok, %SourceFacts{} = facts} =
             DataSourceRegistry.facts(source_request(),
               latest_fun: latest_fun,
               history_fun: history_fun,
               watermark_fun: watermark_fun,
               data_revision: "rev-1",
               correction_cursor: "corr-1",
               backfill_cursor: "backfill-1"
             )

    refute_received :latest_called
    refute_received :history_called

    assert_receive {:watermark_called, "org-1", "mission-1", "HK.counter", watermark_opts}
    assert Keyword.get(watermark_opts, :data_source_id) == "managed_questdb_primary"

    assert facts.source_binding.binding_id == "default_flight_telemetry"
    assert facts.data_source.data_source_id == "managed_questdb_primary"
    assert facts.watermark.complete_through == ~U[2026-06-17 12:00:00Z]
    assert facts.data_revision == "rev-1"
    assert facts.correction_cursor == "corr-1"
    assert facts.backfill_cursor == "backfill-1"

    assert %RuntimeCacheKey{layer: :source_result} =
             key =
             SourceFacts.runtime_cache_key(source_request(), facts,
               freshness_policy: %{stale_after_ms: 5_000}
             )

    assert key.parts.source_binding.binding_id == "default_flight_telemetry"
    assert key.parts.data_source.data_source_id == "managed_questdb_primary"
    assert key.parts.watermark_cursor.complete_through == ~U[2026-06-17 12:00:00Z]
    assert key.parts.data_revision == "rev-1"
    assert key.parts.correction_cursor == "corr-1"
    assert key.parts.backfill_cursor == "backfill-1"
  end

  test "resolves limits source facts without frame resolution" do
    test_pid = self()

    latest_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      send(test_pid, :limits_latest_called)
      nil
    end

    history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      send(test_pid, :limits_history_called)
      []
    end

    watermark_fun = fn organization_id, mission_id, point_id, opts ->
      send(test_pid, {:limits_watermark_called, organization_id, mission_id, point_id, opts})

      %{
        complete_through: ~U[2026-06-17 13:00:00Z],
        latest_receipt_time: ~U[2026-06-17 13:00:05Z],
        retention_starts_at: ~U[2026-06-17 11:00:00Z],
        confidence: :best_effort
      }
    end

    request = source_request(logical_source: :limits, sampling: %{mode: :latest_state})

    assert {:ok, %SourceFacts{} = facts} =
             DataSourceRegistry.facts(request,
               latest_fun: latest_fun,
               history_fun: history_fun,
               watermark_fun: watermark_fun
             )

    refute_received :limits_latest_called
    refute_received :limits_history_called

    assert_receive {:limits_watermark_called, "org-1", "mission-1", "HK.counter", watermark_opts}

    assert Keyword.get(watermark_opts, :data_source_id) == "managed_limits_projection"
    assert Keyword.get(watermark_opts, :semantics_mode) == :observed
    assert facts.source_binding.binding_id == "default_flight_limits"
    assert facts.data_source.data_source_id == "managed_limits_projection"
    assert facts.watermark.complete_through == ~U[2026-06-17 13:00:00Z]
  end

  test "resolves operational observable facts without frame resolution" do
    test_pid = self()

    request =
      source_request(
        logical_source: :operational_observables,
        observables: ["commanding.queue_depth"],
        sampling: %{mode: :latest}
      )

    assert {:ok, %SourceFacts{} = facts} =
             DataSourceRegistry.facts(request,
               command_queue_revision_fun: fn organization_id, mission_id, opts ->
                 send(
                   test_pid,
                   {:command_queue_revision_called, organization_id, mission_id, opts}
                 )

                 "command-queue-rev-1"
               end,
               command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
                 send(test_pid, :command_queue_entries_called)
                 []
               end,
               correction_cursor: "ops-corr-1",
               backfill_cursor: "ops-backfill-1"
             )

    assert_receive {:command_queue_revision_called, "org-1", "mission-1", revision_opts}
    assert Keyword.get(revision_opts, :data_source_id) == "managed_operational_observables"
    refute_received :command_queue_entries_called

    assert facts.source_binding.binding_id == "default_flight_operational_observables"
    assert facts.data_source.data_source_id == "managed_operational_observables"
    assert facts.watermark == nil
    assert facts.data_revision == "command-queue-rev-1"
    assert facts.correction_cursor == "ops-corr-1"
    assert facts.backfill_cursor == "ops-backfill-1"

    assert %RuntimeCacheKey{layer: :source_result} =
             key =
             SourceFacts.runtime_cache_key(request, facts,
               freshness_policy: %{stale_after_ms: 5_000}
             )

    assert key.parts.source_binding.binding_id == "default_flight_operational_observables"
    assert key.parts.data_source.data_source_id == "managed_operational_observables"
    refute Map.has_key?(key.parts, :watermark_cursor)
    assert key.parts.freshness_policy == %{stale_after_ms: 5_000}
    assert key.parts.data_revision == "command-queue-rev-1"
    assert key.parts.correction_cursor == "ops-corr-1"
    assert key.parts.backfill_cursor == "ops-backfill-1"

    changed_policy_key =
      SourceFacts.runtime_cache_key(request, facts, freshness_policy: %{stale_after_ms: 30_000})

    changed_revision_key =
      SourceFacts.runtime_cache_key(request, %{facts | data_revision: "ops-rev-2"},
        freshness_policy: %{stale_after_ms: 5_000}
      )

    assert changed_policy_key.fingerprint != key.fingerprint
    assert changed_revision_key.fingerprint != key.fingerprint
  end

  test "resolves mixed operational observable facts from source-owned family revisions" do
    test_pid = self()

    request =
      source_request(
        logical_source: :operational_observables,
        observables: [
          "contacts.phase",
          "comms.transport.connection_state",
          "comms.transport.downlink_bitrate",
          "commanding.queue_depth",
          "ingress.processing_latency_ms"
        ],
        sampling: %{mode: :latest}
      )

    opts = [
      contact_phase_revision_fun: fn organization_id, mission_id, revision_opts ->
        send(test_pid, {:contact_phase_revision, organization_id, mission_id, revision_opts})
        "contact-rev-1"
      end,
      connection_state_revision_fun: fn organization_id, mission_id, revision_opts ->
        send(test_pid, {:connection_state_revision, organization_id, mission_id, revision_opts})
        "connection-rev-1"
      end,
      transport_bitrate_revision_fun: fn organization_id, mission_id, revision_opts ->
        send(test_pid, {:transport_bitrate_revision, organization_id, mission_id, revision_opts})
        "bitrate-rev-1"
      end,
      command_queue_revision_fun: fn organization_id, mission_id, revision_opts ->
        send(test_pid, {:command_queue_revision, organization_id, mission_id, revision_opts})
        "command-rev-1"
      end,
      ingress_processing_latency_revision_fun: fn organization_id, mission_id, revision_opts ->
        send(test_pid, {:ingress_revision, organization_id, mission_id, revision_opts})
        "ingress-rev-1"
      end,
      scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
        send(test_pid, :scheduled_contacts_called)
        []
      end,
      realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
        send(test_pid, :realized_contacts_called)
        []
      end,
      transports_fun: fn _organization_id, _mission_id, _opts ->
        send(test_pid, :transports_called)
        []
      end,
      source_endpoints_fun: fn _organization_id, _mission_id, _opts ->
        send(test_pid, :source_endpoints_called)
        []
      end,
      connection_snapshots_fun: fn _organization_id, _mission_id, _opts ->
        send(test_pid, :connection_snapshots_called)
        []
      end,
      transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
        send(test_pid, :transport_metric_snapshots_called)
        []
      end,
      command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
        send(test_pid, :command_queue_entries_called)
        []
      end,
      runtime_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
        send(test_pid, :runtime_metric_snapshots_called)
        []
      end
    ]

    assert {:ok, %SourceFacts{} = facts} = DataSourceRegistry.facts(request, opts)

    assert_receive {:contact_phase_revision, "org-1", "mission-1", contact_opts}
    assert_receive {:connection_state_revision, "org-1", "mission-1", connection_opts}
    assert_receive {:transport_bitrate_revision, "org-1", "mission-1", bitrate_opts}
    assert_receive {:command_queue_revision, "org-1", "mission-1", command_opts}
    assert_receive {:ingress_revision, "org-1", "mission-1", ingress_opts}

    assert Keyword.get(contact_opts, :data_source_id) == "managed_operational_observables"
    assert Keyword.get(connection_opts, :data_source_id) == "managed_operational_observables"
    assert Keyword.get(bitrate_opts, :data_source_id) == "managed_operational_observables"
    assert Keyword.get(command_opts, :data_source_id) == "managed_operational_observables"
    assert Keyword.get(ingress_opts, :data_source_id) == "managed_operational_observables"

    refute_received :scheduled_contacts_called
    refute_received :realized_contacts_called
    refute_received :transports_called
    refute_received :source_endpoints_called
    refute_received :connection_snapshots_called
    refute_received :transport_metric_snapshots_called
    refute_received :command_queue_entries_called
    refute_received :runtime_metric_snapshots_called

    assert String.starts_with?(facts.data_revision, "operational_latest:")

    assert {:ok, %SourceFacts{} = changed_facts} =
             DataSourceRegistry.facts(
               request,
               Keyword.replace!(
                 opts,
                 :transport_bitrate_revision_fun,
                 fn _organization_id, _mission_id, _revision_opts -> "bitrate-rev-2" end
               )
             )

    assert changed_facts.data_revision != facts.data_revision
  end

  defp source_request(overrides \\ []) do
    attrs =
      %{
        request_id: "source-request-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        logical_source: :telemetry,
        observables: ["HK.counter"],
        data_context: %{realm: :flight},
        sampling: %{mode: :raw_series}
      }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  defp binding(binding_id, organization_id, mission_id, data_source_id, priority) do
    %DataBinding{
      binding_id: binding_id,
      organization_id: organization_id,
      mission_id: mission_id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: binding_id,
      priority: priority
    }
  end

  defp data_source(data_source_id, isolation_level) do
    data_source = %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      isolation_level: isolation_level
    }

    case isolation_level do
      :org_isolated ->
        %DataSource{data_source | organization_id: "org-1"}

      :mission_isolated ->
        %DataSource{data_source | organization_id: "org-1", mission_id: "mission-1"}

      _other ->
        data_source
    end
  end

  defp source_health_status(data_source_id, source_health, reason, opts \\ []) do
    observed_at = Keyword.get(opts, :observed_at, ~U[2026-06-21 12:00:00Z])
    last_seen_at = Keyword.get(opts, :last_seen_at, observed_at)
    payload = Keyword.get(opts, :payload, %{})

    %SourceHealthStatus{
      source_health_key:
        SourceHealthEvent.source_health_key(%{
          organization_id: "org-1",
          mission_id: "mission-1",
          logical_source: :telemetry,
          data_source_id: data_source_id,
          source_binding_id: Keyword.get(opts, :source_binding_id),
          realm: Keyword.get(opts, :realm),
          replay_run_id: Keyword.get(opts, :replay_run_id),
          dataset: Keyword.get(opts, :dataset)
        }),
      source_health_event_id: "source-health-event-#{data_source_id}",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :telemetry,
      data_source_id: data_source_id,
      source_binding_id: Keyword.get(opts, :source_binding_id),
      realm: Keyword.get(opts, :realm),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      dataset: Keyword.get(opts, :dataset),
      source_health: source_health,
      reason: reason,
      observed_at: observed_at,
      last_seen_at: last_seen_at,
      transition_count: 1,
      payload: payload
    }
  end

  defp assert_warning_actions(details, source_query) do
    assert actions = details.actions

    assert Enum.any?(actions, fn
             %DashboardAction{target: :source_health, kind: :invoke, source: :warning} = action ->
               action_query_contains?(action, source_query)

             _other ->
               false
           end)

    assert Enum.any?(actions, fn
             %DashboardAction{target: :source_inventory, kind: :invoke, source: :warning} = action ->
               action_query_contains?(action, source_query)

             _other ->
               false
           end)

    assert Enum.any?(actions, fn
             %DashboardAction{
               target: :telemetry_explore,
               kind: :invoke,
               source: :warning,
               query: %{"point_id" => "HK.counter"}
             } ->
               true

             _other ->
               false
           end)
  end

  defp action_query_contains?(%DashboardAction{query: query}, expected) do
    Map.take(query, Map.keys(expected)) == expected
  end

  defp assert_source_health_warning_actions(details, scenario) do
    assert actions = details.actions

    for target <- [:source_health, :source_inventory] do
      assert Enum.any?(actions, &source_health_warning_action?(&1, target, details))
    end

    if Map.has_key?(scenario, :connection_test_result) do
      assert Enum.any?(actions, &connection_test_action?(&1, scenario))
    end
  end

  defp source_health_warning_action?(
         %DashboardAction{target: target, kind: :invoke, source: :warning} = action,
         expected_target,
         details
       ) do
    target == expected_target and action.route == nil and
      source_health_warning_context?(action, details) and
      source_health_warning_query?(action, details)
  end

  defp source_health_warning_action?(_action, _target, _details), do: false

  defp source_health_warning_context?(%DashboardAction{context: context}, details) do
    context.source_request_id == details.source_request_id and
      context.logical_source == details.logical_source and
      context.data_source_id == details.data_source_id and
      context.source_binding_id == details.binding_id and
      context.realm == details.realm
  end

  defp source_health_warning_query?(%DashboardAction{query: query}, details) do
    query["logical_source"] == Atom.to_string(details.logical_source) and
      query["data_source_id"] == details.data_source_id and
      query["source_binding_id"] == details.binding_id and
      query["realm"] == Atom.to_string(details.realm)
  end

  defp connection_test_action?(%DashboardAction{target: :source_health, query: query}, scenario) do
    query["connection_test_result"] == scenario.connection_test_result and
      query["connection_test_kind"] == scenario.connection_test_kind and
      query["connection_test_message"] == scenario.connection_test_message
  end

  defp connection_test_action?(_action, _scenario), do: false
end
