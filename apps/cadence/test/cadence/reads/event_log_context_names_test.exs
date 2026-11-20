defmodule Cadence.Reads.EventLogContextNamesTest do
  @moduledoc """
  #472 (#462, #146 rule C1): the Timeline names a person only while they hold an active
  membership in the mission's organization, checked at read time. No email, ever.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.EventLog.Context
  alias Cadence.Reads.EventSentences

  @org "org-472-log"
  @mission "mission-472-log"

  setup do
    persist_mission_scope(@org, @mission)
    persist_mission_scope("org-472-log-other", "mission-472-log-other")
    person!("log-member", "Mira K.", @org)
    person!("log-nameless", "Placeholder", @org)
    {1, _} = Repo.update_all(where(UserRow, user_id: "log-nameless"), set: [display_name: ""])
    person!("log-left", "Lee Left", @org, :revoked)
    person!("log-admin", "Pat Platform", "org-472-log-other", :active, [:platform_admin])
    :ok
  end

  test "(a) a member is named; (b) no display name, (c) a non-member or one who left: nothing" do
    entries =
      for id <- ~w(log-member log-nameless log-left log-admin),
          do: struct(Entry, actor: %{"value" => %{"kind" => "user", "id" => id}})

    %{users: users} = Context.load(@org, @mission, entries)

    assert users == %{"log-member" => "Mira K."}
    refute Enum.any?(Map.values(users), &(&1 =~ "@"))
  end

  test "#488: services and Cadence are named in the sentence, through the loaded names" do
    planner = service!(@org, "Nightly planner")
    foreign = service!("org-472-log-other", "Their planner")

    entries =
      for actor <- [
            %{"kind" => "service", "id" => planner},
            %{"kind" => "service", "id" => foreign},
            %{"kind" => "system"}
          ],
          do:
            struct(Entry,
              mission_event_id: "e-#{System.unique_integer([:positive])}",
              kind: :dashboard_published,
              subject_id: "dash",
              actor: %{"value" => actor},
              metadata: %{"payload" => %{"value" => %{"dashboard_version" => 1}}}
            )

    ctx = Map.merge(Context.load(@org, @mission, entries), %{contacts: %{}})
    texts = Enum.map(entries, &EventSentences.describe(&1, ctx).text)

    assert [planned, foreign_text, cadence] = texts
    assert planned =~ "by Nightly planner (a service identity)"
    assert foreign_text =~ "by a service identity"
    refute foreign_text =~ foreign
    assert cadence =~ "by Cadence"
  end

  defp service!(organization_id, name) do
    {:ok, %{service_identity: identity}} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: organization_id,
          display_name: name,
          capabilities: [:mission_admin]
        }),
        %Scope{
          actor_kind: :user,
          organization_id: organization_id,
          user: %User{user_id: "issuer-488"}
        }
      )

    identity.service_identity_id
  end

  defp person!(id, name, organization_id, state \\ :active, capabilities \\ []) do
    Repo.insert!(
      UserRow.changeset(
        User.new(%{
          user_id: id,
          email: "#{id}@example.test",
          display_name: name,
          capabilities: capabilities
        })
      )
    )

    Repo.insert!(
      OrganizationMembershipRow.changeset(
        OrganizationMembership.new(%{
          user_id: id,
          organization_id: organization_id,
          role: :member,
          lifecycle_state: state
        })
      )
    )
  end
end
