defmodule CadenceWeb.Console.PassSecondConnectionsAPITest do
  @moduledoc """
  U50: the selected pass (GET …/passes/:id) carries second_connections_refused: connections its
  shared listener refused while the pass's own was up, live or as recorded at LOS; null without a
  realized contact.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Contacts
  alias Cadence.Contacts.RealizedContact
  alias Cadence.ProviderChangeFixtures
  alias CadenceWeb.TestFixtures

  setup do
    booked = ProviderChangeFixtures.setup_contact()
    user = TestFixtures.persist_user!(display_name: "Operator")
    TestFixtures.grant_membership!(user, booked.organization, role: :organization_admin)

    %{
      booked: booked,
      conn: TestFixtures.member_conn(user),
      path:
        "/api/v1/missions/#{booked.mission_id}/passes/#{booked.reservation.provider_reservation_id}"
    }
  end

  defp pass(c), do: c.conn |> get(c.path) |> json_response(200) |> Map.fetch!("data")

  test "null before the pass has a realized contact", c do
    assert Map.has_key?(pass(c), "second_connections_refused")
    assert pass(c)["second_connections_refused"] == nil
  end

  test "the count the settler recorded at LOS, summed over the contact's bindings", c do
    {:ok, _} =
      Contacts.persist_realized_contact(
        c.booked.organization_id,
        RealizedContact.new(%{
          realized_contact_id: "rc-second-connections",
          organization_id: c.booked.organization_id,
          mission_id: c.booked.mission_id,
          scheduled_contact_id: c.booked.reservation.scheduled_contact_id,
          source_endpoint_refs: [],
          paths: [],
          realized_at: ~U[2026-11-14 12:10:57.000000Z],
          metadata: %{
            "listener_refusal" => %{
              "binding-a" => %{"second_connections_refused" => 2},
              "binding-b" => %{"second_connections_refused" => 1}
            }
          }
        })
      )

    assert pass(c)["second_connections_refused"] == 3
  end
end
