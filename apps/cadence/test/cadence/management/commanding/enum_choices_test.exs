defmodule Cadence.Management.Commanding.EnumChoicesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Commanding.RequestValidation
  alias Cadence.ExactCommandAuthoringFixtures, as: Fixtures
  alias Cadence.Management.Commanding.RequestAuthoring
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{RevisionRow, RuntimePlanRow}

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

  test "an existing plan obtains exact catalog choices without rewriting its identity or document",
       c do
    plans = Repo.all(from(p in RuntimePlanRow, where: p.mission_id == ^c.mission))
    command = selected(c, "SET_HEATER_SETPOINT")
    assert command["supported"]
    assert [heater, setpoint] = command["arguments"]
    assert heater["type"] == "enumerated"

    assert heater["choices"] == [
             %{"label" => "1", "value_json" => "1"},
             %{"label" => "2", "value_json" => "2"}
           ]

    assert setpoint["choices"] == []
    assert [counter] = selected(c, "SET_ENUM")["arguments"]

    assert counter["choices"] == [
             %{"label" => "18446744073709551615", "value_json" => "18446744073709551615"}
           ]

    assert Repo.all(from(p in RuntimePlanRow, where: p.mission_id == ^c.mission)) == plans
  end

  test "preview and direct validation accept members and reject encodable nonmembers", c do
    for value <- [1, 2, "1"] do
      values = %{"heater_id" => value, "setpoint" => 18.5}

      assert {:ok, held} =
               RequestAuthoring.preview(
                 c.scope,
                 c.mission,
                 Fixtures.input(c, "SET_HEATER_SETPOINT", values)
               )

      assert held.request.argument_values == values
      assert {:ok, _} = RequestValidation.validate_and_enrich(held.request)

      assert {:error, {:invalid_command_argument_choice, "heater_id"}} =
               RequestValidation.validate_and_enrich(%{
                 held.request
                 | argument_values: Map.put(values, "heater_id", 3)
               })
    end

    for value <- [0, 3, "3"] do
      assert {:error, {:invalid_command_argument_choice, "heater_id"}} =
               RequestAuthoring.preview(
                 c.scope,
                 c.mission,
                 Fixtures.input(c, "SET_HEATER_SETPOINT", %{
                   "heater_id" => value,
                   "setpoint" => 18.5
                 })
               )
    end
  end

  test "choice projections require the pinned revision, scope and argument identity", c do
    [heater | _] = selected(c, "SET_HEATER_SETPOINT")["arguments"]
    ids = [heater["id"]]

    assert {:ok, choices} =
             MissionModels.command_argument_choices(c.org, c.mission, c.model.revision_id, ids)

    assert Map.fetch!(choices, heater["id"]) == [%{label: "1", value: 1}, %{label: "2", value: 2}]

    for {org, mission, revision, arguments} <- [
          {"foreign", c.mission, c.model.revision_id, ids},
          {c.org, "foreign", c.model.revision_id, ids},
          {c.org, c.mission, "foreign", ids},
          {c.org, c.mission, c.model.revision_id, ["missing"]}
        ] do
      assert {:error, :command_argument_choices_unavailable} =
               MissionModels.command_argument_choices(org, mission, revision, arguments)
    end
  end

  test "missing or excessive enum metadata disables preparation", c do
    row = Repo.get!(RevisionRow, c.model.revision_id)
    [heater | _] = selected(c, "SET_HEATER_SETPOINT")["arguments"]
    declarations = row.revision_document["value"]["declarations"]
    reference = Enum.find(declarations[heater["id"]]["references"], &(&1["role"] == "type"))
    type_id = reference["resolved_id"]

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
      refute selected(c, "SET_HEATER_SETPOINT")["supported"]

      assert {:error, :command_argument_choices_unavailable} =
               MissionModels.command_argument_choices(c.org, c.mission, c.model.revision_id, [
                 heater["id"]
               ])
    end
  end

  defp selected(c, name) do
    {:ok, catalog} =
      RequestAuthoring.load(c.scope, c.mission, %{"command" => c.model.commands_by_name[name]})

    catalog["selected_command"]
  end
end
