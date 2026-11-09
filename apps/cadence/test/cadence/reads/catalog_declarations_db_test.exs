defmodule Cadence.Reads.CatalogDeclarationsDBTest do
  use Cadence.DataCase, async: false

  alias Cadence.CommandReviewFixtures
  alias Cadence.ExactCommandAuthoringFixtures, as: Fixtures
  alias Cadence.MissionModels
  alias Cadence.Reads.CatalogDeclarations

  @extra """
    - name: SET_LEVEL
      opcode: 20
      parameters:
        - name: level
          data_type: uint
          required: true
          min_value: 0
          max_value: 100
          units: "%"
          bit_offset: 0
          bit_length: 8
  """

  setup do
    c = CommandReviewFixtures.scope!()
    Fixtures.activate!(c.org, c.mission, @extra)
    revision_id = CatalogDeclarations.active_revision_id(c.org, c.mission)
    {:ok, revision} = MissionModels.fetch_revision(c.org, c.mission, revision_id)

    argument_id =
      Enum.find_value(revision.declarations, fn {id, declaration} ->
        if declaration.kind == :command_argument and declaration.name == "level" and
             String.contains?(declaration.qualified_name, "SET_LEVEL"),
           do: id
      end)

    Map.merge(c, %{revision_id: revision_id, argument_id: argument_id})
  end

  test "projects an argument and its type out of the stored revision", c do
    closure = CatalogDeclarations.closure(c.org, c.mission, c.revision_id, [c.argument_id])

    assert map_size(closure) >= 2
    assert %{"kind" => "command_argument"} = closure[c.argument_id]

    assert CatalogDeclarations.argument_facts(closure, c.argument_id) ==
             %{valid_range: %{minimum: 0, maximum: 100}, unit: "%"}
  end

  test "unknown ids and a missing revision project nothing", c do
    assert CatalogDeclarations.closure(c.org, c.mission, c.revision_id, ["nope"]) == %{}
    assert CatalogDeclarations.closure(c.org, c.mission, nil, [c.argument_id]) == %{}
  end
end
