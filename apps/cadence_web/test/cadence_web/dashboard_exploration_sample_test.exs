defmodule CadenceWeb.DashboardExplorationSampleTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.ResolutionContext
  alias Cadence.Dashboards.Sources.Telemetry
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources
  alias Cadence.Reads.Dashboards.{Exploration, ExplorationSnapshot}
  alias Cadence.Telemetry.{HistoryStore, PhysicalSampleQuery}
  alias Cadence.TestSupport.PhysicalSampleFixtures
  alias CadenceWeb.TestFixtures

  @checker Path.expand(
             "../../../../frontend/modules/dashboards-and-exploration/src/features/exploration/producer-contract-check.mjs",
             __DIR__
           )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    for id <- ["inspection-old", "inspection-new"] do
      assert {:ok, _} =
               DataSources.persist_data_source(%DataSource{
                 data_source_id: id,
                 adapter: Telemetry,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 isolation_level: :mission_isolated,
                 capabilities: %{latest?: true, range_scan?: true, bounded_history?: true},
                 metadata: %{endpoint_ref: "private-execution-marker"}
               })
    end

    assert {:ok, binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding_id: "inspection-binding",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 realm: :flight,
                 data_source_id: "inspection-old",
                 dataset: "flight"
               },
               occurred_at: ~U[2026-09-08 11:00:00Z]
             )

    sample =
      PhysicalSampleFixtures.sample(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id
      })

    storage =
      sample.provenance["storage"]
      |> Map.merge(%{
        "organization_id" => org.organization_id,
        "data_source_id" => "inspection-old",
        "binding_id" => binding.binding_id
      })

    sample = %{sample | provenance: %{"storage" => storage, "secret" => "private-sample-marker"}}

    %{
      org: org.organization_id,
      mission: mission.mission_id,
      spacecraft: spacecraft.spacecraft_id,
      scope: scope,
      binding: binding,
      sample: sample
    }
  end

  test "authorized selection reads the physical record under the exact query scope and clocks",
       c do
    params =
      Map.merge(selection(), %{
        "time_mode" => "range",
        "time_axis" => "generation_time",
        "from" => "2026-09-08T12:00:00.000000Z",
        "to" => "2026-09-08T12:00:01.000000Z",
        "spacecraft_id" => c.spacecraft,
        "selected_time" => "2026-09-08T12:00:05.654321Z"
      })

    assert {:ok, read} = Exploration.load(c.scope, c.mission, params, runtime(c))
    assert {:ok, sample} = read.selected_sample
    assert sample == c.sample
    assert sample.provenance["storage"]["validity_state"] == "superseded"
    assert_received {:physical_read, query}
    assert query.organization_id == c.org and query.mission_id == c.mission
    assert query.spacecraft_id == c.spacecraft
    assert query.from_observed_at == ~U[2026-09-08 12:00:00.000000Z]
    assert query.to_observed_at == ~U[2026-09-08 12:00:01.000000Z]
    assert query.receipt_time == ~U[2026-09-08 12:00:05.654321Z]
    assert query.from_receipt_time == nil
  end

  test "a source binding changed during the row query cannot redirect physical inspection", c do
    latest = fn _, _, _, _ ->
      assert {:ok, _} =
               DataSources.persist_data_binding(%{c.binding | data_source_id: "inspection-new"},
                 occurred_at: ~U[2026-09-08 12:30:00Z]
               )

      c.sample
    end

    assert {:ok, read} =
             Exploration.load(c.scope, c.mission, selection(), runtime(c, latest: latest))

    assert {:ok, sample} = read.selected_sample
    assert sample == c.sample
    assert_received {:physical_read, %{data_source_id: "inspection-old"}}
    assert {:ok, current} = DataSources.fetch_data_binding(c.binding.binding_id)
    assert current.data_source_id == "inspection-new"
    [planned] = read.result.planned_source_requests
    assert [captured] = read.result.resolved_bindings_by_request_id[planned.request_id]
    assert captured.binding.binding_version == c.binding.binding_version
    assert captured.data_source.data_source_id == "inspection-old"
  end

  test "physical records outside the visible history page remain inspectable", c do
    opts = runtime(c, history: fn _, _, _, _ -> {:ok, []} end)

    params =
      Map.merge(selection(), %{
        "time_mode" => "range",
        "from" => "2026-09-08T12:00:00Z",
        "to" => "2026-09-08T12:01:00Z",
        "limit" => "1"
      })

    assert {:ok, %{selected_sample: {:ok, sample}}} =
             Exploration.load(c.scope, c.mission, params, opts)

    assert sample == c.sample
    assert_received {:physical_read, %{sample_id: "sample-physical"}}
  end

  test "unselected queries and rejected authorization never inspect samples", c do
    assert {:ok, %{selected_sample: :not_selected}} =
             Exploration.load(c.scope, c.mission, %{"point_id" => "HK.counter"}, runtime(c))

    refute_received {:physical_read, _}

    assert {:error, :unavailable} =
             Exploration.load(
               %{c.scope | organization_membership: nil},
               c.mission,
               selection(),
               runtime(c)
             )

    refute_received {:physical_read, _}
  end

  test "missing bindings and unavailable reads do not erase successful query rows", c do
    assert {:ok, missing} =
             Exploration.load(
               c.scope,
               c.mission,
               Map.put(selection(), "source_binding_id", "missing"),
               runtime(c)
             )

    assert missing.selected_sample == {:error, :missing_physical_sample_binding}
    refute_received {:physical_read, _}

    assert {:ok, unavailable} =
             Exploration.load(
               c.scope,
               c.mission,
               selection(),
               runtime(c, read: fn _, _ -> {:error, :offline} end)
             )

    assert unavailable.selected_sample == {:error, :physical_sample_unavailable}
    assert [_] = unavailable.result.frames_by_placement["exploration"].primary
  end

  test "browser projection omits retained bindings and raw sample provenance", c do
    assert {:ok, model} = ExplorationSnapshot.load(c.scope, c.mission, selection(), runtime(c))
    assert model.version == 3
    assert model.inspection.status == "ready"
    assert model.inspection.sample.record.validity_state == "superseded"
    json = Jason.encode!(model)
    refute json =~ "private-execution-marker"
    refute json =~ "private-sample-marker"
    refute json =~ "resolved_bindings"
    refute json =~ "history_store_policy"

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               [
                 "--no-warnings",
                 @checker,
                 Jason.encode!([model])
               ],
               stderr_to_stdout: true
             )

    assert output =~ "Vue renderer contract passed"
  end

  test "historical rows keep their source through global limiting and physical selection", c do
    assert {:ok, _} =
             DataSources.persist_data_binding(
               %{c.binding | data_source_id: "inspection-new"},
               occurred_at: ~U[2026-09-08 12:00:06Z]
             )

    storage = Map.put(c.sample.provenance["storage"], "data_source_id", "inspection-new")

    newer = %{
      c.sample
      | receipt_time: ~U[2026-09-08 12:00:07.654321Z],
        engineering_value: 99.0,
        provenance: %{"storage" => storage}
    }

    samples = [c.sample, newer]

    opts =
      runtime(c,
        history: fn _, _, _, opts ->
          source = Keyword.fetch!(opts, :data_source_id)
          {:ok, Enum.filter(samples, &(&1.provenance["storage"]["data_source_id"] == source))}
        end,
        read: fn query, _ ->
          case Enum.filter(samples, &PhysicalSampleQuery.matches?(query, &1, c.org)) do
            [sample] -> {:ok, %{organization_id: c.org, sample: sample}}
            [] -> {:error, :not_found}
            _ -> {:error, :ambiguous_physical_sample}
          end
        end
      )

    params = %{
      "point_id" => "HK.counter",
      "time_mode" => "range",
      "limit" => "1",
      "from" => "2026-09-08T12:00:00Z",
      "to" => "2026-09-08T12:01:00Z",
      "time_axis" => "receipt_time",
      "order" => "desc"
    }

    assert {:ok, model} = ExplorationSnapshot.load(c.scope, c.mission, params, opts)
    assert [row] = model.rows
    assert model.limited
    assert row.sample_id == c.sample.sample_id
    assert row.value == 99.0
    assert row.source.data_source_id == "inspection-new"
    assert row.source.source_binding_id == c.binding.binding_id

    selected =
      Map.merge(params, %{
        "sample_id" => row.sample_id,
        "selected_time" => row.time,
        "selected_data_source_id" => row.source.data_source_id,
        "selected_source_binding_id" => row.source.source_binding_id,
        "realm" => row.source.realm
      })

    assert {:ok, selected_read} = Exploration.load(c.scope, c.mission, selected, opts)
    assert selected_read.selected_sample == {:ok, newer}
    assert {:ok, detail} = ExplorationSnapshot.load(c.scope, c.mission, selected, opts)
    assert detail.inspection.status == "ready"
    assert detail.inspection.sample.source.data_source_id == "inspection-new"
    assert detail.inspection.sample.receipt_time == row.time
    assert detail.inspection.sample.engineering_value.text == "99.0"
    assert detail.rows == model.rows
    assert_received {:physical_read, %{data_source_id: "inspection-new"}}
    assert_received {:physical_read, %{data_source_id: "inspection-new"}}
    refute_received {:physical_read, _}

    unavailable = Map.put(selected, "selected_data_source_id", "never-executed")
    assert {:ok, rejected} = ExplorationSnapshot.load(c.scope, c.mission, unavailable, opts)
    assert rejected.rows == model.rows
    assert rejected.inspection.status == "unavailable"
    refute_received {:physical_read, _}

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", @checker, Jason.encode!([model, detail])],
               stderr_to_stdout: true
             )

    assert output =~ "Vue renderer contract passed"
  end

  def fetch_sample(query, opts), do: Keyword.fetch!(opts, :read).(query, opts)

  defp runtime(c, overrides \\ []) do
    parent = self()

    read =
      Keyword.get(overrides, :read, fn query, _ ->
        if PhysicalSampleQuery.matches?(query, c.sample, c.org),
          do: {:ok, %{organization_id: c.org, sample: c.sample}},
          else: {:error, :not_found}
      end)

    policy =
      HistoryStore.policy(
        module: __MODULE__,
        read: fn query, opts ->
          send(parent, {:physical_read, query})
          read.(query, opts)
        end
      )

    context =
      ResolutionContext.new!(
        persisted?: true,
        validate_dashboard_contract?: true,
        source_execution_opts: [
          source_circuit_breaker?: false,
          record_source_health_events?: false,
          source_watermark_events?: false,
          source_health_events?: false,
          source_opts: %{
            telemetry: [
              history_store_policy: policy,
              latest_fun: Keyword.get(overrides, :latest, fn _, _, _, _ -> c.sample end),
              history_fun:
                Keyword.get(overrides, :history, fn _, _, _, _ -> {:ok, [c.sample]} end),
              watermark_fun: fn _, _, _, _ -> nil end
            ]
          }
        ]
      )

    [resolution_context: context, now: ~U[2026-09-08 12:10:00Z]]
  end

  defp selection, do: %{"point_id" => "HK.counter", "sample_id" => "sample-physical"}
end
