defmodule Cadence.Alarms.RuleRetiredTest do
  @moduledoc """
  A generation that drops a policy retires it (#451 T3b): the policy's open alarm episodes clear
  with cause `rule_retired` (History says `ended: :rule_retired`), its latest alarm states go, and
  the fleet summaries of the spacecraft it was on follow. A policy the generation keeps is
  untouched, a second run (or a second node) writes nothing more, and another mission is never
  reached.
  """
  use Cadence.DataCase, async: false

  import Cadence.TestSupport.SemanticTransitionFixtures

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow, History}
  alias Cadence.SemanticObservations
  alias Cadence.SemanticObservations.{FleetAlarms, LatestAlarmStateRow}

  @org "org-rule-retired"
  @mission "mission-rule-retired"
  @t0 ~U[2026-11-28 12:00:00.000000Z]
  @applied ~U[2026-11-28 13:00:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    persist_mission_scope(@org, "#{@mission}-other")
    :ok
  end

  defp open!(parameter, craft, opts \\ []) do
    :ok = SemanticObservations.persist_many([prepared(parameter, craft, opts)])
  end

  # A batch as the partition of `generation` hands it over (default: the first).
  defp prepared(parameter, craft, opts) do
    mission = Keyword.get(opts, :mission, @mission)

    @org
    |> transition(
      mission,
      craft,
      parameter,
      Keyword.get(opts, :states, {:normal, :critical}),
      DateTime.add(@t0, Keyword.get(opts, :at, 1)),
      "open-#{mission}-#{parameter}-#{craft}-#{Keyword.get(opts, :at, 1)}"
    )
    |> update_in(
      [:observation_context],
      &Map.put(&1, :generation, Keyword.get(opts, :generation, 1))
    )
  end

  defp retire(live, generation \\ 2, mission \\ @mission),
    do:
      SemanticObservations.retire_rules(
        @org,
        mission,
        live,
        "activation-#{generation}",
        @applied,
        generation
      )

  defp episodes(mission \\ @mission) do
    Repo.all(from(e in EpisodeRow, where: e.mission_id == ^mission, order_by: e.episode_id))
  end

  defp states(mission \\ @mission),
    do:
      Repo.all(
        from(s in LatestAlarmStateRow,
          where: s.mission_id == ^mission,
          select: {s.spacecraft_id, s.policy_id}
        )
      )

  test "a dropped policy's open episodes clear with rule_retired, on every spacecraft it ran on" do
    open!("P1", "sc-1")
    open!("P1", "sc-2")
    open!("P2", "sc-1")

    assert {:ok, %{episodes: 2, states: 2}} = retire(["policy-P2"])

    by_parameter = Enum.group_by(episodes(), & &1.parameter_ref)
    assert [%{state: "active"}] = by_parameter["P2"]

    for %{state: state, cleared_at: cleared_at} <- by_parameter["P1"] do
      assert state == "cleared"
      assert cleared_at == @applied
    end

    events = Repo.all(from(e in EpisodeEventRow, where: e.kind == "cleared"))
    assert length(events) == 2
    assert Enum.all?(events, &(&1.payload["cause"] == "rule_retired"))
    assert Enum.all?(events, &String.starts_with?(&1.source_ref, "activation-2:"))
  end

  test "the dropped policy's latest states go, and the fleet summaries follow" do
    open!("P1", "sc-1")
    open!("P1", "sc-2")
    open!("P2", "sc-1")

    assert %{"sc-1" => _, "sc-2" => _} = FleetAlarms.load(@org, @mission)
    assert {:ok, _counts} = retire(["policy-P2"])

    assert states() == [{"sc-1", "policy-P2"}]
    # sc-2 had only the retired policy; sc-1 still alarms on the one the generation keeps.
    assert [{"sc-1", %{}}] = FleetAlarms.load(@org, @mission) |> Map.to_list()
  end

  test "a policy the generation keeps is untouched, and a generation keeping all of them changes nothing" do
    open!("P1", "sc-1")
    assert {:ok, %{episodes: 0, states: 0}} = retire(["policy-P1", "policy-P3"])
    assert [%{state: "active"}] = episodes()
    assert states() == [{"sc-1", "policy-P1"}]
  end

  test "a second run, or the same generation from another node, writes nothing more" do
    open!("P1", "sc-1")

    assert {:ok, %{episodes: 1, states: 1}} = retire([])
    assert {:ok, %{episodes: 0, states: 0}} = retire([])
    assert {:ok, %{episodes: 0, states: 0}} = retire([], 3)

    assert Repo.aggregate(from(e in EpisodeEventRow, where: e.kind == "cleared"), :count) == 1
  end

  test "another mission's episodes and states are never reached" do
    open!("P1", "sc-1")
    open!("P1", "sc-1", mission: "#{@mission}-other")

    assert {:ok, %{episodes: 1, states: 1}} = retire([])

    assert [%{state: "active"}] = episodes("#{@mission}-other")
    assert states("#{@mission}-other") == [{"sc-1", "policy-P1"}]
  end

  test "History says the episode ended because its rule was retired" do
    open!("P1", "sc-1")
    assert {:ok, _counts} = retire([])

    assert %{items: [item]} =
             History.page(@mission, %{spacecraft_id: "sc-1"}, nil, 10, DateTime.add(@applied, 60))

    assert item.ended == :rule_retired
  end

  describe "a batch evaluated under an older generation, persisted after the retirement" do
    test "cannot bring a retired policy's state back or open its episode again" do
      open!("P1", "sc-1")
      open!("P2", "sc-1")

      # Generation 2 keeps P2 only, and has been applied; the projector is still behind.
      assert {:ok, %{episodes: 1, states: 1}} = retire(["policy-P2"], 2)

      # A generation 1 batch for the retired policy arrives late: a new transition and a new craft.
      late = [
        prepared("P1", "sc-1", states: {:critical, :normal}, at: 30, generation: 1),
        prepared("P1", "sc-2", at: 31, generation: 1)
      ]

      assert :ok = SemanticObservations.persist_many(late)

      assert states() == [{"sc-1", "policy-P2"}]
      assert [%{state: "cleared"}] = Enum.filter(episodes(), &(&1.parameter_ref == "P1"))
      assert [] = Enum.filter(episodes(), &(&1.spacecraft_id == "sc-2"))
      assert %{"sc-1" => _} = FleetAlarms.load(@org, @mission)
      refute Map.has_key?(FleetAlarms.load(@org, @mission), "sc-2")
    end

    test "still persists the policies the newer generation keeps" do
      open!("P2", "sc-1")
      assert {:ok, _counts} = retire(["policy-P2"], 2)

      late = prepared("P2", "sc-2", at: 30, generation: 1)
      assert :ok = SemanticObservations.persist_many([late])
      assert Enum.sort(states()) == [{"sc-1", "policy-P2"}, {"sc-2", "policy-P2"}]
    end

    test "a batch of the new generation, or one persisted before the retirement ran, is not dropped" do
      open!("P1", "sc-1")

      # Before the retirement recorded generation 2: a new policy of generation 2 persists.
      assert :ok =
               SemanticObservations.persist_many([prepared("P9", "sc-1", at: 5, generation: 2)])

      assert {:ok, _counts} = retire(["policy-P9"], 2)
      assert Enum.sort(states()) == [{"sc-1", "policy-P9"}]

      # And after it, a generation 2 batch for the same policy.
      assert :ok =
               SemanticObservations.persist_many([prepared("P9", "sc-2", at: 40, generation: 2)])

      assert Enum.sort(states()) == [{"sc-1", "policy-P9"}, {"sc-2", "policy-P9"}]
    end

    test "a retirement of an older generation than the recorded one does nothing" do
      open!("P1", "sc-1")
      assert {:ok, %{episodes: 0, states: 0}} = retire(["policy-P1"], 3)

      assert {:ok, %{episodes: 0, states: 0}} = retire([], 2)
      assert [%{state: "active"}] = episodes()
      assert states() == [{"sc-1", "policy-P1"}]
    end
  end
end
