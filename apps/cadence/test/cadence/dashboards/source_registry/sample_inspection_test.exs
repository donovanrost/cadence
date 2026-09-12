defmodule Cadence.Dashboards.SourceRegistry.SampleInspectionTest do
  use Cadence.DataCase, async: false

  import Cadence.Dashboards.SourceRegistryFixtures,
    only: [source_request: 1, data_binding: 1, data_source: 2]

  alias Cadence.Dashboards.{
    DataContext,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    SourceCircuitBreaker,
    SourceExecutionPolicy,
    SourceRegistry,
    TimeContext
  }

  alias Cadence.Dashboards.Sources.Telemetry
  alias Cadence.Management.DataSources.Credentials
  alias Cadence.Telemetry.{HistoryStore, PhysicalSampleQuery, Sample}
  alias Cadence.Telemetry.HistoryStore.Noop
  alias Cadence.TestSupport.PhysicalSampleFixtures

  test "dispatches through the captured backend and does not re-resolve a mutable default" do
    test_pid = self()

    policy =
      HistoryStore.policy(
        module: __MODULE__,
        read: fn query, opts ->
          send(test_pid, {:read, query, opts})
          {:ok, %{organization_id: "org-1", sample: sample()}}
        end
      )

    opts = opts(policy) ++ [data_bindings: [data_binding("new-default")], data_sources: []]

    assert {:ok, actual} =
             SourceRegistry.inspect_sample(request(), resolved_binding(), selection(), opts)

    assert actual == sample()
    assert_received {:read, query, read_opts}
    assert query.source_binding_id == "flight-telemetry"
    assert query.data_source_id == "source-1"
    assert query.sample_id == "sample-physical"
    refute Keyword.has_key?(read_opts, :current_value_store_policy)
    refute Keyword.has_key?(read_opts, :selection_view)
  end

  test "rejects binding ownership and explicit source mismatches before execution" do
    for resolved <- [
          put_in(resolved_binding().binding.organization_id, "foreign-org"),
          put_in(resolved_binding().data_source.mission_id, "foreign-mission"),
          put_in(resolved_binding().binding.data_source_id, "different-source"),
          %{resolved_binding() | dataset: "other-dataset"}
        ] do
      assert {:error, :physical_sample_context_mismatch} =
               SourceRegistry.inspect_sample(
                 request(),
                 resolved,
                 selection(),
                 custom_opts(fn _, _ -> flunk("must not execute") end)
               )
    end

    request = %{
      request()
      | data_context: %DataContext{realm: :flight, source_binding_id: "new-binding"}
    }

    assert {:error, :physical_sample_context_mismatch} =
             SourceRegistry.inspect_sample(
               request,
               resolved_binding(),
               selection(),
               custom_opts(fn _, _ -> flunk("must not execute") end)
             )
  end

  test "honors adapter override and validates returned physical context" do
    test_pid = self()

    opts =
      custom_opts(fn query, adapter_opts ->
        send(test_pid, {:adapter_called, query, adapter_opts[:source_binding]})
        {:ok, sample()}
      end)

    assert {:ok, _} =
             SourceRegistry.inspect_sample(request(), resolved_binding(), selection(), opts)

    assert_received {:adapter_called, _, resolved}
    assert resolved == resolved_binding()

    for invalid <- [
          %{sample() | mission_id: "other-mission"},
          %{sample() | point_id: "other-point"},
          %{sample() | receipt_time: ~U[2026-09-08 14:00:00Z]},
          put_in(sample().provenance["storage"]["organization_id"], "foreign-org"),
          put_in(sample().provenance["storage"]["organization_id"], nil),
          put_in(sample().provenance["storage"]["binding_id"], "other-binding")
        ] do
      assert {:error, :physical_sample_context_mismatch} =
               SourceRegistry.inspect_sample(
                 request(),
                 resolved_binding(),
                 selection(),
                 custom_opts(fn _, _ -> {:ok, invalid} end)
               )
    end
  end

  test "unsupported adapter and backend capabilities do not fall back" do
    opts = Keyword.put(opts(), :adapters, %{telemetry: String})

    assert {:error, :unsupported_sample_inspection} =
             SourceRegistry.inspect_sample(request(), resolved_binding(), selection(), opts)

    assert {:error, :unsupported_sample_inspection} =
             SourceRegistry.inspect_sample(
               request(),
               resolved_binding(),
               selection(),
               opts(HistoryStore.policy(module: Noop))
             )

    {:ok, query} = PhysicalSampleQuery.new(PhysicalSampleFixtures.attrs())
    assert {:error, :missing_physical_sample_policy} = Telemetry.inspect_sample(query, [])
  end

  test "missing and ambiguous records remain distinct from unavailable and malformed results" do
    for reason <- [:not_found, :ambiguous_physical_sample] do
      assert {:error, ^reason} =
               SourceRegistry.inspect_sample(
                 request(),
                 resolved_binding(),
                 selection(),
                 custom_opts(fn _, _ -> {:error, reason} end)
               )
    end

    assert {:error, :physical_sample_unavailable} =
             SourceRegistry.inspect_sample(
               request(),
               resolved_binding(),
               selection(),
               custom_opts(fn _, _ ->
                 {:error, %{headers: [{"authorization", "private-token"}]}}
               end)
             )

    assert {:error, :invalid_physical_sample_result} =
             SourceRegistry.inspect_sample(
               request(),
               resolved_binding(),
               selection(),
               custom_opts(fn _, _ -> {:ok, %{secret: "private-token"}} end)
             )
  end

  test "exceptions and exits are contained and finite timeouts kill the pending read" do
    for fun <- [
          fn _, _ -> raise "private-token" end,
          fn _, _ -> exit(:private_token) end,
          fn _, _ -> throw(:private_token) end,
          fn _, _ -> Process.exit(self(), :kill) end
        ] do
      assert {:error, :physical_sample_unavailable} =
               SourceRegistry.inspect_sample(
                 request(),
                 resolved_binding(),
                 selection(),
                 custom_opts(fun)
               )
    end

    test_pid = self()

    opts =
      custom_opts(fn _, _ ->
        send(test_pid, {:pending_read, self()})

        receive do
          :never -> {:ok, sample()}
        end
      end)
      |> Keyword.put(:source_execution_timeout_ms, 50)

    assert {:error, :physical_sample_timeout} =
             SourceRegistry.inspect_sample(request(), resolved_binding(), selection(), opts)

    assert_received {:pending_read, pid}
    refute Process.alive?(pid)
  end

  test "inspection observes and updates the source circuit breaker" do
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})
    test_pid = self()

    opts =
      custom_opts(fn _, _ ->
        send(test_pid, :attempt)
        {:error, :offline}
      end)
      |> Keyword.merge(
        source_circuit_breaker?: true,
        source_circuit_breaker: breaker,
        source_circuit_failure_threshold: 1,
        source_circuit_backoff_ms: 60_000,
        now_ms: 1_000
      )

    assert {:error, :physical_sample_unavailable} =
             SourceRegistry.inspect_sample(request(), resolved_binding(), selection(), opts)

    assert_received :attempt

    assert {:error, :physical_sample_source_degraded} =
             SourceRegistry.inspect_sample(request(), resolved_binding(), selection(), opts)

    refute_received :attempt
  end

  test "a disappearing caller does not leave an inspection worker running" do
    test_pid = self()

    read_opts =
      custom_opts(fn _, _ ->
        send(test_pid, {:inspection_worker, self()})

        receive do
          :never -> {:ok, sample()}
        end
      end)
      |> Keyword.put(:source_execution_timeout_ms, :infinity)

    caller =
      spawn(fn ->
        SourceRegistry.inspect_sample(request(), resolved_binding(), selection(), read_opts)
      end)

    assert_receive {:inspection_worker, worker}
    monitor = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}
    refute Process.alive?(worker)
  end

  test "resolves binding credentials into execution options without returning material" do
    persist_mission_scope("org-1", "mission-1")
    ref = "secret://org-1/dashboard/source-1"

    assert {:ok, _, _} =
             Credentials.register_reference(%{
               credentials_ref: ref,
               organization_id: "org-1",
               mission_id: "mission-1",
               data_source_id: "source-1",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "test",
               metadata: %{}
             })

    resolved = put_in(resolved_binding().data_source.credentials_ref, ref)

    resolved = %{
      resolved
      | data_source: %{resolved.data_source | organization_id: "org-1", mission_id: "mission-1"}
    }

    test_pid = self()

    resolver = fn credential, context ->
      send(
        test_pid,
        {:credential, credential.credentials_ref,
         Keyword.take(context, [:organization_id, :mission_id, :data_source_id])}
      )

      {:ok, %{http_endpoint: "https://source.example.test", bearer_token: "private-token"}}
    end

    policy =
      HistoryStore.policy(
        module: __MODULE__,
        read: fn _, read_opts ->
          send(
            test_pid,
            {:connection, read_opts[:http_endpoint], read_opts[:headers],
             read_opts[:source_connection_profile]}
          )

          {:ok, %{organization_id: "org-1", sample: sample()}}
        end
      )

    opts = opts(policy) ++ [credential_material_resolver: resolver, credential_configuration: %{}]
    assert {:ok, actual} = SourceRegistry.inspect_sample(request(), resolved, selection(), opts)
    refute inspect(actual) =~ "private-token"
    assert_received {:credential, ^ref, context}

    assert Map.new(context) == %{
             organization_id: "org-1",
             mission_id: "mission-1",
             data_source_id: "source-1"
           }

    assert_received {:connection, "https://source.example.test", headers, profile}
    assert {"authorization", "Bearer private-token"} in headers
    refute inspect(profile) =~ "private-token"

    failed_opts =
      Keyword.put(opts, :credential_material_resolver, fn _, _ -> {:error, :private_token} end)

    assert {:error, :physical_sample_unavailable} =
             SourceRegistry.inspect_sample(request(), resolved, selection(), failed_opts)

    refute_received {:connection, _, _, _}
  end

  def fetch_sample(query, opts), do: Keyword.fetch!(opts, :read).(query, opts)

  test "segment inspection requires one physical match, not just the first successful source" do
    first = resolved_binding()

    second = %{
      first
      | binding: %{first.binding | data_source_id: "source-2"},
        data_source: %{first.data_source | data_source_id: "source-2"}
    }

    selected = put_in(sample().provenance["storage"]["data_source_id"], "source-2")

    one_match =
      custom_opts(fn query, _ ->
        if query.data_source_id == "source-1", do: {:error, :not_found}, else: {:ok, selected}
      end)

    assert {:ok, ^selected} =
             SourceRegistry.inspect_samples(request(), [first, second], selection(), one_match)

    both_match =
      custom_opts(fn query, _ ->
        {:ok, put_in(sample().provenance["storage"]["data_source_id"], query.data_source_id)}
      end)

    assert {:error, :ambiguous_physical_sample} =
             SourceRegistry.inspect_samples(request(), [first, second], selection(), both_match)

    assert {:ok, _} =
             SourceRegistry.inspect_samples(request(), [first, first], selection(), both_match)

    uncertain =
      custom_opts(fn query, _ ->
        if query.data_source_id == "source-1", do: {:ok, sample()}, else: {:error, :offline}
      end)

    assert {:error, :physical_sample_unavailable} =
             SourceRegistry.inspect_samples(request(), [first, second], selection(), uncertain)
  end

  test "missing or excessive captured segments cannot trigger a default lookup" do
    read_opts =
      custom_opts(fn _, _ -> flunk("must not inspect without bounded binding evidence") end)

    for bindings <- [[], nil, List.duplicate(resolved_binding(), 65)] do
      assert {:error, :missing_physical_sample_binding} =
               SourceRegistry.inspect_samples(request(), bindings, selection(), read_opts)
    end
  end

  test "a whole-selection timeout bounds a source with a longer individual execution policy" do
    parent = self()

    read_opts =
      custom_opts(fn _, _ ->
        send(parent, {:bounded_segment, self()})

        receive do
          :never -> {:error, :not_found}
        end
      end)
      |> Keyword.put(:source_execution_defaults, %{
        SourceExecutionPolicy.default()
        | timeout_ms: 250
      })

    binding =
      put_in(resolved_binding().binding.metadata, %{dashboard_policy: %{timeout_ms: 10_000}})

    started = System.monotonic_time(:millisecond)

    assert {:error, :physical_sample_timeout} =
             SourceRegistry.inspect_samples(request(), [binding], selection(), read_opts)

    assert System.monotonic_time(:millisecond) - started < 2_000
    assert_received {:bounded_segment, worker}
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}
  end

  def inspect_sample(query, opts) do
    case Keyword.fetch!(opts, :inspect_fun).(query, opts) do
      {:ok, %Sample{} = sample} ->
        {:ok, %{organization_id: sample.provenance["storage"]["organization_id"], sample: sample}}

      result ->
        result
    end
  end

  defp opts(policy \\ HistoryStore.policy(module: __MODULE__)) do
    [
      source_opts: %{telemetry: [history_store_policy: policy]},
      source_execution_defaults: SourceExecutionPolicy.default(),
      source_circuit_breaker?: false,
      record_source_health_events?: false
    ]
  end

  defp custom_opts(fun),
    do:
      opts()
      |> Keyword.put(:adapters, %{telemetry: __MODULE__})
      |> Keyword.put(:source_opts, %{telemetry: [inspect_fun: fun]})

  defp request,
    do:
      source_request(
        time_context: %TimeContext{
          mode: :range,
          axis: :receipt_time,
          from: ~U[2026-09-08 12:00:00Z],
          to: ~U[2026-09-08 12:01:00Z]
        }
      )
      |> PlannedSourceRequest.normalize()

  defp resolved_binding,
    do: %ResolvedSourceBinding{
      binding: data_binding("source-1"),
      data_source: data_source("source-1", []),
      realm: :flight,
      dataset: "flight"
    }

  defp selection, do: %{point_id: "HK.counter", sample_id: "sample-physical"}

  defp sample do
    sample = PhysicalSampleFixtures.sample(%{mission_id: "mission-1"})

    %{
      sample
      | provenance: %{
          "storage" => %{
            "organization_id" => "org-1",
            "realm" => "flight",
            "data_source_id" => "source-1",
            "binding_id" => "flight-telemetry",
            "validity_state" => "superseded"
          }
        }
    }
  end
end
