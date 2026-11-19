defmodule CadenceWeb.Console.AttentionAPITest do
  @moduledoc "U32: one pass by id with its attention item, and acknowledge / resolve."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Contacts.BookingResolutions.Row
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup do
    c = ProviderChangeFixtures.setup_contact()
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, c.organization)
    conflict!(c, user)
    Map.merge(c, %{user: user, base: "/api/console/v1/missions/#{c.mission_id}"})
  end

  defp conflict!(c, user) do
    r = c.reservation

    %{
      booking_resolution_id: "br-1",
      organization_id: c.organization_id,
      mission_id: c.mission_id,
      contact_plan_id: "plan-1",
      contact_plan_version: 1,
      contact_plan_execution_item_id: "item-1",
      provider_reservation_id: r.provider_reservation_id,
      spacecraft_id: r.spacecraft_id,
      ground_station_ref: "svb",
      provider_id: r.provider_id,
      starts_at: r.starts_at,
      ends_at: r.ends_at,
      action: "not_booked",
      outcome: "not_booked",
      note: "Not on the provider's schedule",
      actor_document: %{"kind" => "user", "id" => user.user_id, "name" => "Mira K."}
    }
    |> Row.changeset()
    |> Repo.insert!()
    |> Row.conflict_changeset(
      "cancel_failed",
      %{"provider_message" => "Too late"},
      DateTime.utc_now()
    )
    |> Repo.update!()
  end

  defp conn(c), do: TestFixtures.member_conn(c.user)

  test "one pass by id carries its booking evidence and attention item", c do
    id = c.reservation.provider_reservation_id

    data =
      c |> conn() |> get(c.base <> "/passes/#{id}") |> json_response(200) |> Map.fetch!("data")

    assert %{
             "id" => ^id,
             "booking_evidence" => _,
             "attested_by" => nil,
             "uplink_confirmed" => nil,
             "attention" => %{
               "id" => "br-1",
               "source" => "pass_resolution",
               "conflict" => "cancel_failed",
               "state" => "open",
               "reservation_id" => ^id,
               "provider_message" => "Too late",
               "station" => %{"ref" => "svb"}
             }
           } = data

    assert %{"error" => %{"code" => "pass_not_found"}} =
             c |> conn() |> get(c.base <> "/passes/nope") |> json_response(404)
  end

  test "acknowledge, then resolve, as the signed-in user", c do
    path = c.base <> "/attention/pass_resolution/br-1"

    assert %{"data" => %{"state" => "acknowledged", "acknowledged_by" => by}} =
             c |> conn() |> post(path <> "/acknowledge") |> json_response(200)

    assert by["id"] == c.user.user_id

    assert %{"error" => %{"code" => "attention_item_not_open"}} =
             c |> conn() |> post(path <> "/acknowledge") |> json_response(409)

    assert %{"data" => %{"state" => "resolved", "id" => "br-1"}} =
             c
             |> conn()
             |> post(path <> "/resolve", %{
               "action_text" => "Called Northlight; cancel confirmed."
             })
             |> json_response(200)

    assert %{"error" => %{"code" => "attention_item_not_open"}} =
             c
             |> conn()
             |> post(path <> "/resolve", %{"action_text" => "Again"})
             |> json_response(409)
  end

  test "rejects a named actor, a missing action text and unknown items", c do
    path = c.base <> "/attention/pass_resolution/br-1"

    assert %{"error" => %{"code" => "actor_not_assignable"}} =
             c
             |> conn()
             |> post(path <> "/resolve", %{"action_text" => "x", "resolved_by" => "someone"})
             |> json_response(422)

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"action_text" => _}}} =
             c
             |> conn()
             |> post(path <> "/resolve", %{"action_text" => "  "})
             |> json_response(422)

    too_long = String.duplicate("a", 201)

    assert %{"error" => %{"code" => "invalid_params"}} =
             c
             |> conn()
             |> post(path <> "/resolve", %{"action_text" => too_long})
             |> json_response(422)

    # contact_settlement (#71) closes by itself: acknowledge and resolve are refused cleanly.
    for missing <- [
          "/attention/pass_resolution/nope",
          "/attention/provider_change/br-1",
          "/attention/contact_settlement/realized-1"
        ] do
      assert %{"error" => %{"code" => "attention_item_not_found"}} =
               c |> conn() |> post(c.base <> missing <> "/acknowledge") |> json_response(404)
    end

    # Retry exists only for contact_settlement, and only on an open item (#71 replay).
    for path <- [
          "/attention/contact_settlement/realized-1/retry",
          "/attention/pass_resolution/br-1/retry"
        ] do
      assert %{"error" => %{"code" => "attention_item_not_found"}} =
               c |> conn() |> post(c.base <> path) |> json_response(404)
    end

    assert %{"error" => %{"code" => "attention_item_not_found"}} =
             c
             |> conn()
             |> post(c.base <> "/attention/contact_settlement/realized-1/resolve", %{
               "action_text" => "stored"
             })
             |> json_response(404)
  end
end
