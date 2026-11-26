defmodule Cadence.ContactPlanning.FleetPlanningScaleTest do
  use Cadence.DataCase, async: false

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates,
    FleetOptimizer,
    FleetPlanningPolicies,
    FleetPlanningRuns,
    FleetPlanningStarts
  }

  alias Cadence.FleetStartFixtures, as: Fixtures
  alias Cadence.PolicyReviewer
  alias Cadence.SpacecraftStore.SpacecraftRow

  @moduletag timeout: 600_000
  @moduletag sandbox_ownership_timeout: 600_000
  @start ~U[2030-07-17 04:00:00.000000Z]
  @week_seconds 7 * 24 * 3_600

  setup do: Fixtures.setup_start()

  @tag :scale
  @tag timeout: 1_800_000
  test "500 spacecraft at four daily contacts start 14,000 requirements", context do
    warm_fk_plans(context)
    assert_scale_start(context, 500)
  end

  @tag :scale
  @tag timeout: 1_800_000
  test "1,000 spacecraft at four daily contacts start 28,000 requirements", context do
    assert_scale_start(context, 1_000)
  end

  test "the requirement safety bound refuses a start with a clear code", context do
    for index <- 1..3 do
      assert {:ok, _, _} =
               ContactRequirements.create(
                 context.scope,
                 context.mission_id,
                 Fixtures.requirement_attrs(%{contact_intent: "extra-#{index}"})
               )
    end

    previous = Application.get_env(:cadence, :fleet_planning_requirement_limit)
    Application.put_env(:cadence, :fleet_planning_requirement_limit, 3)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cadence, :fleet_planning_requirement_limit, previous),
        else: Application.delete_env(:cadence, :fleet_planning_requirement_limit)
    end)

    assert {:error, :fleet_planning_run_requirement_limit_exceeded} =
             FleetPlanningStarts.preview(context.scope, context.mission_id, Fixtures.params())
  end

  defp assert_scale_start(context, spacecraft_count) do
    assert {:ok, _} =
             ContactRequirements.cancel(
               context.scope,
               context.mission_id,
               context.requirement.contact_requirement_id,
               1,
               "Use recurring demand for this fleet test"
             )

    ids = spacecraft_ids(context, spacecraft_count)
    policy = approve_week_policy(context)

    for hour <- [0, 6, 12, 18] do
      schedule = %{
        "type" => "fixed_interval",
        "anchor_at" => DateTime.to_iso8601(DateTime.add(@start, hour * 3_600)),
        "interval_seconds" => 86_400,
        "window_offset_seconds" => 600,
        "window_duration_seconds" => 1_800
      }

      attrs =
        Fixtures.template_attrs(%{
          target_document: %{"kind" => "spacecraft_ids", "spacecraft_ids" => ids},
          schedule_document: schedule,
          catch_up_policy_document: %{
            "maximum_occurrences_per_run" => 7,
            "maximum_lookback_seconds" => 86_400
          }
        })

      assert {:ok, _, _} =
               ContactRequirementTemplates.create(context.admin, context.mission_id, attrs)
    end

    params = %{
      "fleet_run" => %{
        "horizon_start" => DateTime.to_iso8601(@start),
        "horizon_end" => @start |> DateTime.add(@week_seconds) |> DateTime.to_iso8601(),
        "include_recurring" => true
      }
    }

    expected = spacecraft_count * 4 * 7
    assert {:ok, review} = FleetPlanningStarts.preview(context.scope, context.mission_id, params)
    assert review.occurrence_count == expected

    {start_ms, start_peak_bytes, start_result} =
      measure(fn ->
        FleetPlanningStarts.create(
          context.scope,
          context.mission_id,
          Map.put(params, "evidence", review.evidence)
        )
      end)

    assert {:ok, run, refs} = start_result

    assert run.input_document["requirement_count"] == expected
    assert run.input_document["template_materialization"]["created_count"] == expected
    refute Map.has_key?(run.input_document, "requirements")
    assert byte_size(:erlang.term_to_binary(run.input_document)) < 256 * 1_024
    assert length(refs) == expected

    assert length(
             FleetPlanningRuns.list_requirement_refs(
               context.organization_id,
               context.mission_id,
               run.fleet_planning_run_id
             )
           ) == expected

    versions =
      refs
      |> Stream.chunk_every(500)
      |> Enum.flat_map(fn batch ->
        ids = Enum.map(batch, & &1.contact_requirement_id)
        found = ContactRequirements.fetch_many(context.organization_id, context.mission_id, ids)
        Enum.map(batch, fn ref -> found |> Map.fetch!(ref.contact_requirement_id) |> elem(1) end)
      end)

    {optimizer_ms, optimizer_peak_bytes, optimization} =
      measure(fn -> FleetOptimizer.optimize(versions, [], policy, now: @start) end)

    assert {:ok, result} = optimization
    assert map_size(result.coverage_by_requirement) == expected

    IO.puts(
      "fleet scale #{spacecraft_count}: start_ms=#{start_ms} start_process_peak_bytes=#{start_peak_bytes} " <>
        "optimizer_no_opportunities_ms=#{optimizer_ms} optimizer_process_peak_bytes=#{optimizer_peak_bytes}"
    )
  end

  defp measure(fun) do
    owner = self()
    sampler = Task.async(fn -> sample_peak(owner, 0) end)
    started = System.monotonic_time(:millisecond)
    result = fun.()
    elapsed = System.monotonic_time(:millisecond) - started
    send(sampler.pid, :stop)
    {elapsed, Task.await(sampler, 5_000), result}
  end

  defp sample_peak(owner, previous) do
    current =
      case Process.info(owner, :memory) do
        {:memory, bytes} -> max(previous, bytes)
        nil -> previous
      end

    receive do
      :stop -> current
    after
      100 -> sample_peak(owner, current)
    end
  end

  defp warm_fk_plans(context) do
    [[backend]] = Repo.query!("SELECT pg_backend_pid()").rows
    at = DateTime.add(@start, -86_400)
    until = DateTime.add(at, 3_600)

    attrs =
      Fixtures.template_attrs(%{
        target_document: %{
          "kind" => "spacecraft_ids",
          "spacecraft_ids" => [context.craft.spacecraft_id]
        },
        schedule_document: %{
          "type" => "fixed_interval",
          "anchor_at" => DateTime.to_iso8601(at),
          "interval_seconds" => 86_400,
          "window_offset_seconds" => 600,
          "window_duration_seconds" => 1_800
        },
        catch_up_policy_document: %{
          "maximum_occurrences_per_run" => 1,
          "maximum_lookback_seconds" => 86_400
        }
      })

    assert {:ok, template, version} =
             ContactRequirementTemplates.create(context.admin, context.mission_id, attrs)

    assert {:ok, [%{status: :created}]} =
             ContactRequirementTemplates.materialize(
               context.scope,
               context.mission_id,
               template.contact_requirement_template_id,
               at,
               until
             )

    assert {:ok, _run, [_ref]} =
             FleetPlanningRuns.create(context.scope, context.mission_id, %{
               horizon_start: at,
               horizon_end: until,
               trigger_kind: :manual
             })

    assert {:ok, _} =
             ContactRequirementTemplates.pause(
               context.admin,
               context.mission_id,
               template.contact_requirement_template_id,
               version.version,
               "Warm backend test"
             )

    assert Repo.query!("SELECT pg_backend_pid()").rows == [[backend]]
  end

  defp spacecraft_ids(context, count) do
    ids = for number <- 2..count, do: "craft-fleet-scale-#{number}"
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    ids
    |> Enum.map(fn id ->
      %{
        spacecraft_id: id,
        organization_id: context.organization_id,
        mission_id: context.mission_id,
        display_name: id,
        metadata: %{},
        lifecycle_state: "active",
        inserted_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(&Repo.insert_all(SpacecraftRow, &1))

    [context.craft.spacecraft_id | ids]
  end

  defp approve_week_policy(context) do
    attrs =
      Fixtures.policy_attrs()
      |> update_in([:horizon_document], &Map.put(&1, "max_horizon_seconds", @week_seconds))

    assert {:ok, _, version} =
             FleetPlanningPolicies.version(
               context.admin,
               context.mission_id,
               context.policy.fleet_planning_policy_id,
               1,
               attrs
             )

    assert {:ok, _, _, _} =
             FleetPlanningPolicies.approve(
               PolicyReviewer.reviewer(context.admin),
               context.mission_id,
               context.policy.fleet_planning_policy_id,
               version.version,
               version.content_sha256,
               "Scale planning boundary"
             )

    version
  end
end
