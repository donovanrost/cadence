defmodule Cadence.Configuration.ApprovalReasonChecksTest do
  @moduledoc """
  #521 follow-up (ca-security): the table holds the rule the code holds. A change-set review's
  `comment` and an activation decision's `reason` may be NULL only on an approval. A row written
  around the code (a script, a later bug) is refused by the database, not only by the changeset.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.User
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Management.Activations

  @now ~U[2026-11-20 08:00:00.000000Z]

  setup do
    %{organization: org, mission: mission} = persist_mission_scope("org-521c", "mission-521c")
    %{org: org.organization_id, mission: mission.mission_id}
  end

  describe "mission_config_reviews" do
    test "a send back without a comment is refused by the table", c do
      set = change_set!(c)

      assert_raise Postgrex.Error, ~r/mission_config_reviews_comment_unless_approved/, fn ->
        review!(c, set, "sent_back", nil)
      end
    end

    test "an approval without a comment, and a send back with one, are accepted", c do
      set = change_set!(c)
      assert {1, _} = review!(c, set, "approved", nil)
      assert {1, _} = review!(c, set, "sent_back", "Fix the port")
    end
  end

  describe "activation_decisions" do
    test "a rejection or withdrawal without a reason is refused by the table", c do
      request = activation_request!(c)

      for decision <- ["rejected", "withdrawn"] do
        assert_raise Postgrex.Error, ~r/activation_decisions_reason_unless_approved/, fn ->
          Repo.transaction(fn -> decision!(c, request, decision, nil) end)
        end
      end
    end

    test "an approval without a reason is accepted", c do
      request = activation_request!(c)
      assert {1, _} = decision!(c, request, "approved", nil)
    end
  end

  defp change_set!(c) do
    id = "config_change_set-521c-#{System.unique_integer([:positive])}"

    Repo.query!(
      """
      INSERT INTO mission_config_change_sets (change_set_id, organization_id, mission_id, state,
        version, base_revision_number, opened_by, opened_at, inserted_at, updated_at)
      VALUES ($1, $2, $3, 'in_review', 2, 1, '{"kind":"user","id":"u"}', $4, $4, $4)
      """,
      [id, c.org, c.mission, @now]
    )

    id
  end

  defp review!(c, set, decision, comment) do
    Repo.insert_all("mission_config_reviews", [
      %{
        review_id: "config_review-521c-#{System.unique_integer([:positive])}",
        change_set_id: set,
        organization_id: c.org,
        mission_id: c.mission,
        decision: decision,
        actor: %{"kind" => "user", "id" => "u"},
        comment: comment,
        decided_at: @now
      }
    ])
  end

  defp activation_request!(c) do
    {:ok, _} =
      Cadence.Governance.persist_binding_set(
        c.org,
        BindingSet.new(%{
          organization_id: c.org,
          mission_id: c.mission,
          binding_set_id: "basis-521c",
          version: 1
        })
      )

    scope =
      Scope.new(%{
        user:
          User.new(%{
            user_id: "requester-521c",
            email: "r@example.test",
            display_name: "Requester",
            capabilities: [:platform_admin]
          }),
        organization_id: c.org,
        admin_mode?: true
      })

    {:ok, request} = Activations.request(scope, c.mission, "basis-521c", 1)
    request.activation_request_id
  end

  defp decision!(c, request, decision, reason) do
    Repo.insert_all("activation_decisions", [
      %{
        activation_decision_id: "activation_decision-521c-#{System.unique_integer([:positive])}",
        activation_request_id: request,
        organization_id: c.org,
        mission_id: c.mission,
        decision: decision,
        actor_kind: "user",
        actor_id: "decider",
        actor_document: %{"kind" => "user", "id" => "decider"},
        reason: reason,
        decided_at: @now,
        inserted_at: @now
      }
    ])
  end
end
