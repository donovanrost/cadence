defmodule Cadence.Reads.CommandCatalogTest do
  use Cadence.DataCase, async: false

  alias Cadence.CommandReviewFixtures
  alias Cadence.ExactCommandAuthoringFixtures, as: Fixtures
  alias Cadence.Reads.CommandCatalog

  @extra """
    - name: SET_LEVEL
      opcode: 20
      description: Sets the heater level
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
    model = Fixtures.activate!(c.org, c.mission, @extra)
    Map.merge(c, %{ids: model.commands_by_name})
  end

  defp names(%{commands: commands}), do: Enum.map(commands, & &1.name)

  describe "list/3" do
    test "lists every command with hazard flags and the second-GO policy", c do
      assert {:ok, page} = CommandCatalog.list(c.org, c.mission)

      assert Enum.sort(names(page)) == ~w(SET_COUNTER SET_ENUM SET_LEVEL SET_SIGNED)
      assert is_binary(page.revision_id)
      assert page.next_after == nil

      counter = Enum.find(page.commands, &(&1.name == "SET_COUNTER"))
      assert counter.hazardous
      assert counter.second_go_required
      assert counter.argument_count == 2

      signed = Enum.find(page.commands, &(&1.name == "SET_SIGNED"))
      refute signed.second_go_required
    end

    test "filters by q and pages by command id", c do
      assert {:ok, page} = CommandCatalog.list(c.org, c.mission, %{query: " heater "})
      assert names(page) == ["SET_LEVEL"]

      assert {:ok, first} = CommandCatalog.list(c.org, c.mission, %{limit: 3})
      assert length(first.commands) == 3
      assert is_binary(first.next_after)

      assert {:ok, rest} =
               CommandCatalog.list(c.org, c.mission, %{limit: 3, after: first.next_after})

      assert length(rest.commands) == 1
      assert rest.next_after == nil
    end

    test "a mission with nothing active is not_active" do
      other = CommandReviewFixtures.scope!()
      assert {:ok, :not_active} = CommandCatalog.list(other.org, other.mission)
    end
  end

  describe "fetch/3" do
    test "returns arguments with range, unit and enum choices", c do
      assert {:ok, %{command: level}} = CommandCatalog.fetch(c.org, c.mission, c.ids["SET_LEVEL"])

      assert level.description == "Sets the heater level"
      assert [arg] = level.arguments
      assert arg.name == "level"
      assert arg.valid_range == %{minimum: 0, maximum: 100}
      assert arg.unit == "%"

      assert {:ok, %{command: enum}} = CommandCatalog.fetch(c.org, c.mission, c.ids["SET_ENUM"])

      assert [%{type: :enumerated, choices: [%{value: 18_446_744_073_709_551_615}]}] =
               enum.arguments

      assert {:ok, %{command: counter}} =
               CommandCatalog.fetch(c.org, c.mission, c.ids["SET_COUNTER"])

      assert [%{name: "amount", required: true}, %{name: "counter", default_value: default}] =
               counter.arguments

      assert default == 18_446_744_073_709_551_615
    end

    test "an unknown command is command_not_found", c do
      assert {:error, :command_not_found} = CommandCatalog.fetch(c.org, c.mission, "cmd_missing")
    end
  end
end
