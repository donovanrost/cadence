defmodule Cadence.Configuration.ActorNamesTest do
  @moduledoc """
  #471: configuration reads (change sets, revisions, history) name a person only while an active
  member of the mission's organization, never by email; a service only when it belongs to the
  organization; Cadence by its system name. The stored actor document's name is never sent for a
  person or a service, so rows written before #471 (which stored `display_name || email`) read
  with no email, with no reset needed (lead 11-19).
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures
  import Ecto.Query

  alias Cadence.Accounts.UserRow
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.Configuration.{Access, ActorNames, RevisionRow}
  alias Cadence.Control.Configuration

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission()
    alice = member_scope(org, :member, "Alice")

    {:ok, set} = stage_and_apply(alice, mission, "Svalbard")
    %{org: org, mission: mission, alice: alice, set: set}
  end

  test "the writer stores a display name or nil, never an email", c do
    assert %{"kind" => "user", "name" => "Alice"} = Access.actor(c.alice)

    unnamed = %{c.alice | user: %{c.alice.user | display_name: nil}}
    actor = Access.actor(unnamed)
    assert actor["name"] == nil
    refute inspect(actor) =~ "@"
  end

  test "an old row that stored an email reads with the member's name, never the email", c do
    old_row!(c, %{"kind" => "user", "id" => c.alice.user.user_id, "name" => c.alice.user.email})

    assert {:ok, %{applied_by: %{name: "Alice"}} = revision} =
             Configuration.get_revision(c.alice, c.mission, 3)

    refute inspect(revision) =~ c.alice.user.email
  end

  test "an old row by someone who isn't a member reads with no name and no email", c do
    outsider = "outsider-#{System.unique_integer([:positive])}"

    old_row!(c, %{"kind" => "user", "id" => outsider, "name" => "#{outsider}@example.test"})

    for read <- [
          fn -> Configuration.get_revision(c.alice, c.mission, 3) end,
          fn -> Configuration.list_revisions(c.alice, c.mission) end
        ] do
      assert {:ok, view} = read.()
      refute inspect(view) =~ "@example.test"
      refute inspect(view) =~ outsider
    end

    # Neither the name nor the id reaches the organization (ca-security on #487).
    assert {:ok, %{applied_by: %{id: nil, name: nil}}} =
             Configuration.get_revision(c.alice, c.mission, 3)
  end

  test "a member without a display name reads with no name, never the email", c do
    id = c.alice.user.user_id
    Repo.update_all(from(u in UserRow, where: u.user_id == ^id), set: [display_name: ""])

    # They keep their id, so the console still knows their own changes (mms-engineer on #487).
    member_id = c.alice.user.user_id

    assert {:ok, %{applied_by: %{id: ^member_id, name: nil}} = revision} =
             Configuration.get_revision(c.alice, c.mission, 2)

    refute inspect(revision) =~ c.alice.user.email
  end

  test "services are named only in their own organization; Cadence keeps its name", c do
    own = service!(c.org, "Config bot")
    %{organization_id: other_org} = configuration_mission("other")
    foreign = service!(other_org, "Other bot")

    view = %{
      a: %{kind: "service", id: own, name: "Stored"},
      b: %{kind: "service", id: foreign, name: "Stored"},
      c: %{kind: "system", id: "cadence", name: "Cadence"}
    }

    assert %{
             a: %{name: "Config bot"},
             b: %{id: nil, name: nil},
             c: %{name: "Cadence"}
           } = ActorNames.named(view, c.mission)
  end

  test "with no head to name anyone under, nobody is named or identified" do
    view = [
      %{kind: "user", id: "someone", name: "Stored"},
      %{kind: "system", id: "cadence", name: "Cadence"}
    ]

    assert [%{kind: "user", id: nil, name: nil}, %{kind: "system", name: "Cadence"}] =
             ActorNames.named(view, "mission-without-head")
  end

  defp stage_and_apply(scope, mission, name) do
    {:ok, _staged} =
      Configuration.stage(scope, mission, %{summary: "Add #{name}"}, [station_op(name)])

    {:ok, %{change_set: set}} = Configuration.current(scope, mission)

    {:ok, _applied} =
      Configuration.submit(scope, mission, set.id, %{
        reason: "Add #{name}",
        expected_version: set.version
      })

    {:ok, set}
  end

  # A revision row as written before #471, its actor document holding `display_name || email`.
  # Revisions are append-only (#116), so it's inserted as r3 rather than rewritten.
  defp old_row!(c, applied_by) do
    Repo.insert!(%RevisionRow{
      revision_id: "old-#{System.unique_integer([:positive])}",
      organization_id: c.org,
      mission_id: c.mission,
      revision_number: 3,
      kind: "change_set",
      applied_by: applied_by,
      submitted_by: applied_by,
      applied_at: DateTime.utc_now(),
      reason: "Before #471",
      summary: "Old row",
      approvals: []
    })
  end

  defp service!(org, name) do
    identity =
      ServiceIdentity.new(%{
        service_identity_id: "svc-#{System.unique_integer([:positive])}",
        organization_id: org,
        display_name: name,
        capabilities: [:organization_admin]
      })

    issuer = %Scope{
      actor_kind: :user,
      organization_id: org,
      user: %Cadence.Accounts.User{user_id: "issuer"}
    }

    {:ok, %{service_identity: service}} = Auth.issue_service_identity(identity, issuer)
    service.service_identity_id
  end
end
