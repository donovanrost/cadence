defmodule Cadence.Reads.MemberNamesReadsTest do
  @moduledoc """
  #468 (#146; security checklist 12): Ground & Comms reads name a person only while they hold an
  active membership in the record's organization, checked at read time, and never by email. An
  active member keeps their id, with their name or nil when they have none; anyone else (someone
  who isn't a member, a platform admin from another organization acting in admin mode) reads id
  and name nil (ca-security on #468, as #474 and #487 do).
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures
  import Ecto.Query

  alias Cadence.Accounts.{MemberNames, OrganizationMembershipRow, UserRow}
  alias Cadence.Contacts.{ContactAction, RealizedContact, ScheduleOperation}
  alias Cadence.Management.Providers.ProviderAccountDetail
  alias Cadence.Reads.{ContactStart, PassContactFields, PassEnders}

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission("names")
    %{organization_id: other_org} = configuration_mission("other")

    named = member_scope(org, :member, "Ada")
    nameless = member_scope(org, :member, "Nameless")
    nameless_id = nameless.user.user_id
    Repo.update_all(from(u in UserRow, where: u.user_id == ^nameless_id), set: [display_name: ""])

    # A platform admin from another organization, acting in this one in admin mode.
    admin = member_scope(other_org, :organization_admin, "Pat")

    # Someone who was a member of this organization and was removed (api on #503).
    departed = member_scope(org, :member, "Dee")
    departed_id = departed.user.user_id

    Repo.update_all(
      from(m in OrganizationMembershipRow,
        where: m.organization_id == ^org and m.user_id == ^departed_id
      ),
      set: [lifecycle_state: "revoked"]
    )

    %{
      org: org,
      mission: mission,
      named: named.user,
      nameless: nameless.user,
      admin: admin.user,
      departed: departed.user,
      emails: Enum.map([named, nameless, admin, departed], & &1.user.email)
    }
  end

  defp no_email(view, c), do: for(e <- c.emails, do: refute(inspect(view) =~ e))

  test "who started a contact (Uplink, hand-started passes)", c do
    contacts =
      for user <- [c.named, c.nameless, c.admin, c.departed],
          do: %RealizedContact{
            metadata: %{"started_by" => %{"kind" => "user", "id" => user.user_id}}
          }

    people = ContactStart.people(c.org, contacts)
    starters = Enum.map(contacts, &ContactStart.started_by(&1, people))

    assert [
             %{kind: "user", id: named_id, name: "Ada"},
             %{kind: "user", id: nameless_id, name: nil},
             %{kind: "user", id: nil, name: nil},
             # A removed member of this organization: no name, no id.
             %{kind: "user", id: nil, name: nil}
           ] = starters

    assert named_id == c.named.user_id
    assert nameless_id == c.nameless.user_id
    no_email(starters, c)
  end

  test "who granted and revoked a provider account grant (PA2)", c do
    grant = %{
      provider_account_grant_id: "pag-1",
      version: 1,
      mission_id: c.mission,
      lifecycle_state: :revoked,
      restrictions: %{},
      grant_reason: nil,
      granted_by: c.nameless.user_id,
      granted_at: ~U[2026-11-19 00:00:00Z],
      revoked_by: c.admin.user_id,
      revoked_at: ~U[2026-11-19 01:00:00Z],
      revoke_reason: nil
    }

    row =
      ProviderAccountDetail.grant_row(grant, %{}, ProviderAccountDetail.people(c.org, [grant]))

    assert row.granted_by == %{id: c.nameless.user_id, name: nil}
    assert row.revoked_by == %{id: nil, name: nil}
    no_email(row, c)

    named = %{grant | granted_by: c.named.user_id, revoked_by: nil}

    row =
      ProviderAccountDetail.grant_row(named, %{}, ProviderAccountDetail.people(c.org, [named]))

    assert row.granted_by == %{id: c.named.user_id, name: "Ada"}
  end

  test "who ended a contact early (Passes' contact_ended)", c do
    ended = fn user ->
      action = %ContactAction{
        action_kind: :realized_contact_ended_early,
        actor: %{"kind" => "user", "id" => user.user_id},
        metadata: %{},
        occurred_at: ~U[2026-11-19 00:00:00Z]
      }

      %{ending: action}
      |> PassContactFields.ended(MemberNames.members(c.org, [user.user_id]))
      |> Map.fetch!(:by)
    end

    assert ended.(c.named) == %{kind: "user", id: c.named.user_id, name: "Ada"}
    assert ended.(c.nameless) == %{kind: "user", id: c.nameless.user_id, name: nil}
    assert ended.(c.admin) == %{kind: "user", id: nil, name: nil}
  end

  test "who cancelled a booking (Passes' ended_by)", c do
    reservations =
      for {user, n} <- Enum.with_index([c.named, c.nameless, c.admin]) do
        id = "res-#{n}-#{System.unique_integer([:positive])}"

        Repo.insert!(%ScheduleOperation{
          operation_id: Ecto.UUID.generate(),
          organization_id: c.org,
          mission_id: c.mission,
          user_id: user.user_id,
          action: "cancel",
          input: %{},
          reservation_id: id
        })

        %{provider_reservation_id: id, lifecycle_state: :canceled, metadata: %{}}
      end

    enders = PassEnders.load(c.org, c.mission, reservations)

    assert [
             %{kind: "user", id: named_id, name: "Ada"},
             %{kind: "user", id: nameless_id, name: nil},
             %{kind: "user", id: nil, name: nil}
           ] = Enum.map(reservations, &PassEnders.ended_by(&1, enders))

    assert named_id == c.named.user_id
    assert nameless_id == c.nameless.user_id
    no_email(enders, c)
  end
end
