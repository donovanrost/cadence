defmodule CadenceWeb.Console.PassReleaseAPITest do
  @moduledoc "D2 Release: POST /passes/:id/release (org admins), via the contact workspace's cancel."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.CommandGroupFixtures
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Ingress.ReceiveBackpressure
  alias Cadence.Runtime.IngressBackpressureMonitor, as: BackpressureMonitor
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada Admin")
    member = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-001")

    reservation =
      CommandGroupFixtures.commandable_pass!(
        org.organization_id,
        mission.mission_id,
        craft.spacecraft_id,
        DateTime.add(DateTime.utc_now(), 3_600)
      )

    %{
      admin: admin,
      member: member,
      id: reservation.provider_reservation_id,
      org_id: org.organization_id,
      mission_id: mission.mission_id,
      base: "/api/v1/missions/#{mission.mission_id}"
    }
  end

  defp pass(c, user),
    do:
      user
      |> TestFixtures.member_conn()
      |> get(c.base <> "/passes/#{c.id}")
      |> json_response(200)
      |> Map.fetch!("data")

  defp release(c, user, body),
    do: user |> TestFixtures.member_conn() |> post(c.base <> "/passes/#{c.id}/release", body)

  test "rows say who may release, with the revision to send back", c do
    assert %{"provider_revision" => 1, "releasable" => true, "state" => "confirmed"} =
             pass(c, c.admin)

    assert %{"releasable" => false} = pass(c, c.member)
  end

  test "members can't release; stale or missing revisions are refused", c do
    assert %{"error" => %{"code" => "forbidden"}} =
             c |> release(c.member, %{"expected_provider_revision" => 1}) |> json_response(403)

    assert %{"error" => %{"code" => "pass_changed"}} =
             c |> release(c.admin, %{"expected_provider_revision" => 7}) |> json_response(409)

    assert %{"error" => %{"code" => "invalid_params"}} =
             c |> release(c.admin, %{}) |> json_response(422)

    assert %{"error" => %{"code" => "actor_not_assignable"}} =
             c
             |> release(c.admin, %{"expected_provider_revision" => 1, "user_id" => "x"})
             |> json_response(422)
  end

  test "a cancel the provider didn't take leaves the booking as it was (502)", c do
    # The fixture's provider isn't reachable, so the cancel is never confirmed (domain 4b18d046).
    assert %{"error" => %{"code" => "provider_cancel_failed", "details" => details}} =
             c |> release(c.admin, %{"expected_provider_revision" => 1}) |> json_response(502)

    assert details["state"] in ["confirmed", "unknown"]
    assert details["outcome"] in ["refused", "not_sent", "unknown"]
    assert %{"state" => state} = pass(c, c.admin)
    assert state == details["state"]

    # It raises a pass_release item (domain 548b8dd9), in Now and on the pass row.
    queue =
      c.admin
      |> TestFixtures.member_conn()
      |> get(c.base <> "/action-queue")
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{
             "kind" => "attention",
             "source" => "pass_release",
             "attention" => %{
               "conflict" => "cancel_failed",
               "reservation_id" => id,
               "release" => %{"outcome" => outcome}
             }
           } = Enum.find(queue["items"], &(&1["source"] == "pass_release"))

    assert id == c.id
    assert outcome == details["outcome"]

    assert %{"attention" => %{"source" => "pass_release"} = top, "attentions" => [first | _]} =
             pass(c, c.admin)

    # ux U45: every open item of the pass in Now's order, each with priority and due_at;
    # attention is the first.
    assert first == top
    assert %{"priority" => priority, "due_at" => _} = first
    assert priority in [1, 2, 3]
  end

  # ux U47 / api U45: an ingest-backpressure item shows on its pass row (by reservation), not in
  # the uplink-readiness map, where it would shadow the pass's uplink_blocked item.
  test "a contact's dropped frames join its pass's attentions", c do
    run = "run-" <> c.id

    {:ok, _contact} =
      Cadence.Contacts.persist_realized_contact(
        c.org_id,
        RealizedContact.new(%{
          realized_contact_id: run,
          mission_id: c.mission_id,
          scheduled_contact_id: "contact-" <> c.id
        })
      )

    ReceiveBackpressure.on_full(
      false,
      %{
        mission_id: c.mission_id,
        realized_contact_id: run,
        provider_binding_id: "binding-" <> c.id,
        buffer: :executor
      },
      48
    )

    :ok = BackpressureMonitor.sample_now()

    assert %{"attentions" => attentions} = pass(c, c.admin)

    assert %{"conflict" => "frames_dropped", "drops" => %{"count" => 1}, "reservation_id" => id} =
             Enum.find(attentions, &(&1["source"] == "ingress_backpressure"))

    assert id == c.id
  end
end
