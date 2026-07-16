defmodule CadenceSimulator.Provider.ContactLifecycleTest do
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{ContactChanges, Contacts, EventDelivery, Store}
  alias CadenceSimulator.TestProviderFixtures

  setup do
    :ok = Store.clear()
    :ok
  end

  test "provider changes append immutable history and emit revision-correlated events" do
    context = TestProviderFixtures.create_contact!()
    contact = context.contact

    assert {:ok, changed} =
             ContactChanges.apply(
               context.run,
               contact["id"],
               %{
                 "type" => "timing_shift",
                 "start_shift_seconds" => 60,
                 "end_shift_seconds" => 60
               },
               request_id: "provider-change-request"
             )

    assert changed["revision"] == 2
    assert {:ok, internal} = Contacts.fetch_internal(contact["id"])

    assert [history] = internal["modification_history"]
    assert history["from_revision"] == 1
    assert history["to_revision"] == 2
    assert history["source"] == "provider"

    event =
      Store.events(0, 100).data
      |> Enum.find(&(&1["type"] == "contact.modified"))

    assert event["resource_revision"] == 2
    assert event["request_id"] == "provider-change-request"
    assert event["data"]["provider_change"]["type"] == "timing_shift"
    assert event["data"]["changed_fields"]["starts_at"]["before"] == contact["starts_at"]
  end

  test "event delay and omission advance only according to declared provider behavior" do
    context = TestProviderFixtures.create_contact!()

    {:ok, run} =
      Provider.configure_run_faults(context.run["id"], %{
        "event_delay_poll_count" => 1,
        "event_omission_count" => 1
      })

    assert %{data: [], next_cursor: 0} = EventDelivery.page(run, 0, 100)

    raw = Store.events_for_run(run["id"], 0, 100)
    omitted = EventDelivery.page(run, 0, 100)

    assert length(omitted.data) == length(raw.data) - 1
    assert omitted.next_cursor == raw.next_cursor
    refute Enum.any?(omitted.data, &(&1["sequence"] == hd(raw.data)["sequence"]))
  end

  test "event duplication, reordering, and identity collision are explicit deterministic faults" do
    duplicate = fault_page("event_duplication_count")
    assert [first, second | _rest] = duplicate.data
    assert first == second

    reordered = fault_page("event_reordering_count")
    sequences = Enum.map(reordered.data, & &1["sequence"])
    assert sequences == Enum.sort(sequences, :desc)

    collision = fault_page("event_identity_collision_count")
    assert [original, conflicting | _rest] = collision.data
    assert original["id"] == conflicting["id"]
    assert original["sequence"] == conflicting["sequence"]
    refute original["data"] == conflicting["data"]
    assert conflicting["data"]["simulated_identity_collision"]
  end

  defp fault_page(field) do
    :ok = Store.clear()
    context = TestProviderFixtures.create_contact!()
    {:ok, run} = Provider.configure_run_faults(context.run["id"], %{field => 1})
    EventDelivery.page(run, 0, 100)
  end
end
