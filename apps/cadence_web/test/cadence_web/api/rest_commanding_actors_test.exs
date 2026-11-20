defmodule CadenceWeb.API.RESTCommandingActorsTest do
  @moduledoc """
  #465 (#462, #146): REST commanding names every actor (a stage's owner, requested_by,
  decided_by, enqueued_by, released_by) as `{kind, id, name}` through #472's `ActorRef`, built on
  #466's `ActorDocument`, never the stored document. A person is named and keeps their id only
  while an active member of the record's organization (a member without a name keeps their id);
  anyone else is `{kind: "user", id: nil, name: nil}`. A service of the organization keeps its id
  and live name; the system actor reads as stored. A form Cadence can't read makes the whole
  field null. No email, ever, the rows written before #466 included (#116).
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}
  alias Cadence.Auth
  alias Cadence.Auth.ServiceIdentity

  alias Cadence.Commanding.{
    CommandApproval,
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandStage
  }

  alias Cadence.Repo
  alias CadenceWeb.API.CommandingJSON
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    other = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)

    named = TestFixtures.persist_user!(display_name: "Mira K.")
    nameless = TestFixtures.persist_user!(display_name: "Nameless")
    left = TestFixtures.persist_user!(display_name: "Lee Left")
    support = TestFixtures.persist_user!(display_name: "Pat Support")
    for user <- [named, nameless, left], do: TestFixtures.grant_membership!(user, org)
    TestFixtures.grant_membership!(support, other, role: :organization_admin)

    Repo.update_all(from(u in UserRow, where: u.user_id == ^nameless.user_id),
      set: [display_name: ""]
    )

    Repo.update_all(
      from(m in OrganizationMembershipRow,
        where: m.user_id == ^left.user_id and m.organization_id == ^org.organization_id
      ),
      set: [lifecycle_state: "revoked"]
    )

    {:ok, %{service_identity: service}} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          display_name: "Planner bot",
          capabilities: [:mission_admin]
        }),
        %Auth.Scope{actor_kind: :user, organization_id: org.organization_id, user: named}
      )

    %{
      org: org.organization_id,
      named: named,
      nameless: nameless,
      left: left,
      support: support,
      service: service,
      emails: Enum.map([named, nameless, left, support], & &1.email)
    }
  end

  # A person's actor document as REST commanding stored it before #466, with their email.
  defp old_rest(user, org),
    do: %{
      "actor_kind" => "user",
      "organization_id" => org,
      "user_id" => user.user_id,
      "user_email" => user.email,
      "user_display_name" => "Stored Name"
    }

  defp encode_each(c, document) do
    org = c.org

    [
      CommandingJSON.command_stage(
        struct(CommandStage,
          organization_id: org,
          owner: document,
          visibility: :private,
          lifecycle_state: :draft
        )
      ).owner,
      CommandingJSON.command_request(
        struct(CommandRequest, organization_id: org, requested_by: document)
      ).requested_by,
      CommandingJSON.command_approval(
        struct(CommandApproval, organization_id: org, decided_by: document)
      ).decided_by,
      CommandingJSON.command_queue_entry(
        struct(CommandQueueEntry, organization_id: org, enqueued_by: document)
      ).enqueued_by,
      CommandingJSON.command_release_attempt(
        struct(CommandReleaseAttempt, organization_id: org, released_by: document)
      ).released_by
    ]
  end

  test "a member is named and keeps their id; the stored name and email never go out", c do
    for actor <- encode_each(c, old_rest(c.named, c.org)) do
      assert actor == %{kind: "user", id: c.named.user_id, name: "Mira K."}
    end
  end

  test "a member without a display name keeps their id, with a null name", c do
    for actor <- encode_each(c, old_rest(c.nameless, c.org)) do
      assert actor == %{kind: "user", id: c.nameless.user_id, name: nil}
    end
  end

  test "someone who left, or a platform admin from another organization, is neither named nor identified",
       c do
    for user <- [c.left, c.support], actor <- encode_each(c, old_rest(user, c.org)) do
      assert actor == %{kind: "user", id: nil, name: nil}
    end
  end

  test "a service of the organization keeps its id and live name; the system reads as stored",
       c do
    service = %{"actor_kind" => "service", "service_identity_id" => c.service.service_identity_id}

    for actor <- encode_each(c, service) do
      assert actor == %{kind: "service", id: c.service.service_identity_id, name: "Planner bot"}
    end

    system = %{
      "actor_kind" => "system",
      "system_id" => "cadence:command_safety_policy",
      "name" => "Cadence"
    }

    for actor <- encode_each(c, system) do
      assert actor == %{kind: "system", id: "cadence:command_safety_policy", name: "Cadence"}
    end
  end

  test "a document Cadence can't read is the whole field null, not an object of nulls", c do
    for actor <- encode_each(c, %{"display_name" => "Who?", "email" => "who@example.test"}) do
      assert actor == nil
    end
  end

  test "a list encodes with its names loaded once, and no email anywhere", c do
    requests =
      for user <- [c.named, c.nameless, c.left, c.support],
          do: struct(CommandRequest, organization_id: c.org, requested_by: old_rest(user, c.org))

    encoded = CommandingJSON.encode_all(requests, &CommandingJSON.command_request/2)

    assert Enum.map(encoded, & &1.requested_by) == [
             %{kind: "user", id: c.named.user_id, name: "Mira K."},
             %{kind: "user", id: c.nameless.user_id, name: nil},
             %{kind: "user", id: nil, name: nil},
             %{kind: "user", id: nil, name: nil}
           ]

    text = Jason.encode!(encoded)
    for email <- c.emails, do: refute(text =~ email)
    refute text =~ "Stored Name"
  end
end
