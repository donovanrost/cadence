defmodule Cadence.Reads.ActorDocumentsTest do
  @moduledoc """
  #468 C (#146; security checklist 12): stored actor documents are named at read time through
  `Cadence.Control.ActorRef`, never by the name stored in them, and the writers store no email.
  An active member of the record's organization is named (or keeps their id with a nil name);
  anyone else (a platform admin from another organization acting in admin mode, a removed member)
  reads id and name nil. Rows written before this change, which may hold an email in "name",
  read the same way with no reset (lead 11-20).
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures
  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}
  alias Cadence.Comms.{GroundStation, GroundStationStore, StationAvailability}
  alias Cadence.Comms.StationAvailability.WindowRow
  alias Cadence.ContactPlanning.PlanSubmissions
  alias Cadence.Control.{ActorRef, PlanConfirmation}
  alias Cadence.Reads.{PassEnders, PlanRounds, StationWindowActors}

  @at ~U[2026-11-20 00:00:00.000000Z]

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission("docs")
    %{organization_id: other_org} = configuration_mission("docs-other")

    named = member_scope(org, :member, "Ada")
    nameless = member_scope(org, :member, "Nameless")
    nameless_id = nameless.user.user_id
    Repo.update_all(from(u in UserRow, where: u.user_id == ^nameless_id), set: [display_name: ""])

    # A platform admin from another organization, acting in this one in admin mode.
    admin = member_scope(other_org, :organization_admin, "Pat")

    # Someone who was a member of this organization and was removed.
    departed = member_scope(org, :member, "Dee")
    departed_id = departed.user.user_id

    Repo.update_all(
      from(m in OrganizationMembershipRow,
        where: m.organization_id == ^org and m.user_id == ^departed_id
      ),
      set: [lifecycle_state: "revoked"]
    )

    people = [named, nameless, admin, departed]

    %{
      org: org,
      mission: mission,
      scopes: %{named: named, nameless: nameless},
      users: Enum.map(people, & &1.user),
      emails: Enum.map(people, & &1.user.email)
    }
  end

  # A document as Cadence stored it before #468: the name fell back to the email.
  defp old_doc(user), do: %{"kind" => "user", "id" => user.user_id, "name" => user.email}

  defp no_email(view, c), do: for(e <- c.emails, do: refute(inspect(view) =~ e))

  # Named member, nameless member (id kept), outsider and removed member (neither).
  defp assert_rule([named, nameless, outsider, departed], c) do
    [ada, nobody | _] = c.users
    assert %{kind: "user", id: ada_id, name: "Ada"} = named
    assert ada_id == ada.user_id
    assert %{kind: "user", id: nobody_id, name: nil} = nameless
    assert nobody_id == nobody.user_id
    assert %{kind: "user", id: nil, name: nil} = outsider
    assert %{kind: "user", id: nil, name: nil} = departed
  end

  test "station windows: a new window stores no email; older ones read by membership", c do
    station = unique("svb")

    {:ok, _} =
      GroundStationStore.persist_ground_station(
        c.org,
        GroundStation.new(%{
          ground_station_id: station,
          mission_id: c.mission,
          display_name: "Svalbard",
          code: "SVB"
        })
      )

    assert {:ok, %{id: new_id}} =
             StationAvailability.schedule(c.scopes.named, c.mission, station, %{
               kind: :maintenance,
               starts_at: DateTime.add(@at, 3600),
               ends_at: DateTime.add(@at, 7200)
             })

    stored = Repo.get!(WindowRow, new_id).reported_by
    assert stored["id"] == c.scopes.named.user.user_id
    refute Map.has_key?(stored, "email")
    no_email(stored, c)

    # Rows written before #468, each holding the email in "name"; later windows, one per person.
    for {user, n} <- Enum.with_index(c.users, 1) do
      Repo.insert!(%WindowRow{
        window_id: unique("win"),
        organization_id: c.org,
        mission_id: c.mission,
        ground_station_id: station,
        kind: "degraded",
        source: "operator",
        starts_at: DateTime.add(@at, n * 86_400),
        ends_at: DateTime.add(@at, n * 86_400 + 600),
        reported_by: old_doc(user)
      })
    end

    {:ok, windows} =
      StationAvailability.windows(
        c.scopes.named,
        c.mission,
        station,
        @at,
        DateTime.add(@at, 9, :day)
      )

    [_new | old] = windows |> StationWindowActors.named(c.org) |> Enum.sort_by(& &1.from)
    assert_rule(Enum.map(old, & &1.reported_by), c)
    assert Enum.map(old, & &1.created_by) == Enum.map(old, & &1.reported_by)
    no_email(old, c)
  end

  test "plan rounds: an older round holding an email names its submitter by membership", c do
    plan_id = unique("plan")

    for user <- c.users do
      {:ok, _round} =
        PlanSubmissions.record(%{
          organization_id: c.org,
          mission_id: c.mission,
          contact_plan_id: plan_id,
          contact_plan_version: length(c.users) - Enum.find_index(c.users, &(&1 == user)),
          actor_document: old_doc(user)
        })
    end

    actors =
      for version <- 4..1//-1,
          do: PlanRounds.load(c.org, c.mission, plan_id, version).submission.actor

    assert_rule(actors, c)
    no_email(actors, c)
  end

  test "plan confirmation: an operator's resolution names who by membership", c do
    items =
      for {user, n} <- Enum.with_index(c.users) do
        %{
          contact_opportunity_snapshot_id: "s#{n}",
          lifecycle_state: :failed,
          provider_reservation_id: "r#{n}",
          last_error_document: %{
            "code" => "operator_not_booked",
            "resolved_by" => old_doc(user),
            "resolved_at" => "2026-11-20T10:52:00Z"
          },
          started_at: nil,
          completed_at: nil,
          updated_at: @at
        }
      end

    names = ActorRef.names(c.org, Enum.map(items, & &1.last_error_document["resolved_by"]))
    bookings = PlanConfirmation.bookings(items, names)
    by = for n <- 0..3, do: bookings["s#{n}"].resolved.by
    assert_rule(by, c)
    no_email(bookings, c)
  end

  test "pass enders: a #53 resolution holding an email names who by membership", c do
    reservations =
      for {user, n} <- Enum.with_index(c.users) do
        %{
          provider_reservation_id: "res-#{n}-#{System.unique_integer([:positive])}",
          lifecycle_state: :failed,
          metadata: %{
            "operator_resolution" => %{"action" => "not_booked", "actor" => old_doc(user)}
          }
        }
      end

    enders = PassEnders.load(c.org, c.mission, reservations)
    assert_rule(Enum.map(reservations, &PassEnders.ended_by(&1, enders)), c)
    no_email(enders, c)
  end
end
