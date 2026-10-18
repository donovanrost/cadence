defmodule CadenceWeb.DashboardExecutionDiagnosticsTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope

  alias Cadence.Dashboards.{
    Diagnostics,
    DocumentCodec,
    Documents,
    ResolutionContext,
    RuntimeCache
  }

  alias Cadence.Dashboards.RuntimeInvalidation.Event
  alias Cadence.Reads.Dashboards.ExecutionDiagnostics
  alias Cadence.Telemetry.{RuntimeHealth, Sample}
  alias CadenceWeb.TestFixtures

  @checker Path.expand(
             "../../../../frontend/modules/dashboards-and-exploration/src/features/execution-diagnostics/producer-contract-check.mjs",
             __DIR__
           )

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    base = DocumentCodec.load!(@fixture)
    [placement] = base.placements

    placement = %{
      placement
      | widget_def: %{
          placement.widget_def
          | binding: Map.put(placement.widget_def.binding, :overlays, [])
        }
    }

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "diagnostics-" <> Ecto.UUID.generate(),
        placements: [placement]
    }

    assert {:ok, document} = Documents.persist(org.organization_id, document)
    cache = start_supervised!({RuntimeCache, name: nil})
    health = start_supervised!({RuntimeHealth, name: nil, event_route: make_ref()})
    parent = self()

    context =
      ResolutionContext.new!(
        runtime_cache: cache,
        plan_cache?: true,
        source_result_cache?: true,
        frame_cache?: true,
        validate_dashboard_contract?: true,
        source_execution_opts: [
          source_health_events?: false,
          record_source_health_events?: false,
          source_watermark_events?: false,
          freshness_now: ~U[2026-09-07 00:00:02Z],
          source_opts: %{
            telemetry: [
              latest_fun: fn org, mission, point, _opts ->
                send(parent, {:diagnostic_source, org, mission, point})

                %Sample{
                  sample_id: "sample-secret",
                  mission_id: mission,
                  spacecraft_id: "sc_001",
                  point_id: point,
                  point_name: point,
                  packet_definition_id: "packet-1",
                  packet_definition_version: 1,
                  packet_id: "packet-1",
                  evidence_id: "evidence-secret",
                  raw_value: 28.4,
                  engineering_value: 28.4,
                  quality_state: :good,
                  generation_time: ~U[2026-09-07 00:00:00Z],
                  receipt_time: ~U[2026-09-07 00:00:01Z],
                  provenance: %{authorization: "source-credential-secret"}
                }
              end,
              watermark_fun: fn _, _, _, _ -> nil end
            ]
          }
        ]
      )

    opts = [
      resolution_context: context,
      runtime_health: health,
      runtime: %{scope_context: %{primary: %{kind: :spacecraft, mode: :one, ids: ["sc_001"]}}}
    ]

    %{
      org: org,
      user: user,
      mission: mission,
      scope: scope,
      document: document,
      opts: opts,
      health: health
    }
  end

  test "only published definitions are inspected and real plan, request, frame, cache and source evidence is projected",
       c do
    assert {:error, :unavailable} = load(c)
    refute_received {:diagnostic_source, _, _, _}
    publish(c)
    assert {:ok, first} = load(c)
    assert first.version == 2
    assert first.document_version == 1

    assert Enum.map(first.collections, & &1.id) ==
             ~w(plan requests frames cache source_execution refresh invalidation)

    for id <- ~w(plan requests frames cache source_execution),
        do: assert(collection(first, id).rows != [])

    assert [%{status: "planned", details: details}] = collection(first, "requests").rows
    assert Enum.find(details, &(&1.key == "observables")).value == "tlm.hk.battery_voltage"
    assert_received {:diagnostic_source, org, mission, "tlm.hk.battery_voltage"}
    assert org == c.org.organization_id and mission == c.mission.mission_id

    warnings = Enum.filter(collection(first, "plan").rows, &(&1.kind == "plan_warning"))
    assert warnings != []
    assert Enum.all?(warnings, &(&1.status in ~w(info warning error)))

    assert Enum.find(
             collection(first, "cache").rows,
             &(&1.identity == cache_identity(first, "plan"))
           ).status == "miss"

    assert {:ok, second} = load(c)
    assert_consumer_accepts([first, second])
    assert Enum.any?(collection(second, "cache").rows, &(&1.status == "hit"))
    assert byte_size(Jason.encode!(second)) < 1_048_576

    for secret <- ~w(source-credential-secret sample-secret evidence-secret),
        do: refute(Jason.encode!(second) =~ secret)

    for c <- second.collections,
        row <- c.rows,
        detail <- row.details,
        do: refute(detail.value == 28.4)

    assert {:ok, _} =
             Documents.update(
               org,
               mission,
               c.document.dashboard_id,
               %{c.document | name: "Private draft"},
               expected_version: 1
             )

    assert {:ok, %{name: "Power Latest", document_version: 1}} = load(c)
  end

  test "mission and organization identity and revoked membership are checked before any source executes",
       c do
    publish(c)
    foreign = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(foreign)

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "other"},
          %{c.scope | organization_id: foreign.organization_id}
        ] do
      assert {:error, :unavailable} =
               ExecutionDiagnostics.load(
                 scope,
                 c.mission.mission_id,
                 c.document.dashboard_id,
                 c.opts
               )
    end

    assert {:error, :unavailable} =
             ExecutionDiagnostics.load(
               c.scope,
               mission.mission_id,
               c.document.dashboard_id,
               c.opts
             )

    assert {:error, :unavailable} =
             ExecutionDiagnostics.load(
               c.scope,
               c.mission.mission_id,
               String.duplicate("x", 257),
               c.opts
             )

    refute_received {:diagnostic_source, _, _, _}
  end

  test "recorded decisions remain scoped, bounded and independently available when inspection fails",
       c do
    publish(c)
    for index <- 1..51, do: record(c.document, "decision-#{index}")

    assert {:ok, foreign} =
             Documents.persist(c.org.organization_id, %{
               c.document
               | dashboard_id: "other-dashboard"
             })

    record(foreign, "foreign-decision")
    opts = Keyword.put(c.opts, :resolution_context, :broken_runtime)

    assert {:ok, model} =
             ExecutionDiagnostics.load(
               c.scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               opts
             )

    assert Enum.all?(
             Enum.take(model.collections, 5),
             &(&1.state == "unavailable" and &1.rows == [])
           )

    for id <- ~w(refresh invalidation) do
      assert %{source: "durable", state: "ready", limited: true, rows: rows} =
               collection(model, id)

      assert length(rows) == 50
      refute Enum.any?(rows, &(&1.identity == "foreign-decision"))
    end

    refute Jason.encode!(model) =~ "private-decision-secret"
    assert_consumer_accepts([model])
    refute_received {:diagnostic_source, _, _, _}
  end

  test "local fallback is labeled and a missing local runtime is unavailable, not an empty success",
       c do
    publish(c)
    assert {:ok, model} = load(c)

    assert %{source: "process_local", state: "ready", rows: []} =
             collection(model, "invalidation")

    opts = Keyword.put(c.opts, :runtime_health, :missing_diagnostic_health)

    assert {:ok, model} =
             ExecutionDiagnostics.load(
               c.scope,
               c.mission.mission_id,
               c.document.dashboard_id,
               opts
             )

    assert %{source: nil, state: "unavailable", rows: []} = collection(model, "invalidation")
    assert collection(model, "plan").state == "ready"
    assert_consumer_accepts([model])
  end

  test "populated local fallback excludes foreign and missing scope without exposing raw decisions",
       c do
    publish(c)

    for {org, mission, dashboard} <- [
          {c.org.organization_id, c.mission.mission_id, c.document.dashboard_id},
          {"foreign-org", c.mission.mission_id, c.document.dashboard_id},
          {c.org.organization_id, "foreign-mission", c.document.dashboard_id},
          {c.org.organization_id, c.mission.mission_id, "foreign-dashboard"},
          {nil, c.mission.mission_id, c.document.dashboard_id}
        ] do
      RuntimeHealth.execute(
        c.health,
        [:cadence, :dashboards, :runtime_invalidation, :decision],
        %{invalidated_artifacts: 2},
        %{
          invalidation_event_id: "local-event",
          organization_id: org,
          mission_id: mission,
          dashboard_id: dashboard,
          boundary: :source_watermark_changed,
          decision_status: :filtered,
          refresh_allowed?: false,
          refresh_reason: :stale_for_context,
          decision: %{authorization: "local-private-secret", affected_placement_ids: ["battery"]}
        }
      )
    end

    assert {:ok, model} = load(c)
    assert %{source: "process_local", rows: [row]} = collection(model, "invalidation")
    assert Enum.find(row.details, &(&1.key == "invalidation_event_id")).value == "local-event"
    refute Jason.encode!(model) =~ "local-private-secret"
    assert_consumer_accepts([model])
  end

  defp load(c),
    do: ExecutionDiagnostics.load(c.scope, c.mission.mission_id, c.document.dashboard_id, c.opts)

  defp assert_consumer_accepts(models) do
    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", @checker, Jason.encode!(models)],
               stderr_to_stdout: true
             )

    assert output =~ "contract passed"
  end

  defp publish(c) do
    assert {:ok, _} =
             Documents.publish(
               c.org.organization_id,
               c.mission.mission_id,
               c.document.dashboard_id,
               1,
               expected_version: 1
             )
  end

  defp collection(model, id), do: Enum.find(model.collections, &(&1.id == id))

  defp cache_identity(model, layer) do
    collection(model, "cache").rows
    |> Enum.find(fn row -> Enum.any?(row.details, &(&1.key == "layer" and &1.value == layer)) end)
    |> Map.fetch!(:identity)
  end

  defp record(document, id) do
    event =
      Event.new(
        :source_watermark_changed,
        [:source_result, :frame],
        %{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          logical_source: :telemetry
        },
        %{},
        %{total: 2}
      )

    assert {:ok, _} =
             Diagnostics.record_runtime_invalidation_decision(
               event,
               %{
                 organization_id: document.organization_id,
                 mission_id: document.mission_id,
                 dashboard_id: document.dashboard_id,
                 decision_status: :matched,
                 matches?: true,
                 dashboard_matches?: true,
                 context_matches?: true,
                 context_reason: :matched,
                 refresh_allowed?: false,
                 refresh_reason: :stale_for_context,
                 affected_placement_count: 1,
                 affected_placement_ids: ["battery"],
                 authorization: "private-decision-secret"
               },
               decision_event_id: id
             )
  end
end
