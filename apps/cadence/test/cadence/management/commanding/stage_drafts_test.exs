defmodule Cadence.Management.Commanding.StageDraftsTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Auth.Scope
  alias Cadence.Commanding.{CommandStageRow, StagedCommandItem, StagedCommandItemRow}
  alias Cadence.CommandReviewFixtures
  alias Cadence.Ids
  alias Cadence.Management.Commanding.{StageCatalog, StageDrafts}

  setup do
    c = CommandReviewFixtures.scope!()
    {:ok, held} = StageDrafts.prepare_create(c.scope, c.mission)

    input = %{
      "expected_write" => held.write_token,
      "name" => "My flight stage",
      "description" => nil,
      "visibility" => "private"
    }

    %{c: c, held: held, input: input}
  end

  test "creation derives actual owner and durable ID, rejects replay and forged identity", %{
    c: c,
    held: held,
    input: input
  } do
    assert {:error, _} =
             StageDrafts.create(c.scope, c.mission, held, Map.put(input, "owner_id", "forged"))

    assert {:error, _} =
             StageDrafts.create(c.scope, c.mission, held, %{
               input
               | "expected_write" => String.duplicate("a", 64)
             })

    assert Repo.aggregate(CommandStageRow, :count) == 0
    assert {:ok, receipt} = StageDrafts.create(c.scope, c.mission, held, input)
    assert receipt["stage_id"] == held.stage_id
    assert receipt["actor_id"] == c.user.user_id
    row = Repo.get!(CommandStageRow, held.stage_id)

    assert row.owner_document == %{
             "value" => %{"actor_kind" => "user", "user_id" => c.user.user_id}
           }

    assert row.lifecycle_state == "draft"

    assert {:error, _} =
             StageDrafts.create(c.scope, c.mission, held, %{input | "name" => "Replay"})

    assert Repo.get!(CommandStageRow, held.stage_id).stage_name == "My flight stage"
  end

  test "held creation cannot cross mission or actor or survive revocation", %{
    c: c,
    held: held,
    input: input
  } do
    other = manager!(c)
    assert {:error, :unavailable} = StageDrafts.create(other, c.mission, held, input)
    assert {:error, :unavailable} = StageDrafts.create(c.scope, "mission_other", held, input)
    revoke!(c)
    assert {:error, :unavailable} = StageDrafts.create(c.scope, c.mission, held, input)
    refute Repo.get(CommandStageRow, held.stage_id)
  end

  test "stage edits preserve ownership and reject retained content after another edit", %{
    c: c,
    held: held,
    input: input
  } do
    {:ok, _} = StageDrafts.create(c.scope, c.mission, held, input)
    {:ok, detail} = StageCatalog.workbench(c.scope, c.mission, held.stage_id, %{})
    edit = stage_edit(detail, held.write_token)

    assert {:ok, %{"state" => "in_review"}} =
             StageDrafts.edit_stage(c.scope, c.mission, held.stage_id, held.write_token, edit)

    assert {:error, :command_stage_changed} =
             StageDrafts.edit_stage(c.scope, c.mission, held.stage_id, held.write_token, %{
               edit
               | "name" => "Stale overwrite"
             })

    row = Repo.get!(CommandStageRow, held.stage_id)
    assert row.stage_name == "Updated stage"
    assert get_in(row.owner_document, ["value", "user_id"]) == c.user.user_id
  end

  test "shared collaborators may maintain items but cannot take over or hide the container", %{
    c: c,
    held: held,
    input: input
  } do
    {:ok, _} = StageDrafts.create(c.scope, c.mission, held, %{input | "visibility" => "shared"})
    other = manager!(c)
    item = item!(c, held.stage_id)

    {:ok, detail} =
      StageCatalog.workbench(other, c.mission, held.stage_id, %{
        "item" => item.staged_command_item_id
      })

    assert {:error, :unavailable} =
             StageDrafts.edit_stage(
               other,
               c.mission,
               held.stage_id,
               held.write_token,
               stage_edit(detail, held.write_token)
             )

    edit = item_edit(detail, held.write_token)

    assert {:ok, receipt} =
             StageDrafts.edit_details(
               other,
               c.mission,
               held.stage_id,
               item.staged_command_item_id,
               held.write_token,
               edit
             )

    assert receipt["actor_id"] == other.user.user_id
    row = Repo.get!(StagedCommandItemRow, item.staged_command_item_id)
    assert row.item_order == 27
    assert row.notes == String.duplicate("é", 2_000)
    assert row.argument_values_document == %{"value" => %{"enabled" => false}}
    assert row.mission_model_revision_id == "model_unavailable"
  end

  test "draft details bind exact item content, stage visibility and current authorization", %{
    c: c,
    held: held,
    input: input
  } do
    {:ok, _} = StageDrafts.create(c.scope, c.mission, held, input)
    item = item!(c, held.stage_id)

    {:ok, detail} =
      StageCatalog.workbench(c.scope, c.mission, held.stage_id, %{
        "item" => item.staged_command_item_id
      })

    edit = item_edit(detail, held.write_token)

    assert {:ok, _} =
             StageDrafts.edit_details(
               c.scope,
               c.mission,
               held.stage_id,
               item.staged_command_item_id,
               held.write_token,
               edit
             )

    assert {:error, :command_stage_changed} =
             StageDrafts.edit_details(
               c.scope,
               c.mission,
               held.stage_id,
               item.staged_command_item_id,
               held.write_token,
               edit
             )

    revoke!(c)

    assert {:error, :unavailable} =
             StageDrafts.cancel_item(
               c.scope,
               c.mission,
               held.stage_id,
               item.staged_command_item_id,
               held.write_token,
               Map.drop(edit, ["notes", "order"])
             )

    assert Repo.get!(StagedCommandItemRow, item.staged_command_item_id).lifecycle_state == "draft"
  end

  test "canceling an oversized old draft does not need its original model or truncate its data",
       %{c: c, held: held, input: input} do
    {:ok, _} = StageDrafts.create(c.scope, c.mission, held, input)
    item = item!(c, held.stage_id)
    row = Repo.get!(StagedCommandItemRow, item.staged_command_item_id)
    original = %{"value" => %{"huge" => String.duplicate("x", 40_000)}}
    Repo.update!(Ecto.Changeset.change(row, argument_values_document: original))

    {:ok, detail} =
      StageCatalog.workbench(c.scope, c.mission, held.stage_id, %{
        "item" => item.staged_command_item_id
      })

    refute detail["selected_item"]["available"]
    cancel = detail |> item_edit(held.write_token) |> Map.drop(["notes", "order"])

    assert {:ok, %{"operation" => "item_canceled"}} =
             StageDrafts.cancel_item(
               c.scope,
               c.mission,
               held.stage_id,
               item.staged_command_item_id,
               held.write_token,
               cancel
             )

    current = Repo.get!(StagedCommandItemRow, item.staged_command_item_id)
    assert current.lifecycle_state == "canceled"
    assert current.argument_values_document == original

    {:ok, detail} =
      StageCatalog.workbench(c.scope, c.mission, held.stage_id, %{
        "item" => item.staged_command_item_id
      })

    assert {:error, _} =
             StageDrafts.edit_details(
               c.scope,
               c.mission,
               held.stage_id,
               item.staged_command_item_id,
               held.write_token,
               item_edit(detail, held.write_token)
             )
  end

  defp stage_edit(detail, token),
    do: %{
      "expected_write" => token,
      "expected_stage" => detail["stage"]["expected_stage"],
      "name" => "Updated stage",
      "description" => nil,
      "visibility" => "shared",
      "state" => "in_review"
    }

  defp item_edit(detail, token),
    do: %{
      "expected_write" => token,
      "expected_stage" => detail["stage"]["expected_stage"],
      "expected_item" => detail["selected_item"]["expected_item"],
      "notes" => String.duplicate("é", 2_000),
      "order" => 27
    }

  defp item!(c, stage_id) do
    StagedCommandItem.new(%{
      organization_id: c.org,
      mission_id: c.mission,
      command_stage_id: stage_id,
      source_endpoint_ref: "target_unavailable",
      mission_model_revision_id: "model_unavailable",
      command_id: "command_old",
      argument_values: %{"enabled" => false}
    })
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

  defp revoke!(c),
    do:
      Repo.update_all(
        from(row in OrganizationMembershipRow,
          where: row.user_id == ^c.user.user_id and row.organization_id == ^c.org
        ),
        set: [lifecycle_state: "revoked"]
      )
end
