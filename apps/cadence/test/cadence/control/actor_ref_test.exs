defmodule Cadence.Control.ActorRefTest do
  @moduledoc """
  #472 (#462, #146 rule C1, as settled on #487): the shared actor helper names a person only
  while they hold an active membership in the organization being read, checked at read time.
  A member keeps their id, named or not. Anyone outside the organization, a platform admin from
  another organization or someone who left, reads with no name and no id (ca-security). A
  service is named only from its live row in the same organization; the organization's own
  unnamed service keeps its id. Nothing is ever read from a stored document's display_name,
  email or user_email.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceIdentity, ServiceIdentityRow}
  alias Cadence.Control.ActorRef

  @org "org-472"
  @other "org-472-other"

  setup do
    persist_mission_scope(@org, "mission-472")
    persist_mission_scope(@other, "mission-472-other")

    member = person!("member-472", "Mira K.", @org)
    nameless = person!("nameless-472", "Placeholder", @org)
    {1, _} = Repo.update_all(where(UserRow, user_id: "nameless-472"), set: [display_name: ""])
    left = person!("left-472", "Lee Left", @org, :revoked)
    admin = person!("admin-472", "Pat Platform", @other, :active, [:platform_admin])

    %{
      member: member,
      nameless: nameless,
      left: left,
      admin: admin,
      service: service!(@org, "Nightly planner"),
      foreign_service: service!(@other, "Their planner")
    }
  end

  describe "resolve/2 (one id)" do
    test "(a) a member with a display name is named, with their id", c do
      assert ActorRef.resolve(@org, c.member) ==
               %{kind: "user", id: c.member, name: "Mira K."}
    end

    test "(b) a member without a display name keeps their id, with no name", c do
      assert ActorRef.resolve(@org, c.nameless) == %{kind: "user", id: c.nameless, name: nil}
    end

    test "(c) a platform admin from another organization, or someone who left, reads nil", c do
      assert ActorRef.resolve(@org, c.admin) == %{kind: "user", id: nil, name: nil}
      assert ActorRef.resolve(@org, c.left) == %{kind: "user", id: nil, name: nil}
    end

    test "a service of the organization is named from its live row", c do
      assert ActorRef.resolve(@org, c.service) ==
               %{kind: "service", id: c.service, name: "Nightly planner"}
    end

    test "another organization's service gets no name and no id", c do
      assert ActorRef.resolve(@org, c.foreign_service) == %{kind: "service", id: nil, name: nil}
    end

    test "an id that is neither a person nor a service is Cadence's own, unnamed" do
      assert ActorRef.resolve(@org, "cadence:planner") ==
               %{kind: "system", id: "cadence:planner", name: nil}
    end

    test "a nil organization names nobody", c do
      assert ActorRef.resolve(nil, c.member) == %{kind: "user", id: nil, name: nil}
      assert ActorRef.resolve(nil, c.service) == %{kind: "service", id: nil, name: nil}
      # Kept from the drift-sweep test this file replaces: an unknown id is system.
      assert %{kind: "system"} = ActorRef.resolve(nil, "automation:nightly")
    end
  end

  test "the organization's own service with no name keeps its id", c do
    {1, _} =
      Repo.update_all(where(ServiceIdentityRow, service_identity_id: ^c.service),
        set: [display_name: ""]
      )

    assert ActorRef.resolve(@org, c.service) == %{kind: "service", id: c.service, name: nil}
  end

  describe "names/2 and ref/2 (batched)" do
    test "give the same answers as resolve/2", c do
      ids = [c.member, c.nameless, c.left, c.admin, c.service, c.foreign_service, "cadence:x"]
      names = ActorRef.names(@org, ids)

      for id <- ids, do: assert(ActorRef.ref(id, names) == ActorRef.resolve(@org, id))
    end

    test "a nil organization names nobody", c do
      names = ActorRef.names(nil, [c.member, c.service])
      assert ActorRef.ref(c.member, names) == %{kind: "user", id: nil, name: nil}
      assert ActorRef.ref(c.service, names) == %{kind: "service", id: nil, name: nil}
    end
  end

  describe "document/2 (a stored actor document)" do
    test "reads every stored form, naming people only from the live membership", c do
      documents = [
        %{"kind" => "user", "id" => c.member},
        %{"kind" => "user", "user_id" => c.member},
        %{"actor_kind" => "user", "user_id" => c.member},
        %{kind: :user, id: c.member}
      ]

      names = ActorRef.names(@org, documents)

      for document <- documents do
        assert ActorRef.document(document, names) ==
                 %{kind: "user", id: c.member, name: "Mira K."}
      end
    end

    test "never reads a stored display_name, email or user_email", c do
      old = fn id ->
        %{
          "kind" => "user",
          "id" => id,
          "display_name" => "Stored Name",
          "email" => "person@example.test",
          "user_email" => "person@example.test"
        }
      end

      documents = [old.(c.member), old.(c.admin), old.(c.left), old.(c.nameless)]
      names = ActorRef.names(@org, documents)

      # A member is named by their live name, not the stored one.
      assert ActorRef.document(old.(c.member), names) ==
               %{kind: "user", id: c.member, name: "Mira K."}

      assert ActorRef.document(old.(c.nameless), names) ==
               %{kind: "user", id: c.nameless, name: nil}

      for id <- [c.admin, c.left] do
        assert ActorRef.document(old.(id), names) == %{kind: "user", id: nil, name: nil}
      end
    end

    test "services: named from the live row in the organization only", c do
      documents = [
        %{"kind" => "service", "id" => c.service, "display_name" => "Stored"},
        %{"actor_kind" => "service", "service_identity_id" => c.service},
        %{"kind" => "service", "id" => c.foreign_service}
      ]

      names = ActorRef.names(@org, documents)
      [mine, rest, foreign] = Enum.map(documents, &ActorRef.document(&1, names))

      assert mine == %{kind: "service", id: c.service, name: "Nightly planner"}
      assert rest == mine
      assert foreign == %{kind: "service", id: nil, name: nil}
    end

    test "Cadence's own acts keep their stored system name" do
      names = ActorRef.names(@org, [])

      assert ActorRef.document(
               %{"actor_kind" => "system", "system_id" => "cadence:seed", "name" => "Cadence"},
               names
             ) == %{kind: "system", id: "cadence:seed", name: "Cadence"}

      assert ActorRef.document(%{"kind" => "system", "name" => "Cadence"}, names) ==
               %{kind: "system", id: nil, name: "Cadence"}
    end

    test "a form it can't read is nil, never Cadence acting" do
      names = ActorRef.names(@org, [])

      for document <- [
            %{},
            %{"email" => "person@example.test"},
            %{"kind" => "robot", "id" => "r-1"},
            %{"actor_kind" => "user"},
            "user-id-as-a-string",
            nil
          ] do
        assert ActorRef.document(document, names) == nil
      end
    end

    test "a nil organization names nobody", c do
      names = ActorRef.names(nil, [%{"kind" => "user", "id" => c.member}])

      assert ActorRef.document(%{"kind" => "user", "id" => c.member}, names) ==
               %{kind: "user", id: nil, name: nil}
    end
  end

  defp person!(id, name, organization_id, state \\ :active, capabilities \\ []) do
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
          role: :member,
          lifecycle_state: state
        })
      )
    )

    id
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
          user: %User{user_id: "issuer-472"}
        }
      )

    identity.service_identity_id
  end
end
