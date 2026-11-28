defmodule Cadence.Commanding.Groups.ValidationTest do
  use Cadence.DataCase, async: false

  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.Groups.Validation
  alias Cadence.CommandReviewFixtures
  alias Cadence.ExactCommandAuthoringFixtures, as: Fixtures

  setup do
    c = CommandReviewFixtures.scope!()
    model = Fixtures.activate!(c.org, c.mission)

    for id <- ~w(sc-a sc-b) do
      {:ok, _} =
        Cadence.SpacecraftStore.persist_spacecraft(
          c.org,
          Cadence.Spacecraft.new(%{
            spacecraft_id: id,
            organization_id: c.org,
            mission_id: c.mission,
            display_name: String.upcase(id)
          })
        )

      CommandAuthoringFixtures.target!(c.org, c.mission, %{
        spacecraft_id: id,
        display_name: String.upcase(id)
      })
    end

    Map.merge(c, %{
      ids: model.commands_by_name,
      actor: %{"actor_kind" => "user", "user_id" => "u-1"}
    })
  end

  defp draft(targets, commands),
    do: %{targets: Enum.map(targets, &%{spacecraft_id: &1}), commands: commands, priority: 3}

  defp cmd(c, name, args), do: %{command_id: c.ids[name], argument_values: args}

  test "validates every target x command member against one snapshot", c do
    draft =
      draft(~w(sc-a sc-b), [
        cmd(c, "SET_SIGNED", %{"counter" => -1}),
        cmd(c, "SET_COUNTER", %{"amount" => 2})
      ])

    assert {:ok, result} = Validation.validate(c.org, c.mission, c.actor, draft)
    assert result.valid?

    assert Enum.map(result.members, &{&1.target_index, &1.position}) ==
             [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

    assert [%{name: "SC-A", scid: 7}, %{name: "SC-B"}] = result.targets

    # SET_COUNTER is hazardous in the fixture catalog.
    assert %{second_go_required: true, reasons: [%{key: :hazardous_command}]} = result.policy
    assert is_binary(result.digest)
  end

  test "the digest is stable across runs and changes with the inputs", c do
    draft = draft(~w(sc-a), [cmd(c, "SET_SIGNED", %{"counter" => 5})])
    {:ok, first} = Validation.validate(c.org, c.mission, c.actor, draft)
    {:ok, second} = Validation.validate(c.org, c.mission, c.actor, draft)
    assert first.digest == second.digest

    {:ok, changed} =
      Validation.validate(
        c.org,
        c.mission,
        c.actor,
        draft(~w(sc-a), [cmd(c, "SET_SIGNED", %{"counter" => 6})])
      )

    refute changed.digest == first.digest
  end

  test "reports identity and catalog failures per target without failing the whole read", c do
    draft = draft(~w(sc-a nobody), [cmd(c, "SET_SIGNED", %{"counter" => "not-a-number"})])

    assert {:ok, result} = Validation.validate(c.org, c.mission, c.actor, draft)
    refute result.valid?
    assert [%{spacecraft_id: "nobody", failure: :no_source_endpoint}] = result.identity_failures
    assert [%{spacecraft_id: "sc-a", position: 0}] = result.catalog_failures
  end

  test "enforces the size bounds", c do
    targets = for i <- 1..5_001, do: "sc-#{i}"

    assert {:error, {:command_group_too_large, %{max_targets: 5_000, targets: 5_001}}} =
             Validation.validate(
               c.org,
               c.mission,
               c.actor,
               draft(targets, [cmd(c, "SET_SIGNED", %{})])
             )

    # The members are targets x commands: 1,251 x 16 is within each own bound but not the product.
    stack = List.duplicate(cmd(c, "SET_SIGNED", %{}), 16)

    assert :ok = Validation.check_size(draft(for(i <- 1..1_250, do: "sc-#{i}"), stack))

    assert {:error, {:command_group_too_large, %{max_members: 20_000, targets: 1_251}}} =
             Validation.check_size(draft(for(i <- 1..1_251, do: "sc-#{i}"), stack))
  end

  test "a deployment's bounds replace the defaults", c do
    Application.put_env(:cadence, :command_group_bounds, max_targets: 1)
    on_exit(fn -> Application.delete_env(:cadence, :command_group_bounds) end)

    assert {:error, {:command_group_too_large, %{max_targets: 1, targets: 2}}} =
             Validation.check_size(draft(~w(sc-a sc-b), [cmd(c, "SET_SIGNED", %{})]))
  end

  test "a mission without an active catalog is not active" do
    other = CommandReviewFixtures.scope!()

    assert {:error, {:command_catalog_not_active, _}} =
             Validation.validate(other.org, other.mission, %{}, %{
               targets: [%{spacecraft_id: "x"}],
               commands: [%{command_id: "c"}]
             })
  end
end
