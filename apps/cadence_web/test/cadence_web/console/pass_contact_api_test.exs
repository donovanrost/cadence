defmodule CadenceWeb.Console.PassContactAPITest do
  @moduledoc """
  U55 over HTTP: a pass row says whether its contact can be canceled or ended (contact_action) and
  how it ended (contact_ended); cancel needs a reason, never touches the booking, and refuses with
  the state once it can't; the detail carries queued_commands and window_moves.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.ProviderChangeFixtures
  alias CadenceWeb.TestFixtures

  setup do
    booked = ProviderChangeFixtures.setup_contact()
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, booked.organization, role: :organization_admin)
    id = booked.reservation.provider_reservation_id

    %{
      booked: booked,
      user: user,
      conn: TestFixtures.member_conn(user),
      path: "/api/console/v1/missions/#{booked.mission_id}/passes/#{id}"
    }
  end

  defp pass(c), do: c.conn |> get(c.path) |> json_response(200) |> Map.fetch!("data")

  test "a booked pass before AOS offers cancel; the detail has the queued line and no moves", c do
    assert %{
             "contact_action" => "cancel",
             "contact_ended" => nil,
             "window_moves" => [],
             "telemetry_stored" => nil,
             "incomplete_at_end" => nil,
             "scid_mismatch" => nil,
             "queued_commands" => %{"count" => 0, "expiring_before_next" => nil}
           } = pass(c)
  end

  test "cancel needs a reason, records who and why, and refuses once it's done", c do
    assert %{
             "error" => %{
               "code" => "invalid_params",
               "details" => %{"reason" => "Give a reason first."}
             }
           } =
             c.conn
             |> post(c.path <> "/cancel-contact", %{"reason" => "  "})
             |> json_response(422)

    user_id = c.user.user_id

    assert %{
             "data" => %{
               "contact_action" => nil,
               "contact_ended" => %{
                 "kind" => "canceled",
                 "cause" => "operator",
                 "by" => %{"kind" => "user", "id" => ^user_id, "name" => "Mira K."},
                 "reason" => "Antenna maintenance",
                 "reason_code" => nil,
                 "at" => at
               },
               "state" => state
             }
           } =
             c.conn
             |> post(c.path <> "/cancel-contact", %{"reason" => " Antenna maintenance "})
             |> json_response(200)

    # lead 11-14: a new cancel never yields a null cause, by or at (nulls are legacy rows only).
    assert {:ok, _at, 0} = DateTime.from_iso8601(at)
    ended = pass(c)["contact_ended"]
    assert Enum.all?(~w(cause by at), &(not is_nil(ended[&1])))

    # The booking isn't touched (Release is separate).
    assert state == to_string(c.booked.reservation.lifecycle_state)

    assert %{
             "error" => %{
               "code" => "contact_not_cancelable",
               "details" => %{"state" => "canceled"}
             }
           } =
             c.conn
             |> post(c.path <> "/cancel-contact", %{"reason" => "Again"})
             |> json_response(409)

    assert %{"error" => %{"code" => "contact_not_live", "details" => %{"state" => "canceled"}}} =
             c.conn |> post(c.path <> "/end-contact", %{"reason" => "Stop"}) |> json_response(409)
  end

  test "end before the contact is live says it hasn't started", c do
    assert %{"error" => %{"code" => "contact_not_live", "details" => %{"state" => "not_started"}}} =
             c.conn |> post(c.path <> "/end-contact", %{"reason" => "Stop"}) |> json_response(409)
  end
end
