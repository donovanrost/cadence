defmodule Cadence.Commanding.CommandRequestGroupTest do
  @moduledoc "#708: a command request is stored only as a member of a command group that exists."
  use Cadence.DataCase, async: false

  alias Cadence.Commanding.{CommandRequest, CommandRequestRow}
  alias Cadence.CommandMemberFixtures
  alias Cadence.CommandReviewFixtures

  defp request(c, attrs \\ %{}) do
    CommandRequest.new(
      Map.merge(
        %{
          organization_id: c.org,
          mission_id: c.mission,
          source_endpoint_ref: "endpoint-group",
          mission_model_revision_id: "model-group",
          command_id: "command-group",
          command_name: "NOOP",
          requested_by: %{"user_id" => "requester"},
          requested_at: ~U[2026-11-26 12:00:00Z]
        },
        attrs
      )
    )
  end

  test "a request outside any group is refused" do
    c = CommandReviewFixtures.scope!()
    changeset = c |> request() |> CommandRequestRow.changeset()

    assert {:error, %Ecto.Changeset{errors: errors}} = Repo.insert(changeset)

    for field <- [:command_group_id, :group_target_index, :group_position],
        do: assert(Keyword.has_key?(errors, field))
  end

  test "the database refuses it too, whatever the changeset" do
    c = CommandReviewFixtures.scope!()

    assert_raise Postgrex.Error, ~r/not_null_violation/, fn ->
      Repo.insert_all(CommandRequestRow, [
        %{
          command_request_id: "outside-any-group",
          organization_id: c.org,
          mission_id: c.mission,
          source_endpoint_ref: "endpoint-group",
          mission_model_revision_id: "model-group",
          command_id: "command-group",
          command_name: "NOOP",
          lifecycle_state: "queued",
          priority: 3,
          requested_at: ~U[2026-11-26 12:00:00.000000Z],
          inserted_at: ~U[2026-11-26 12:00:00.000000Z],
          updated_at: ~U[2026-11-26 12:00:00.000000Z]
        }
      ])
    end
  end

  test "a request naming a group that doesn't exist is refused" do
    c = CommandReviewFixtures.scope!()

    changeset =
      CommandRequestRow.changeset(
        request(c, %{command_group_id: "no-such-group", group_target_index: 0, group_position: 0})
      )

    assert {:error, %Ecto.Changeset{errors: errors}} = Repo.insert(changeset)
    assert Keyword.has_key?(errors, :command_group_id)
  end

  test "two members can't take the same place in a group" do
    c = CommandReviewFixtures.scope!()
    group = CommandMemberFixtures.group!(c.org, c.mission, :queued, 2)
    CommandMemberFixtures.insert!(c.org, request(c), group: group)

    assert {:error, %Ecto.Changeset{}} =
             Repo.insert(
               CommandRequestRow.changeset(
                 request(c, %{
                   command_group_id: group,
                   group_target_index: 0,
                   group_position: 0
                 })
               )
             )
  end
end
