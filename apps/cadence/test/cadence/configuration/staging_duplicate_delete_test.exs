defmodule Cadence.Configuration.StagingDuplicateDeleteTest do
  @moduledoc "A delete its author already staged adds nothing (fe-setup, qa: a double-submitted Archive)."
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Control.Configuration

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("dupdel")
    alice = member_scope(org, :member, "Alice")

    {:ok, staged} = Configuration.stage(alice, mission, %{summary: "Add"}, [station_op("Troll")])

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test change: add a station",
        expected_version: staged.version
      })

    [id] = staged.entity_ids
    %{org: org, mission: mission, alice: alice, bob: member_scope(org, :member, "Bob"), id: id}
  end

  test "the same author's second identical delete answers with the change that holds it", c do
    delete = [%{kind: "ground_station", action: :delete, entity_id: c.id}]

    assert {:ok, first} = Configuration.stage(c.alice, c.mission, %{summary: "Archive"}, delete)
    assert first.staged_count == 1

    assert {:ok, again} = Configuration.stage(c.alice, c.mission, %{summary: "Archive"}, delete)

    assert %{change_id: change_id, staged_count: 1, version: version, entity_ids: [id]} = again
    assert {change_id, version, id} == {first.change_id, first.version, c.id}
  end

  test "another author's delete of it is still refused", c do
    delete = [%{kind: "ground_station", action: :delete, entity_id: c.id}]
    assert {:ok, _staged} = Configuration.stage(c.alice, c.mission, %{summary: "Archive"}, delete)

    assert {:error, {:path_already_staged, _overlap}} =
             Configuration.stage(c.bob, c.mission, %{summary: "Archive"}, delete)
  end
end
