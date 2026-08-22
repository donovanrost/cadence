defmodule CadenceSimulator.Provider.ContactsTest do
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider.{ContactChanges, Contacts, Store}
  alias CadenceSimulator.TestProviderFixtures

  setup do
    :ok = Store.clear()
    :ok
  end

  test "provider timing and equivalent antenna changes are bounded and revisioned" do
    context = TestProviderFixtures.create_contact!(%{}, run_state: "paused")
    contact = context.contact

    assert {:ok, shifted} =
             ContactChanges.apply(context.run, contact["id"], %{
               "type" => "timing_shift",
               "start_shift_seconds" => -120,
               "end_shift_seconds" => 180,
               "reason" => "network_optimization"
             })

    assert shifted["revision"] == 2
    assert seconds_between(contact["starts_at"], shifted["starts_at"]) == -120
    assert seconds_between(contact["ends_at"], shifted["ends_at"]) == 180

    equivalent_resource = alternate_antenna(contact)

    assert {:ok, substituted} =
             ContactChanges.apply(context.run, contact["id"], %{
               "type" => "antenna_substitution",
               "antenna_or_service_pool_ref" => equivalent_resource
             })

    assert substituted["revision"] == 3

    assert get_in(substituted, ["extensions", "provider_change", "equivalent_resource"]) ==
             true

    assert {:error, {:invalid, _detail}} =
             ContactChanges.apply(context.run, contact["id"], %{
               "type" => "timing_shift",
               "start_shift_seconds" => 86_401
             })

    assert {:ok, internal} = Contacts.fetch_internal(contact["id"])
    assert length(internal["modification_history"]) == 2
  end

  test "station substitution is outside the equivalent pool and respects committed capacity" do
    context = TestProviderFixtures.create_contact!(%{}, run_state: "paused")
    contact = context.contact

    assert {:ok, substituted} =
             ContactChanges.apply(context.run, contact["id"], %{
               "type" => "station_substitution",
               "ground_station_ref" => "station-troll",
               "antenna_or_service_pool_ref" => "station-troll-antenna-2"
             })

    assert substituted["ground_station_ref"] == "station-troll"
    assert substituted["antenna_or_service_pool_ref"] == "station-troll-antenna-2"

    assert get_in(substituted, ["extensions", "provider_change", "equivalent_resource"]) ==
             false

    {:ok, internal_contact} = Contacts.fetch_internal(contact["id"])

    occupied =
      internal_contact
      |> Map.put("id", "occupied-contact")
      |> Map.put("antenna_or_service_pool_ref", "station-svalbard-antenna-3")
      |> Map.put("client_reference", "occupied-contact")

    {:ok, _occupied} = Store.put(:contact, occupied)

    assert {:error, {:no_capacity, _detail}} =
             ContactChanges.apply(context.run, contact["id"], %{
               "type" => "station_substitution",
               "ground_station_ref" => "station-svalbard",
               "antenna_or_service_pool_ref" => "station-svalbard-antenna-3"
             })
  end

  test "duration and estimated capacity reductions preserve authoritative evidence" do
    context = TestProviderFixtures.create_contact!(%{}, run_state: "paused")
    contact = context.contact
    reduced_end = shift_time(contact["ends_at"], -60)
    current_capacity = get_in(contact, ["extensions", "estimated_capacity", "value"])

    assert {:ok, reduced} =
             ContactChanges.apply(context.run, contact["id"], %{
               "type" => "capacity_reduction",
               "ends_at" => reduced_end,
               "estimated_capacity_bytes" => current_capacity - 1_000,
               "reason" => "provider_capacity_loss"
             })

    assert reduced["ends_at"] == reduced_end

    assert get_in(reduced, ["extensions", "estimated_capacity", "value"]) ==
             current_capacity - 1_000

    assert get_in(reduced, ["extensions", "provider_change", "effective"]) == true

    assert {:error, {:invalid, _detail}} =
             ContactChanges.apply(context.run, contact["id"], %{
               "type" => "capacity_reduction",
               "ends_at" => shift_time(reduced_end, 120)
             })
  end

  test "counteroffers remain distinguishable from provider-initiated cancellation facts" do
    counteroffer_context = TestProviderFixtures.create_contact!(%{}, run_state: "paused")
    contact = counteroffer_context.contact

    assert {:ok, counteroffer} =
             ContactChanges.apply(counteroffer_context.run, contact["id"], %{
               "type" => "counteroffer",
               "starts_at" => shift_time(contact["starts_at"], 120),
               "ends_at" => shift_time(contact["ends_at"], 120),
               "expires_at" => shift_time(contact["starts_at"], -60),
               "reason" => "resource_substitution"
             })

    assert counteroffer["status_reason"] == "provider_counteroffer"
    assert get_in(counteroffer, ["extensions", "provider_change", "effective"]) == false

    assert get_in(counteroffer, ["extensions", "counteroffer", "reason"]) ==
             "resource_substitution"

    cancellation_context = TestProviderFixtures.create_contact!(%{}, run_state: "paused")

    assert {:ok, canceled} =
             ContactChanges.apply(
               cancellation_context.run,
               cancellation_context.contact["id"],
               %{"type" => "cancellation", "reason" => "provider_station_outage"}
             )

    assert canceled["status"] == "canceled"
    assert canceled["pass_phase"] == "closed"
    assert canceled["status_reason"] == "provider_station_outage"
    assert get_in(canceled, ["extensions", "provider_change", "effective"]) == true
  end

  defp seconds_between(left, right) do
    {:ok, left_at, _offset} = DateTime.from_iso8601(left)
    {:ok, right_at, _offset} = DateTime.from_iso8601(right)
    DateTime.diff(right_at, left_at)
  end

  defp shift_time(value, seconds) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime |> DateTime.add(seconds) |> DateTime.to_iso8601()
  end

  defp alternate_antenna(contact) do
    current = contact["antenna_or_service_pool_ref"]
    suffix = if String.ends_with?(current, "-1"), do: "2", else: "1"
    "#{contact["ground_station_ref"]}-antenna-#{suffix}"
  end
end
