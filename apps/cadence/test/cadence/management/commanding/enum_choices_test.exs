defmodule Cadence.Management.Commanding.EnumChoicesTest do
  use Cadence.DataCase, async: false

  alias Cadence.ExactCommandAuthoringFixtures, as: Fixtures
  alias Cadence.MissionModels.RevisionRow

  setup do
    c = Fixtures.fixture!()

    extra = """
      - name: SET_HEATER_SETPOINT
        opcode: 18
        parameters:
          - name: heater_id
            data_type: uint
            required: true
            valid_values: [1, 2]
            bit_offset: 0
            bit_length: 8
          - name: setpoint
            data_type: float
            required: true
            bit_offset: 8
            bit_length: 32
    """

    %{c | model: Fixtures.activate!(c.org, c.mission, extra)}
  end

  test "validation accepts members and rejects encodable nonmembers", c do
    for value <- [1, 2, "1"] do
      values = %{"heater_id" => value, "setpoint" => 18.5}
      assert {:ok, held} = Fixtures.validate(c, "SET_HEATER_SETPOINT", values)
      assert held.request.argument_values == values
    end

    for value <- [0, 3, "3"] do
      assert {:error, {:invalid_command_argument_choice, "heater_id"}} =
               Fixtures.validate(c, "SET_HEATER_SETPOINT", %{
                 "heater_id" => value,
                 "setpoint" => 18.5
               })
    end
  end

  test "missing or excessive enum metadata refuses validation", c do
    row = Repo.get!(RevisionRow, c.model.revision_id)
    declarations = row.revision_document["value"]["declarations"]

    type_id =
      Enum.find_value(declarations, fn {id, declaration} ->
        enumerations = get_in(declaration, ["definition", "enumerations"])

        if is_list(enumerations) and Enum.map(enumerations, & &1["value"]) == [1, 2], do: id
      end)

    for entries <- [
          nil,
          [],
          Enum.map(0..1024, &%{"label" => Integer.to_string(&1), "value" => &1})
        ] do
      document =
        put_in(
          row.revision_document,
          ["value", "declarations", type_id, "definition", "enumerations"],
          entries
        )

      Repo.update!(Ecto.Changeset.change(row, revision_document: document))

      assert {:error, :command_argument_choices_unavailable} =
               Fixtures.validate(c, "SET_HEATER_SETPOINT", %{"heater_id" => 1, "setpoint" => 18.5})
    end
  end
end
