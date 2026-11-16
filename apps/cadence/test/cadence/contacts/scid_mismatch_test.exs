defmodule Cadence.Contacts.ScidMismatchTest do
  @moduledoc "The frame-SCID cross-check on the contact record (DECISIONS #102, ux U81 §2)."
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Contacts.{
    ContactSettlement,
    ContactStore,
    RealizedContact,
    ScidMismatch,
    ScidMismatchAttention
  }

  alias Cadence.OperationalEvents.EventRow

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission("scid-mismatch")
    %{org: org, mission: mission}
  end

  describe "settlement_entries/2 and most?/1" do
    test "every checked path gets an entry once any path refused; counts and SCIDs per path" do
      checks = [
        check("path-a", 100, %{3 => 60, 7 => 2}),
        check("path-b", 40, %{})
      ]

      assert [a, b] = ScidMismatch.settlement_entries(checks, "station-fbk")

      assert a == %{
               "path_id" => "path-a",
               "provider_binding_id" => "binding-path-a",
               "ground_station_ref" => "station-fbk",
               "spacecraft_id" => "sc-1",
               "expected_scid" => 1,
               "frames" => 62,
               "frames_total" => 100,
               "scids" => [3, 7],
               "scid_count" => 2
             }

      assert %{"path_id" => "path-b", "frames" => 0, "frames_total" => 40} = b
      assert ScidMismatch.settlement_entries([check("path-b", 40, %{})], nil) == []
    end

    test "scids stop at 8; scid_count doesn't" do
      refused = Map.new(1..12, &{&1 + 100, 1})
      assert [entry] = ScidMismatch.settlement_entries([check("p", 20, refused)], nil)
      assert entry["scids"] == Enum.to_list(101..108)
      assert entry["scid_count"] == 12
    end

    test "most is MORE than half of the contact's frames, over all its paths" do
      assert ScidMismatch.most?([entry(51, 100)])
      refute ScidMismatch.most?([entry(50, 100)])
      # 62 of (100 + 40): 44%, because the clean path's frames count too.
      refute ScidMismatch.most?([entry(62, 100), entry(0, 40)])
      refute ScidMismatch.most?([])
    end
  end

  describe "ContactSettlement.record/7" do
    test "stores the key, raises one event when most were refused, and a later empty read keeps it",
         ctx do
      contact = contact!(ctx, settled_at: nil)
      checks = [check("path-a", 430, %{3 => 412})]

      assert {:ok, _} = ContactSettlement.record(contact, :settled, %{}, :ok, nil, [], checks)
      assert [%{"frames" => 412, "frames_total" => 430}] = entries(ctx, contact)

      event_id = "operational_event:contact_scid_mismatch:#{contact.realized_contact_id}"

      assert %EventRow{kind: "contact_scid_mismatch", severity: "warning"} =
               event = event(event_id)

      assert %{
               "expected_scid" => 1,
               "frames" => 412,
               "frames_total" => 430,
               "scids" => [3],
               "scid_count" => 1,
               "spacecraft_id" => "sc-1",
               "contact_started_at" => started_at
             } = event.payload_document["value"]

      assert started_at == DateTime.to_iso8601(contact.realized_at)
      assert %{"realized_contact_id" => _, "spacecraft_id" => "sc-1"} = event.scope_document["value"]

      {:ok, again} = ContactStore.fetch_realized(ctx.mission, contact.realized_contact_id)
      assert {:ok, _} = ContactSettlement.record(again, :absent, %{}, :ok, nil, [], [])
      assert [%{"frames" => 412}] = entries(ctx, contact)
      assert Repo.aggregate(from(e in EventRow, where: e.event_id == ^event_id), :count) == 1
    end

    test "half or fewer refused: the key only, no event", ctx do
      contact = contact!(ctx, settled_at: nil)
      checks = [check("path-a", 100, %{3 => 50})]

      assert {:ok, _} = ContactSettlement.record(contact, :settled, %{}, :ok, nil, [], checks)
      assert [%{"frames" => 50}] = entries(ctx, contact)

      assert event("operational_event:contact_scid_mismatch:#{contact.realized_contact_id}") ==
               nil
    end
  end

  describe "ScidMismatchAttention" do
    test "a settled pass where most frames were refused is open until marked seen", ctx do
      raised = contact!(ctx, entries: [entry(412, 430)])
      _below = contact!(ctx, entries: [entry(10, 430)])
      scope = member_scope(ctx.org, :member, "Alice")
      id = raised.realized_contact_id

      assert [item] = ScidMismatchAttention.items(ctx.org, ctx.mission)

      assert %{
               id: ^id,
               source: "contact_scid_mismatch",
               state: "open",
               realized_contact_id: ^id,
               spacecraft_id: "sc-1",
               scid_mismatch: [%{"frames" => 412}]
             } = item

      assert ScidMismatchAttention.counts(ctx.org, ctx.mission) == %{open: 1, acknowledged: 0}

      assert {:ok, %{state: "resolved", resolution: %{action: "seen", actor: actor}}} =
               ScidMismatchAttention.acknowledge(scope, ctx.mission, id)

      assert actor["name"] == "Alice"
      assert ScidMismatchAttention.items(ctx.org, ctx.mission) == []

      assert {:error, :attention_item_not_found} =
               ScidMismatchAttention.acknowledge(scope, ctx.mission, id)

      since = DateTime.add(DateTime.utc_now(), -60)

      assert [%{id: ^id, action: "seen", resolved_by: %{"kind" => "user"}}] =
               ScidMismatchAttention.resolved_since(ctx.org, ctx.mission, since)
    end

    test "never seen, it retires 7 days after settle, by the system", ctx do
      settled = DateTime.add(DateTime.utc_now(), -8 * 86_400)
      old = contact!(ctx, entries: [entry(412, 430)], settled_at: settled)
      id = old.realized_contact_id

      assert ScidMismatchAttention.items(ctx.org, ctx.mission) == []
      retired_at = DateTime.add(settled, 7 * 86_400)

      assert [%{id: ^id, action: "retired", resolved_by: %{"kind" => "system"}, resolved_at: at}] =
               ScidMismatchAttention.resolved_since(
                 ctx.org,
                 ctx.mission,
                 DateTime.add(retired_at, -60)
               )

      assert DateTime.compare(at, retired_at) == :eq
    end
  end

  defp check(path_id, frames, refused),
    do: %{
      path_id: path_id,
      provider_binding_id: "binding-" <> path_id,
      expected_scid: 1,
      spacecraft_id: "sc-1",
      frames: frames,
      refused: refused
    }

  defp entry(frames, total),
    do: %{
      "path_id" => "path-#{frames}",
      "spacecraft_id" => "sc-1",
      "expected_scid" => 1,
      "frames" => frames,
      "frames_total" => total,
      "scids" => [3],
      "scid_count" => 1
    }

  defp contact!(ctx, opts) do
    settled_at =
      Keyword.get_lazy(opts, :settled_at, fn -> DateTime.add(DateTime.utc_now(), -60) end)

    realized_at =
      DateTime.add(settled_at || DateTime.utc_now(), -900) |> DateTime.truncate(:microsecond)

    settlement =
      case {settled_at, Keyword.get(opts, :entries)} do
        {nil, _entries} ->
          %{}

        {at, entries} ->
          %{"state" => "settled", "settled_at" => DateTime.to_iso8601(at)}
          |> then(&if entries, do: Map.put(&1, "scid_mismatch", entries), else: &1)
      end

    {:ok, contact} =
      ContactStore.persist_realized(
        RealizedContact.new(%{
          realized_contact_id: unique("realized"),
          organization_id: ctx.org,
          mission_id: ctx.mission,
          source_endpoint_refs: [],
          clock_mode: :live,
          initial_time: realized_at,
          realized_at: realized_at,
          lifecycle_state: :completed,
          metadata: %{"settlement" => settlement}
        })
      )

    contact
  end

  defp entries(ctx, contact) do
    {:ok, current} = ContactStore.fetch_realized(ctx.mission, contact.realized_contact_id)
    ScidMismatch.entries(current)
  end

  defp event(event_id), do: Repo.get_by(EventRow, event_id: event_id)
end
