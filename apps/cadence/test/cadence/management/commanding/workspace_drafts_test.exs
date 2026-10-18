defmodule Cadence.Management.Commanding.WorkspaceDraftsTest do
  use Cadence.DataCase, async: false
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.{CommandRequestRow, CommandStage, StagedCommandItemRow, StageStore}

  alias Cadence.Management.Commanding.{
    RequestAuthoring,
    StageCatalog,
    StageDrafts,
    WorkspaceCatalog,
    WorkspaceDrafts
  }

  setup do
    c = CommandAuthoringFixtures.fixture!()

    second =
      CommandAuthoringFixtures.target!(c.org, c.mission, %{
        display_name: "Second spacecraft endpoint",
        scid: 8
      })

    {:ok, stage} =
      StageStore.persist_stage(
        c.org,
        CommandStage.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          stage_name: "Fleet preparation",
          owner: %{"user_id" => c.user.user_id},
          visibility: :private
        })
      )

    Map.merge(c, %{stage: stage, second: second})
  end

  test "previews both endpoints, atomically saves their exact overrides, and recovers without formal requests",
       c do
    input = input(c)

    assert {:ok, held} =
             WorkspaceDrafts.preview(c.scope, c.mission, c.stage.command_stage_id, input)

    assert WorkspaceDrafts.current?(c.scope, c.mission, held)
    assert Repo.aggregate(StagedCommandItemRow, :count) == 0
    assert {:ok, public} = WorkspaceDrafts.public_preview(held)

    assert Enum.map(public["items"], & &1["command"]["target"]["id"]) == [
             c.target.source_endpoint_id,
             c.second.source_endpoint_id
           ]

    assert {:ok, receipt} = save(c, held)
    assert length(receipt["items"]) == 2

    assert Enum.map(held.items, fn item ->
             Repo.get!(StagedCommandItemRow, item.item_id).argument_values_document
           end) == [%{"value" => %{"amount" => 2}}, %{"value" => %{"amount" => 7}}]

    assert Repo.aggregate(CommandRequestRow, :count) == 0
    assert {:ok, ^receipt} = WorkspaceDrafts.recover(c.scope, c.mission, held)
    assert {:error, _} = save(c, held)
    assert Repo.aggregate(StagedCommandItemRow, :count) == 2
  end

  test "one invalid endpoint or invalid override prevents the entire preview", c do
    input = input(c)
    [first, second] = input["commands"]

    for invalid <- [
          Map.put(second, "source_endpoint_ref", "endpoint_foreign"),
          Map.put(second, "argument_values_json", ~s({"amount":999}))
        ] do
      assert {:error, _} =
               WorkspaceDrafts.preview(c.scope, c.mission, c.stage.command_stage_id, %{
                 input
                 | "commands" => [first, invalid]
               })
    end

    assert Repo.aggregate(StagedCommandItemRow, :count) == 0
  end

  test "duplicate endpoints and oversized batches are rejected before work", c do
    input = input(c)
    first = hd(input["commands"])

    for commands <- [[first, first], List.duplicate(first, 26), []] do
      assert {:error, _} =
               WorkspaceDrafts.preview(c.scope, c.mission, c.stage.command_stage_id, %{
                 input
                 | "commands" => commands
               })
    end
  end

  test "another saved batch invalidates the reviewed append position", c do
    assert {:ok, first} =
             WorkspaceDrafts.preview(c.scope, c.mission, c.stage.command_stage_id, input(c))

    assert {:ok, concurrent} =
             WorkspaceDrafts.preview(c.scope, c.mission, c.stage.command_stage_id, input(c))

    assert {:ok, _} = save(c, first)
    refute WorkspaceDrafts.current?(c.scope, c.mission, concurrent)
    assert {:error, :command_stage_changed} = save(c, concurrent)
    assert Repo.aggregate(StagedCommandItemRow, :count) == 2
  end

  test "changed second endpoint rolls back the first insertion", c do
    assert {:ok, held} =
             WorkspaceDrafts.preview(c.scope, c.mission, c.stage.command_stage_id, input(c))

    row = Repo.get!(Cadence.SourceEndpoints.SourceEndpointRow, c.second.source_endpoint_id)
    Repo.update!(Ecto.Changeset.change(row, scid: 9))
    refute WorkspaceDrafts.current?(c.scope, c.mission, held)
    assert {:error, _} = save(c, held)
    assert Repo.aggregate(StagedCommandItemRow, :count) == 0
  end

  test "spacecraft name search returns explicit scoped endpoints and curated labels", c do
    {:ok, craft} =
      Cadence.SpacecraftStore.persist_spacecraft(
        c.org,
        Cadence.Spacecraft.new(%{mission_id: c.mission, display_name: "Kestrel 01"})
      )

    endpoint =
      CommandAuthoringFixtures.target!(c.org, c.mission, %{
        display_name: "Payload computer",
        spacecraft_id: craft.spacecraft_id
      })

    other = CommandAuthoringFixtures.fixture!()
    CommandAuthoringFixtures.target!(other.org, other.mission, %{display_name: "Kestrel 01"})

    assert {:ok, catalog, spacecraft} =
             WorkspaceCatalog.load(c.scope, c.mission, %{"target_query" => "kestrel 01"})

    assert [%{"id" => endpoint_id}] = catalog["targets"]["entries"]
    assert endpoint_id == endpoint.source_endpoint_id
    assert spacecraft == [%{"id" => craft.spacecraft_id, "name" => "Kestrel 01"}]
  end

  test "model or stage changes invalidate the held batch", c do
    assert {:ok, held} =
             WorkspaceDrafts.preview(c.scope, c.mission, c.stage.command_stage_id, input(c))

    CommandAuthoringFixtures.activate!(c.org, c.mission, 3)
    refute WorkspaceDrafts.current?(c.scope, c.mission, held)
    assert {:error, _} = save(c, held)
    assert Repo.aggregate(StagedCommandItemRow, :count) == 0

    assert {:ok, held} =
             WorkspaceDrafts.preview(c.scope, c.mission, c.stage.command_stage_id, input(c))

    assert {:ok, _} =
             StageStore.update_stage(c.org, %{c.stage | stage_name: "Changed by another operator"})

    assert {:error, _} = save(c, held)
    assert Repo.aggregate(StagedCommandItemRow, :count) == 0
  end

  defp input(c) do
    {:ok, workbench} = StageCatalog.workbench(c.scope, c.mission, c.stage.command_stage_id, %{})
    {:ok, catalog} = RequestAuthoring.load(c.scope, c.mission, %{})

    %{
      "expected_stage" => workbench["stage"]["expected_stage"],
      "notes" => "Fleet pass",
      "commands" =>
        Enum.map([{c.target, 2}, {c.second, 7}], fn {target, amount} ->
          %{
            "expected_basis" => catalog["basis"]["token"],
            "source_endpoint_ref" => target.source_endpoint_id,
            "command_id" => catalog["commands"]["entries"] |> hd() |> Map.fetch!("id"),
            "argument_values_json" => Jason.encode!(%{"amount" => amount}),
            "priority" => 3,
            "not_before" => nil,
            "expires_at" => nil
          }
        end)
    }
  end

  defp save(c, held) do
    token = StageDrafts.new_write_token()

    WorkspaceDrafts.save(c.scope, c.mission, c.stage.command_stage_id, token, held, %{
      "expected_write" => token,
      "expected_preview" => held.token
    })
  end
end
