defmodule Cadence.MissionModels.RevisionHistoryTest do
  use Cadence.DataCase, async: true

  import Cadence.ConfigurationFixtures, only: [configuration_mission: 1]

  alias Cadence.Activations.{BindingSetActivation, BindingSetActivationRow}
  alias Cadence.Catalog.{FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.MissionModels

  @activated_at ~U[2026-11-28 12:00:00.000000Z]
  @first_receipt ~U[2026-11-28 12:00:00.000001Z]
  @second_receipt ~U[2026-11-28 12:00:00.000003Z]

  test "the runtime receipt makes a fleet effective at the exact microsecond" do
    scope = configuration_mission("revision-history")
    org = scope.organization_id
    mission = scope.mission_id

    first = activate(scope, 1, %{"craft-a" => "model-1", "craft-b" => "model-2"})
    assert MissionModels.revision_at(org, mission, "craft-a", @activated_at) == nil
    assert MissionModels.revisions_at(org, mission, @activated_at) == %{}

    receive_generation(first, @first_receipt)
    second = activate(scope, 2, %{"craft-a" => "model-3", "craft-c" => "model-2"})
    receive_generation(second, @second_receipt)
    activate(scope, 3, %{"craft-a" => "pending-model"})

    before_switch = DateTime.add(@second_receipt, -1, :microsecond)
    later = DateTime.add(@second_receipt, 1, :day)

    for at <- [@first_receipt, before_switch] do
      assert MissionModels.revision_at(org, mission, "craft-a", at) == "model-1"

      assert MissionModels.revisions_at(org, mission, at) == %{
               "model-1" => ["craft-a"],
               "model-2" => ["craft-b"]
             }
    end

    for at <- [@second_receipt, later] do
      assert MissionModels.revision_at(org, mission, "craft-a", at) == "model-3"
      assert MissionModels.revision_at(org, mission, "craft-b", at) == nil

      assert MissionModels.revisions_at(org, mission, at) == %{
               "model-2" => ["craft-c"],
               "model-3" => ["craft-a"]
             }
    end
  end

  test "equal receipt times select the newer generation within the requested mission and organization" do
    scope = configuration_mission("same-time")
    outside = configuration_mission("other-mission")
    org = scope.organization_id
    mission = scope.mission_id

    scope |> activate(1, %{"craft" => "old"}) |> receive_generation(@first_receipt)
    scope |> activate(2, %{"craft" => "new"}) |> receive_generation(@first_receipt)
    outside |> activate(1, %{"craft" => "foreign"}) |> receive_generation(@first_receipt)

    assert MissionModels.revision_at(org, mission, "craft", @first_receipt) == "new"
    assert MissionModels.revisions_at(org, mission, @first_receipt) == %{"new" => ["craft"]}

    assert MissionModels.revision_at(outside.organization_id, mission, "craft", @first_receipt) ==
             nil

    assert MissionModels.revisions_at(org, outside.mission_id, @first_receipt) == %{}
  end

  test "both reads use one bounded statement under a generic plan at 100 and 1,000 craft" do
    Repo.query!("SET LOCAL plan_cache_mode = force_generic_plan")

    for size <- [100, 1_000] do
      scope = configuration_mission("history-#{size}")
      org = scope.organization_id
      mission = scope.mission_id

      assignments =
        Map.new(1..size, fn i ->
          {"craft-#{i}", if(i <= div(size, 2), do: "left", else: "right")}
        end)

      for generation <- 1..2 do
        historical =
          Map.new(assignments, fn {craft, revision} ->
            {craft, "#{revision}-#{generation}"}
          end)

        at = DateTime.add(@first_receipt, generation - 3, :microsecond)
        scope |> activate(generation, historical) |> receive_generation(at)
      end

      scope |> activate(3, assignments) |> receive_generation(@first_receipt)

      assert {"left", single_query} =
               with_one_query(fn ->
                 MissionModels.revision_at(org, mission, "craft-1", @first_receipt)
               end)

      assert {%{"left" => left, "right" => right}, fleet_query} =
               with_one_query(fn -> MissionModels.revisions_at(org, mission, @first_receipt) end)

      if size == 1_000 do
        assert_bounded_plan(:revisions_at, fleet_query)
        assert_bounded_plan(:revision_at, single_query)
      end

      assert Enum.sort(left ++ right) == Enum.sort(Map.keys(assignments))
      assert length(left) == div(size, 2)
      assert length(right) == div(size, 2)
      assert Enum.all?(left, &(assignments[&1] == "left"))
      assert Enum.all?(right, &(assignments[&1] == "right"))
    end
  end

  defp activate(scope, generation, assignments) do
    entries = Map.new(assignments, fn {id, revision} -> {id, fleet_entry(id, revision)} end)
    {:ok, fleet} = FleetSnapshot.store(scope.mission_id, entries)

    %{
      organization_id: scope.organization_id,
      mission_id: scope.mission_id,
      binding_set_id: "history-binding-set",
      binding_set_version: generation,
      activated_at: @activated_at,
      generation: generation,
      metadata: FleetSnapshot.metadata(fleet, %{})
    }
    |> BindingSetActivation.new()
    |> BindingSetActivationRow.changeset()
    |> Repo.insert!()
  end

  defp fleet_entry(id, revision) do
    %{
      "catalog_revision_id" => "catalog",
      "commanding_enabled" => false,
      "document" => %{SpacecraftConfigurationInput.empty() | "catalog_revision_id" => "catalog"},
      "mission_model" => %{"revision_id" => revision},
      "source_endpoint_ids" => ["source-#{id}"]
    }
  end

  defp receive_generation(activation, at) do
    receipt =
      activation
      |> Map.take([
        :organization_id,
        :mission_id,
        :activation_id,
        :generation,
        :binding_set_id,
        :binding_set_version
      ])
      |> Map.put(:applied_at, DateTime.to_naive(at))

    assert {1, nil} = Repo.insert_all("mission_generation_receipts", [receipt])
  end

  defp with_one_query(fun) do
    owner = self()
    handler = make_ref()

    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if self() == owner, do: send(owner, {handler, metadata})
        end,
        nil
      )

    try do
      result = fun.()
      assert_receive {^handler, query}
      refute_received {^handler, _}
      {result, query}
    after
      :telemetry.detach(handler)
    end
  end

  defp assert_bounded_plan(read, %{query: sql, params: params}) do
    Repo.query!("PREPARE revision_history_probe AS " <> sql)

    try do
      # PostgreSQL's EXECUTE utility statement takes literal arguments. Quote the
      # captured binds in PostgreSQL to replay the exact named statement.
      %{rows: [[explain]]} =
        Repo.query!(
          """
          SELECT 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON, TIMING OFF) EXECUTE revision_history_probe('
            || string_agg(quote_literal(value), ', ' ORDER BY position) || ')'
          FROM unnest($1::text[]) WITH ORDINALITY AS parameters(value, position)
          """,
          [Enum.map(params, &to_string/1)]
        )

      %{rows: [[[%{"Plan" => plan}]]]} = Repo.query!(explain)
      assert init_plan?(plan), "#{read} must resolve the fleet hash in an init plan"

      buffers = plan["Shared Hit Blocks"] + plan["Shared Read Blocks"]

      # A scoped membership scan plus keyed entry reads touch a few thousand blocks.
      # This allows spare capacity for cold pages and index depth without a wall-time cap.
      assert buffers < 30_000, "#{read} touched #{buffers} shared buffers"
    after
      Repo.query!("DEALLOCATE revision_history_probe")
    end
  end

  defp init_plan?(%{"Parent Relationship" => "InitPlan"}), do: true
  defp init_plan?(plan), do: Enum.any?(Map.get(plan, "Plans", []), &init_plan?/1)
end
