defmodule CadenceWeb.Console.PassHandStartedAPITest do
  @moduledoc """
  U78 over HTTP: GET /passes/:id also takes a scheduled or realized contact id (the booking's row,
  or a hand-started contact's `booked: false` row), scoped to the mission; writes still take
  reservation ids only; and the list adds hand-started rows only with include=hand_started.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Contacts.ContactStore
  alias Cadence.Contacts.RealizedContact
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Reads.Passes
  alias CadenceWeb.TestFixtures

  setup do
    booked = ProviderChangeFixtures.setup_contact()
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, booked.organization, role: :organization_admin)
    starts_at = booked.reservation.starts_at

    stopped =
      hand!(booked, "stopped", DateTime.add(starts_at, 120), :stopped, %{
        "stopped_at" => DateTime.to_iso8601(DateTime.add(starts_at, 300)),
        "started_by" => %{"kind" => "user", "id" => user.user_id}
      })

    %{
      booked: booked,
      user: user,
      stopped: stopped,
      conn: TestFixtures.member_conn(user),
      base: "/api/console/v1/missions/#{booked.mission_id}/passes"
    }
  end

  defp hand!(booked, name, realized_at, state, metadata, mission_id \\ nil) do
    contact =
      RealizedContact.new(%{
        realized_contact_id: "realized-hand-#{name}-#{System.unique_integer([:positive])}",
        organization_id: booked.organization_id,
        mission_id: mission_id || booked.mission_id,
        scheduled_contact_id: nil,
        source_endpoint_refs: [],
        clock_mode: :live,
        realized_at: realized_at
      })

    {:ok, contact} = Cadence.Contacts.persist_realized_contact(booked.organization_id, contact)

    if state == :defined do
      contact
    else
      {:ok, contact} = ContactStore.update_realized_lifecycle(contact, state, metadata)
      contact
    end
  end

  defp booked_realized!(booked) do
    contact =
      RealizedContact.new(%{
        realized_contact_id: "realized-booked-#{System.unique_integer([:positive])}",
        organization_id: booked.organization_id,
        mission_id: booked.mission_id,
        scheduled_contact_id: booked.reservation.scheduled_contact_id,
        source_endpoint_refs: booked.reservation.source_endpoint_refs,
        clock_mode: :live,
        realized_at: booked.reservation.starts_at
      })

    {:ok, contact} = Cadence.Contacts.persist_realized_contact(booked.organization_id, contact)
    contact
  end

  defp show(c, id, base \\ nil), do: c.conn |> get("#{base || c.base}/#{id}")

  defp list(c, query) do
    from = c.booked.reservation.starts_at |> DateTime.add(-1800) |> DateTime.to_iso8601()
    to = c.booked.reservation.starts_at |> DateTime.add(3600) |> DateTime.to_iso8601()

    c.conn
    |> get(c.base <> "?" <> URI.encode_query(Map.merge(%{"from" => from, "to" => to}, query)))
    |> json_response(200)
    |> get_in(["data", "passes"])
  end

  describe "GET /passes/:id by contact id" do
    test "a scheduled or a booked realized id gives the booking's own row, never booked: false",
         c do
      reservation_id = c.booked.reservation.provider_reservation_id
      realized = booked_realized!(c.booked)

      for id <- [
            reservation_id,
            c.booked.reservation.scheduled_contact_id,
            realized.realized_contact_id
          ] do
        assert %{"data" => %{"id" => ^reservation_id, "booked" => true}} =
                 c |> show(id) |> json_response(200)
      end
    end

    test "a hand-started contact's realized id gives its booked: false row", c do
      id = c.stopped.realized_contact_id
      user_id = c.user.user_id

      assert %{"data" => row} = c |> show(id) |> json_response(200)

      assert %{
               "id" => ^id,
               "realized_contact_id" => ^id,
               "kind" => "contact",
               "booked" => false,
               "state" => "stopped",
               "reservation_id" => nil,
               "scheduled_contact_id" => nil,
               "source" => nil,
               "plan" => nil,
               "provider_revision" => nil,
               "releasable" => false,
               "contact_action" => nil,
               "contact_ended" => nil,
               "started_by" => %{"kind" => "user", "id" => ^user_id, "name" => "Mira K."},
               "provider_changes" => [],
               "window_moves" => [],
               "queued_command_groups" => %{"count" => 0, "next_pass" => nil}
             } = row

      starts_at = DateTime.add(c.booked.reservation.starts_at, 120)
      ends_at = DateTime.add(c.booked.reservation.starts_at, 300)
      assert {:ok, ^starts_at, 0} = DateTime.from_iso8601(row["starts_at"])
      assert {:ok, ^ends_at, 0} = DateTime.from_iso8601(row["ends_at"])
    end

    test "an active hand-started contact is never releasable, even for an org admin", c do
      active = hand!(c.booked, "active", DateTime.utc_now(), :active, %{})

      assert %{"data" => %{"state" => "active", "releasable" => false, "booked" => false}} =
               c |> show(active.realized_contact_id) |> json_response(200)
    end

    test "another mission's contact ids are 404, both ways", c do
      other_id = "mission-other-#{System.unique_integer([:positive])}"
      Cadence.DataCase.persist_mission_scope(c.booked.organization_id, other_id)
      theirs = hand!(c.booked, "theirs", DateTime.utc_now(), :defined, %{}, other_id)

      assert %{"error" => %{"code" => "pass_not_found"}} =
               c |> show(theirs.realized_contact_id) |> json_response(404)

      other_base = "/api/console/v1/missions/#{other_id}/passes"

      for id <- [
            c.stopped.realized_contact_id,
            c.booked.reservation.scheduled_contact_id,
            c.booked.reservation.provider_reservation_id
          ] do
        assert %{"error" => %{"code" => "pass_not_found"}} =
                 c |> show(id, other_base) |> json_response(404)
      end
    end

    test "an unknown id is 404 pass_not_found", c do
      assert %{"error" => %{"code" => "pass_not_found"}} =
               c |> show("no-such-contact") |> json_response(404)
    end
  end

  describe "writes take reservation ids only" do
    test "release, recover-uplink and contact cancel/end refuse contact ids with 404", c do
      ids = [c.stopped.realized_contact_id, c.booked.reservation.scheduled_contact_id]

      for id <- ids do
        assert %{"error" => %{"code" => "pass_not_found"}} =
                 c.conn
                 |> post("#{c.base}/#{id}/release", %{"expected_provider_revision" => 1})
                 |> json_response(404)

        assert %{"error" => %{"code" => "pass_not_found"}} =
                 c.conn |> post("#{c.base}/#{id}/recover-uplink", %{}) |> json_response(404)

        for action <- ~w(cancel-contact end-contact) do
          assert %{"error" => %{"code" => "pass_not_found"}} =
                   c.conn
                   |> post("#{c.base}/#{id}/#{action}", %{"reason" => "Wrong pass"})
                   |> json_response(404)
        end
      end
    end
  end

  describe "GET /passes?include=hand_started" do
    test "without include there are no hand-started rows; booked rows say booked: true", c do
      rows = list(c, %{})
      assert Enum.map(rows, & &1["booked"]) == [true]
    end

    test "with include they join in start order, either way, and filter by their own state", c do
      started_before =
        hand!(c.booked, "open", DateTime.add(c.booked.reservation.starts_at, -7200), :active, %{})

      _ended_before =
        hand!(c.booked, "old", DateTime.add(c.booked.reservation.starts_at, -9000), :stopped, %{
          "stopped_at" =>
            c.booked.reservation.starts_at |> DateTime.add(-3600) |> DateTime.to_iso8601()
        })

      reservation_id = c.booked.reservation.provider_reservation_id

      expected = [
        started_before.realized_contact_id,
        reservation_id,
        c.stopped.realized_contact_id
      ]

      assert c |> list(%{"include" => "hand_started"}) |> Enum.map(& &1["id"]) == expected

      assert c
             |> list(%{"include" => "hand_started", "order" => "desc"})
             |> Enum.map(& &1["id"]) == Enum.reverse(expected)

      assert [%{"id" => id, "booked" => false}] =
               list(c, %{"include" => "hand_started", "states" => "stopped"})

      assert id == c.stopped.realized_contact_id

      assert [%{"id" => ^reservation_id}] =
               list(c, %{"include" => "hand_started", "states" => "confirmed,active"})
               |> Enum.filter(& &1["booked"])
    end

    test "the merged list is cut to the limit in its order and says truncated", c do
      starts_at = c.booked.reservation.starts_at
      from = DateTime.add(starts_at, -1800)
      to = DateTime.add(starts_at, 3600)
      reservation_id = c.booked.reservation.provider_reservation_id
      stopped_id = c.stopped.realized_contact_id

      for {order, first} <- [asc: reservation_id, desc: stopped_id] do
        assert %{passes: [%{id: ^first}], truncated: true} =
                 Passes.load(c.booked.organization_id, c.booked.mission_id, from, to, %{
                   hand_started: true,
                   order: order,
                   limit: 1
                 })
      end
    end

    test "rejects an unknown include or order", c do
      for query <- ["?include=everything", "?order=sideways"] do
        assert %{"error" => %{"code" => "invalid_params"}} =
                 c.conn |> get(c.base <> query) |> json_response(422)
      end
    end
  end
end
