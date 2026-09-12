defmodule CadenceWeb.OpsContactReviewPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Contacts.{ProviderChangeApprovals, ProviderReservationChanges}
  alias Cadence.ProviderChangeFixtures, as: Fixtures
  alias CadenceWeb.TestFixtures

  @renderer Path.expand(
              "../../../../frontend/modules/planning-and-contacts/src/features/contact-scheduling/contact-workflow-check.mjs",
              __DIR__
            )
  setup do
    c = Fixtures.setup_contact()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, c.organization, role: :organization_admin)

    {:ok, _} =
      Fixtures.advance(c, 2, %{
        "starts_at" => Fixtures.shift(c.baseline["starts_at"], 60),
        "ends_at" => Fixtures.shift(c.baseline["ends_at"], 60)
      })

    [change] =
      ProviderReservationChanges.list_for_reservation(
        c.organization_id,
        c.reservation.provider_reservation_id
      )

    Map.merge(c, %{
      user: user,
      change: change,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{c.mission_id}/ops/contacts/#{c.reservation.provider_reservation_id}"
    })
  end

  test "native provider decision admits long reasons and returns actual persisted evidence", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    assert original["id"] == "planning.reservation-review"
    assert original["status"] == "ready"
    reason = String.duplicate("界", 200)

    [[event, input]] =
      native(%{snapshot: original, action: "approve-provider-change", reason: reason})

    op = action(view, c.path, original, event, input)["snapshot"]
    assert op["status"] == "completed"
    assert op["receipt"]["result"]["actor_id"] == c.user.user_id
    fresh = read(view, c.path, original)["snapshot"]
    assert fresh["data"]["operation"] == op

    assert [[event, input]] ==
             native(%{
               snapshot: original,
               action: event,
               reason: reason,
               operation: op,
               refreshed: fresh
             })

    assert {:ok, approval} =
             ProviderChangeApprovals.fetch(
               c.organization_id,
               c.change.provider_reservation_change_id
             )

    assert approval.reason == reason
    assert action(view, c.path, original, event, input)["snapshot"]["status"] == "rejected"
  end

  test "review pins its selected change while newer provider observations disable decisions", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    [[event, input]] = native(%{snapshot: original, action: "reject-provider-change"})

    {:ok, _} =
      Fixtures.advance(c, 3, %{
        "starts_at" => Fixtures.shift(c.baseline["starts_at"], 120),
        "ends_at" => Fixtures.shift(c.baseline["ends_at"], 120)
      })

    fresh = read(view, c.path, original)["snapshot"]
    assert fresh["data"]["model"]["selected"]["id"] == c.change.provider_reservation_change_id
    assert fresh["data"]["model"]["reservation"]["provider_revision"] == 3
    assert [] == native(%{snapshot: fresh})
    op = action(view, c.path, original, event, input)["snapshot"]
    assert op["status"] == "rejected"

    assert {:error, :provider_change_approval_not_found} =
             ProviderChangeApprovals.fetch(
               c.organization_id,
               c.change.provider_reservation_change_id
             )
  end

  test "record history is a read-only captured contribution and path identities win", c do
    path =
      "/missions/#{c.mission_id}/ops/contacts/records/#{c.reservation.scheduled_contact_id}?sources_page=2&contact_id=foreign"

    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["id"] == "planning.contact-record"
    assert original["status"] == "ready"
    assert original["data"]["model"]["query"]["sources_page"] == 2
    assert original["data"]["model"]["subject"]["id"] == c.reservation.scheduled_contact_id
    assert [] == native(%{snapshot: original})

    assert read(view, path, original)["snapshot"]["data"]["model"]["query"] ==
             original["data"]["model"]["query"]

    assert action(view, path, original, "approve-provider-change", %{sequence: 1, payload: %{}})[
             "ok"
           ] == false
  end

  test "operators cannot decide and captured tokens expire on departure", c do
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, c.organization)
    {:ok, view, _} = live(TestFixtures.member_conn(user), c.path)
    original = page(view)
    refute original["data"]["model"]["permissions"]["decide"]
    assert [] == native(%{snapshot: original})
    render_hook(view, "host:context", %{"path" => "/missions/#{c.mission_id}/ops/contacts"})
    assert_reply(view, %{ok: true})
    assert read(view, c.path, original)["ok"] == false
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp read(view, path, p) do
    render_hook(view, "host:ops-page:read", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"]
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp action(view, path, p, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => p["id"],
      "token" => p["token"],
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp native(supplied) do
    {output, status} =
      System.cmd("node", [@renderer, Jason.encode!(supplied)], stderr_to_stdout: true)

    assert status == 0, output
    assert [_, json] = Regex.run(~r/CONTACT_CONTRIBUTION_INPUT=([^\n]+)/, output)
    Jason.decode!(json)
  end
end
