defmodule Cadence.Management.Commanding.StageCatalogTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Auth.Scope
  alias Cadence.CommandReviewFixtures

  alias Cadence.Commanding.{
    CommandStage,
    CommandStageRow,
    StagedCommandItem,
    StagedCommandItemRow,
    StageStore
  }

  alias Cadence.Ids
  alias Cadence.Management.Commanding.StageCatalog
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint

  setup do
    c = CommandReviewFixtures.scope!()
    other = manager!(c)
    %{c: c, other: other}
  end

  test "private stages belong to their owner even when another human is an organization admin", %{
    c: c,
    other: other
  } do
    private = stage!(c, %{})
    shared = stage!(c, %{visibility: :shared})
    foreign = CommandReviewFixtures.scope!()
    stage!(foreign, %{visibility: :shared, stage_name: "foreign-secret"})

    assert {:ok, own} = StageCatalog.directory(c.scope, c.mission, %{})

    assert Enum.sort(Enum.map(own["stages"]["entries"], & &1["id"])) ==
             Enum.sort([private.command_stage_id, shared.command_stage_id])

    assert {:ok, other_page} = StageCatalog.directory(other, c.mission, %{})
    assert [%{"id" => id}] = other_page["stages"]["entries"]
    assert id == shared.command_stage_id

    assert {:error, :unavailable} =
             StageCatalog.workbench(other, c.mission, private.command_stage_id, %{})

    assert {:error, :unavailable} =
             StageCatalog.workbench(foreign.scope, c.mission, shared.command_stage_id, %{})

    assert {:ok, detail} = StageCatalog.workbench(other, c.mission, shared.command_stage_id, %{})
    assert detail["stage"]["can_edit_items"]
    refute detail["stage"]["can_edit_stage"]

    assert {:ok, owner_detail} =
             StageCatalog.workbench(c.scope, c.mission, private.command_stage_id, %{})

    assert owner_detail["stage"]["can_edit_stage"]
    refute Jason.encode!(own) =~ "private-metadata"
    refute Jason.encode!(detail) =~ "private-metadata"
  end

  test "directory pages after privacy filtering and treats search wildcards literally", %{
    c: c,
    other: other
  } do
    for i <- 1..28 do
      stage!(c, %{command_stage_id: "a_private_#{i}", stage_name: "private-secret"})
    end

    expected =
      for i <- 1..27 do
        stage!(c, %{
          command_stage_id: "z_shared_#{String.pad_leading(to_string(i), 2, "0")}",
          visibility: :shared
        })
      end

    assert {:ok, first} = StageCatalog.directory(other, c.mission, %{})
    assert length(first["stages"]["entries"]) == 25

    assert {:ok, second} =
             StageCatalog.directory(other, c.mission, %{"after" => first["stages"]["next_after"]})

    assert length(second["stages"]["entries"]) == 2
    assert second["stages"]["next_after"] == nil

    assert Enum.map(first["stages"]["entries"] ++ second["stages"]["entries"], & &1["id"]) ==
             Enum.map(expected, & &1.command_stage_id)

    literal = stage!(c, %{stage_name: "100%_ready\\now", visibility: :shared})
    assert {:ok, search} = StageCatalog.directory(other, c.mission, %{"query" => "%_ready\\"})
    assert [%{"id" => id}] = search["stages"]["entries"]
    assert id == literal.command_stage_id
  end

  test "draft labels are independent of catalog browsing and do not change the item token", %{
    c: c
  } do
    stage = stage!(c, %{})
    item = item!(c, stage, %{})
    query = %{"item" => item.staged_command_item_id}

    assert {:ok, before} =
             StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, query)

    assert before["selected_item"]["target_name"] == nil

    assert {:ok, _} =
             SourceEndpoints.persist_source_endpoint(
               c.org,
               SourceEndpoint.new(%{
                 mission_id: c.mission,
                 source_endpoint_id: item.source_endpoint_ref,
                 display_name: "Aurora"
               })
             )

    assert {:ok, after_name} =
             StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, query)

    assert [%{"target_name" => "Aurora"}] = after_name["items"]["entries"]
    assert after_name["selected_item"]["target_name"] == "Aurora"
    assert after_name["selected_item"]["target_id"] == item.source_endpoint_ref

    assert after_name["selected_item"]["expected_item"] ==
             before["selected_item"]["expected_item"]
  end

  test "item paging follows order and ID ties; selection is independent of the current page", %{
    c: c
  } do
    stage = stage!(c, %{})
    # No active model or endpoint is needed to inspect these durable drafts.
    items =
      for i <- 1..28 do
        item!(c, stage, %{
          staged_command_item_id: "item_#{String.pad_leading(to_string(29 - i), 2, "0")}",
          item_order: div(i, 3)
        })
      end

    expected = Enum.sort_by(items, &{&1.item_order, &1.staged_command_item_id})
    selected = List.last(expected)

    assert {:ok, first} =
             StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, %{
               "item" => selected.staged_command_item_id
             })

    assert first["selected_item"]["id"] == selected.staged_command_item_id
    assert Jason.decode!(first["selected_item"]["argument_values_json"]) == %{"enabled" => false}
    assert Enum.all?(first["items"]["entries"], &is_nil(&1["argument_values_json"]))
    cursor = first["items"]["next_after"]

    assert {:ok, second} =
             StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, %{
               "after" => cursor["id"],
               "after_order" => to_string(cursor["order"])
             })

    entries = first["items"]["entries"] ++ second["items"]["entries"]
    assert Enum.map(entries, & &1["id"]) == Enum.map(expected, & &1.staged_command_item_id)
    assert second["items"]["next_after"] == nil
    other_stage = stage!(c, %{})

    assert {:ok, isolated} =
             StageCatalog.workbench(c.scope, c.mission, other_stage.command_stage_id, %{
               "item" => selected.staged_command_item_id
             })

    assert isolated["selected_item"] == nil
  end

  test "exact selection fingerprints change for private metadata and draft content", %{c: c} do
    stage = stage!(c, %{})
    item = item!(c, stage, %{})
    params = %{"item" => item.staged_command_item_id}
    {:ok, before} = StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, params)
    row = Repo.get!(StagedCommandItemRow, item.staged_command_item_id)

    Repo.update!(
      Ecto.Changeset.change(row, metadata_document: %{"value" => %{"secret" => "changed"}})
    )

    {:ok, after_metadata} =
      StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, params)

    assert before["selected_item"]["expected_item"] !=
             after_metadata["selected_item"]["expected_item"]

    refute Jason.encode!(after_metadata) =~ "secret"
    row = Repo.get!(CommandStageRow, stage.command_stage_id)
    Repo.update!(Ecto.Changeset.change(row, stage_name: "New name"))

    {:ok, after_stage} =
      StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, params)

    assert before["stage"]["expected_stage"] != after_stage["stage"]["expected_stage"]
  end

  test "oversized arguments remain visible as unavailable items, never silently disappear", %{
    c: c
  } do
    stage = stage!(c, %{})
    item = item!(c, stage, %{argument_values: %{"huge" => String.duplicate("x", 40_000)}})

    assert {:ok, detail} =
             StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, %{
               "item" => item.staged_command_item_id
             })

    assert [%{"available" => false}] = detail["items"]["entries"]
    refute detail["selected_item"]["available"]
    assert detail["selected_item"]["argument_values_json"] == nil
    assert byte_size(Jason.encode!(detail)) < 4_000
  end

  test "fresh reads reject a revoked manager and unknown visibility cannot normalize to access",
       %{c: c} do
    stage = stage!(c, %{})
    row = Repo.get!(CommandStageRow, stage.command_stage_id)
    Repo.update!(Ecto.Changeset.change(row, visibility: "unknown"))

    assert {:error, :unavailable} =
             StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, %{})

    assert {:ok, %{"stages" => %{"entries" => []}}} =
             StageCatalog.directory(c.scope, c.mission, %{})

    Repo.update_all(
      from(r in OrganizationMembershipRow,
        where: r.user_id == ^c.user.user_id and r.organization_id == ^c.org
      ),
      set: [lifecycle_state: "revoked"]
    )

    assert {:error, :unavailable} = StageCatalog.directory(c.scope, c.mission, %{})

    assert {:error, :unavailable} =
             StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, %{})
  end

  test "four thousand UTF8 bytes persist exactly in descriptions and item notes", %{c: c} do
    text = String.duplicate("é", 2_000)
    stage = stage!(c, %{description: text})
    item = item!(c, stage, %{notes: text})

    assert {:ok, detail} =
             StageCatalog.workbench(c.scope, c.mission, stage.command_stage_id, %{
               "item" => item.staged_command_item_id
             })

    assert detail["stage"]["description"] == text
    assert detail["selected_item"]["notes"] == text
  end

  defp stage!(c, attrs) do
    {:ok, stage} =
      StageStore.persist_stage(
        c.org,
        CommandStage.new(
          Map.merge(
            %{
              organization_id: c.org,
              mission_id: c.mission,
              stage_name: "Flight preparation",
              owner: %{"user_id" => c.user.user_id},
              metadata: %{"secret" => "private-metadata"}
            },
            attrs
          )
        )
      )

    stage
  end

  defp item!(c, stage, attrs) do
    StagedCommandItem.new(
      Map.merge(
        %{
          organization_id: c.org,
          mission_id: c.mission,
          command_stage_id: stage.command_stage_id,
          source_endpoint_ref: "target_read",
          mission_model_revision_id: "model_read",
          command_id: "command_read",
          argument_values: %{"enabled" => false},
          metadata: %{"secret" => "private-metadata"}
        },
        attrs
      )
    )
    |> StagedCommandItemRow.changeset()
    |> Repo.insert!()
    |> StagedCommandItemRow.to_domain()
  end

  defp manager!(c) do
    id = Ids.new("manager")
    user = User.new(%{user_id: id, email: "#{id}@example.test", display_name: "Collaborator"})
    Repo.insert!(UserRow.changeset(user))

    member =
      OrganizationMembership.new(%{
        user_id: id,
        organization_id: c.org,
        role: :organization_admin
      })

    Repo.insert!(OrganizationMembershipRow.changeset(member))
    Scope.new(%{user: user, organization_id: c.org, organization_membership: member})
  end
end
