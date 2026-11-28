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
    mission = Keyword.get(opts, :mission, @mission)

    :ok =
      SemanticObservations.persist_many([
        transition(
          @org,
          mission,
          craft,
          parameter,
          {:normal, :critical},
          DateTime.add(@t0, 1),
          "open-#{mission}-#{parameter}-#{craft}"
        )
      ])
  end

  defp retire(live, ref \\ "activation-2", mission \\ @mission),
    do: SemanticObservations.retire_rules(@org, mission, live, ref, @applied)

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
    assert {:ok, %{episodes: 0, states: 0}} = retire([], "activation-3")

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
end
