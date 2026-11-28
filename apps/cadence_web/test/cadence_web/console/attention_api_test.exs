defmodule CadenceWeb.Console.AttentionAPITest do
  @moduledoc "U32: one pass by id with its attention item, and acknowledge / resolve."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Contacts.BookingResolutions.Row
  alias Cadence.Contacts.{ContactStore, RealizedContact}
  alias Cadence.Protocol.RecordArchive.Quarantine
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Reads.ActionQueue.AttentionItems
  alias Cadence.Reads.Attention
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup do
    c = ProviderChangeFixtures.setup_contact()
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, c.organization)
    conflict!(c, user)
    Map.merge(c, %{user: user, base: "/api/v1/missions/#{c.mission_id}"})
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

  test "pass attention matches the mission feed for a booking with several sources", c do
    contact = unsettled_contact!(c)
    now = DateTime.utc_now()

    assert :ok =
             Quarantine.put(
               c.mission_id,
               c.organization_id,
               [
                 %{
                   entry: %{
                     "record_kind" => "frame",
                     "record_id" => "poisoned-frame",
                     "metadata" => %{"realized_contact_id" => contact.realized_contact_id}
                   },
                   error_code: "identity_conflict",
                   error: nil
                 }
               ],
               now
             )

    id = c.reservation.provider_reservation_id
    pass = %{id: id, scheduled_contact_id: c.reservation.scheduled_contact_id}

    assert {:ok, %{items: items}} = Attention.load(c.admin_scope, c.mission_id)
    expected = Enum.filter(items, &(Map.get(&1, :provider_reservation_id) == id))

    assert Enum.map(expected, & &1.source) ==
             ~w(pass_resolution contact_settlement archive_quarantine)

    assert {:ok, ^expected} = Attention.for_passes(c.admin_scope, c.mission_id, [pass])

    assert %{"data" => %{"attentions" => attentions}} =
             c |> conn() |> get(c.base <> "/passes/#{id}") |> json_response(200)

    names = AttentionItems.lookups(c.organization_id, c.mission_id, expected)

    expected_wire =
      for item <- expected do
        {priority, due_at} = AttentionItems.rank(item, now)

        item
        |> AttentionItems.object(names)
        |> Map.merge(%{priority: priority, due_at: due_at})
      end
      |> Jason.encode!()
      |> Jason.decode!()

    assert Enum.sort_by(attentions, & &1["source"]) ==
             Enum.sort_by(expected_wire, & &1["source"])
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

  # #847 (U37): the Contacts drawer reads one pass's settlement item, not the whole action queue.
  describe "GET …/attention/contact_settlement?reservation_id=" do
    setup c do
      unsettled_contact!(c)
      :ok
    end

    test "answers the pass's open item in the queue's wire shape", c do
      id = c.reservation.provider_reservation_id

      assert %{"data" => item} =
               c
               |> conn()
               |> get(c.base <> "/attention/contact_settlement?reservation_id=#{id}")
               |> json_response(200)

      assert %{
               "source" => "contact_settlement",
               "conflict" => "unsettled",
               "reservation_id" => ^id,
               "backlog" => %{"entries" => 120, "lost" => false}
             } = item
    end

    test "answers null for a pass with no open item", c do
      assert %{"data" => nil} =
               c
               |> conn()
               |> get(c.base <> "/attention/contact_settlement?reservation_id=another-booking")
               |> json_response(200)
    end

    test "requires the reservation id", c do
      assert %{"error" => %{"code" => "invalid_params"}} =
               c
               |> conn()
               |> get(c.base <> "/attention/contact_settlement")
               |> json_response(422)
    end
  end

  defp unsettled_contact!(c) do
    now = DateTime.utc_now()

    assert {:ok, contact} =
             ContactStore.persist_realized(
               RealizedContact.new(%{
                 organization_id: c.organization_id,
                 mission_id: c.mission_id,
                 scheduled_contact_id: c.reservation.scheduled_contact_id,
                 initial_time: now,
                 realized_at: now,
                 lifecycle_state: :completed,
                 metadata: %{
                   "settlement" => %{
                     "state" => "unsettled",
                     "reason" => "settle_deadline",
                     "failure_kind" => "store_unavailable",
                     "unsettled_at" => DateTime.to_iso8601(now),
                     "backlog" => %{"entries" => 120, "bytes" => 4096, "journals" => 1}
                   }
                 }
               })
             )

    contact
  end
end
