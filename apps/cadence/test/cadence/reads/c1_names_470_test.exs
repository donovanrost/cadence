defmodule Cadence.Reads.C1Names470Test do
  @moduledoc """
  #470 (#462, #146 rule C1): the activation request rows, a command's resolution, and the
  settings History name people only while they're active members of the read's organization,
  live, never from a stored name or email. Each is tested with the issue's three actors:
  (a) a member with a display name, (b) a member without one, (c) another organization's
  platform admin, or someone who left. (b) and (c) never show the email. Old stored documents
  with a name and email are read through the shared helper.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{
    MembershipAdministration,
    OrganizationMembership,
    OrganizationMembershipRow,
    User,
    UserRow
  }

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.{Scope, SettingsAccess}
  alias Cadence.Control.ActivationRequests.Rows
  alias Cadence.Management.{Activations, SettingsHistory}
  alias Cadence.Platform.ScopedSettings
  alias Cadence.Platform.ScopedSettings.RevisionRow
  alias Cadence.Reads.CommandRequestHistory

  @org "org-470-c1"
  @mission "mission-470-c1"

  setup do
    persist_mission_scope(@org, @mission)
    persist_mission_scope("org-470-c1-other", "mission-470-c1-other")
    member = person!("c1-member", "Mira K.", @org)
    person!("c1-nameless", "Placeholder", @org)
    {1, _} = Repo.update_all(where(UserRow, user_id: "c1-nameless"), set: [display_name: ""])
    person!("c1-left", "Lee Left", @org)
    {:ok, _} = MembershipAdministration.remove_member(@org, "c1-left", "c1-member")
    admin = person!("c1-admin", "Pat Platform", "org-470-c1-other", [:platform_admin])
    second = person!("c1-admin2", "Sam Second", "org-470-c1-other", [:platform_admin])

    %{
      member: Scope.new(%{user: member, organization_id: @org}),
      admin: Scope.new(%{user: admin, organization_id: @org, admin_mode?: true}),
      second: Scope.new(%{user: second, organization_id: @org, admin_mode?: true})
    }
  end

  describe "activation request rows" do
    test "(a) named live; (b), (c) {user, nil, nil}; a stored name or email is never used", c do
      {:ok, _} =
        Cadence.Governance.persist_binding_set(
          @org,
          BindingSet.new(%{
            organization_id: @org,
            mission_id: @mission,
            binding_set_id: "basis-470",
            version: 1
          })
        )

      {:ok, request} = Activations.request(c.admin, @mission, "basis-470", 1)

      {:ok, _request, _decision} =
        Activations.reject(c.second, request.activation_request_id, "no")

      {:ok, request} = Activations.fetch(c.member, request.activation_request_id)

      [row] = Rows.rows(c.member, @mission, [request])
      # Platform admins from another organization asked and decided: unnamed, no id.
      assert row.requested_by == %{kind: "user", id: nil, name: nil}
      assert row.decision.by == %{kind: "user", id: nil, name: nil}

      for {id, expected} <- [
            {"c1-member", %{kind: "user", id: "c1-member", name: "Mira K."}},
            {"c1-nameless", %{kind: "user", id: "c1-nameless", name: nil}},
            {"c1-left", %{kind: "user", id: nil, name: nil}}
          ] do
        [row] = Rows.rows(c.member, @mission, [%{request | requester_actor_document: old(id)}])
        assert row.requested_by == expected
      end
    end
  end

  describe "a command's resolution (CommandRequestHistory.resolved_by/3)" do
    test "(a) named live; (b), (c) unnamed; an old document's name or email is never used" do
      for {id, expected} <- [
            {"c1-member", %{kind: "user", id: "c1-member", name: "Mira K."}},
            {"c1-nameless", %{kind: "user", id: "c1-nameless", name: nil}},
            {"c1-left", %{kind: "user", id: nil, name: nil}},
            {"c1-admin", %{kind: "user", id: nil, name: nil}}
          ] do
        evidence = %{
          "entries" => [
            %{
              "outcome" => "not_sent",
              "actor" => old(id),
              "recorded_at" => "2026-11-20T01:00:00Z"
            }
          ]
        }

        assert %{by: ^expected} =
                 CommandRequestHistory.resolved_by(
                   %{kind: "resolved", code: "not_sent"},
                   evidence,
                   @org
                 )
      end
    end
  end

  describe "the settings History and who saved a section" do
    test "the writer stores the display name only, never the email", c do
      assert SettingsAccess.actor(c.member) == %{id: "c1-member", name: "Mira K."}
    end

    test "History names live from the id, never the stored name, which can be an email" do
      for {id, n} <- Enum.with_index(~w(c1-member c1-nameless c1-left c1-admin), 1) do
        Repo.insert!(
          RevisionRow.changeset(%{
            revision_id: "settings-470-c1-#{n}",
            organization_id: @org,
            scope_key: "organization",
            section_id: "cadence.pass_review",
            version: n,
            document: %{"value" => %{}, "allow_override" => true},
            actor_id: id,
            actor_name: "#{id}@example.test"
          })
        )
      end

      actors =
        @org
        |> SettingsHistory.list(nil, "cadence.pass_review")
        |> Map.new(&{&1.version, &1.actor})

      # The raw history carries the id only, never the stored name.
      refute Enum.any?(
               ScopedSettings.history(@org, nil, "cadence.pass_review"),
               &Map.has_key?(&1, :actor)
             )

      assert actors == %{1 => "Mira K.", 2 => nil, 3 => nil, 4 => nil}
    end
  end

  defp old(id),
    do: %{
      "kind" => "user",
      "id" => id,
      "display_name" => "Stored Name",
      "email" => "stored@example.test"
    }

  defp person!(id, name, organization_id, capabilities \\ []) do
    user =
      User.new(%{
        user_id: id,
        email: "#{id}@example.test",
        display_name: name,
        capabilities: capabilities
      })

    Repo.insert!(UserRow.changeset(user))

    Repo.insert!(
      OrganizationMembershipRow.changeset(
        OrganizationMembership.new(%{
          user_id: id,
          organization_id: organization_id,
          role: :member
        })
      )
    )

    user
  end
end
