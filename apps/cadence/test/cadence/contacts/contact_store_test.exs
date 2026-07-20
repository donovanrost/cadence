defmodule Cadence.Contacts.ContactStoreTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.ContactAction
  alias Cadence.Contacts.ContactStore
  alias Cadence.Contacts.Path
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Contacts.ScheduledContact

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-contact-store-#{suffix}"
    mission_id = "mission-contact-store-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "owns contact records, lifecycle updates, action filters, and scheduler reads", context do
    starts_at = DateTime.from_unix!(1_700_500_000)
    ends_at = DateTime.add(starts_at, 600, :second)

    path =
      Path.new(%{
        path_id: "downlink-1",
        direction: :downlink,
        selection_role: :selected
      })

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "scheduled-1",
        organization_id: context.organization_id,
        mission_id: context.mission_id,
        provider_contact_ref: "provider-contact-1",
        paths: [path],
        starts_at: starts_at,
        ends_at: ends_at
      })

    assert {:ok, %ScheduledContact{} = persisted_scheduled} =
             ContactStore.persist_scheduled(scheduled_contact)

    assert {:ok, %ScheduledContact{}} =
             ContactStore.fetch_scheduled_by_provider_ref(
               context.mission_id,
               "provider-contact-1"
             )

    assert [%ScheduledContact{scheduled_contact_id: "scheduled-1"}] =
             ContactStore.due_scheduled(DateTime.add(starts_at, 60, :second), context.mission_id)

    assert [%{mission_id: mission_id, wake_at: wake_at}] =
             ContactStore.scheduler_wakeups(starts_at, context.mission_id)

    assert mission_id == context.mission_id
    assert DateTime.compare(wake_at, starts_at) == :eq

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "realized-1",
        organization_id: context.organization_id,
        mission_id: context.mission_id,
        scheduled_contact_id: persisted_scheduled.scheduled_contact_id,
        paths: [path],
        realized_at: starts_at
      })

    assert {:ok, %RealizedContact{}} = ContactStore.persist_realized(realized_contact)

    action =
      ContactAction.new(%{
        contact_action_id: "action-1",
        organization_id: context.organization_id,
        mission_id: context.mission_id,
        scheduled_contact_id: persisted_scheduled.scheduled_contact_id,
        action_kind: :scheduled_contact_canceled,
        occurred_at: starts_at
      })

    assert {:ok, %ContactAction{}} = ContactStore.persist_action(action)

    assert [%ContactAction{contact_action_id: "action-1"}] =
             ContactStore.list_actions(
               context.organization_id,
               context.mission_id,
               scheduled_contact_id: persisted_scheduled.scheduled_contact_id
             )

    assert {:ok, %ScheduledContact{lifecycle_state: :canceled}} =
             ContactStore.update_scheduled_lifecycle(
               persisted_scheduled,
               :canceled,
               %{"reason" => "operator"}
             )

    assert {:ok, %RealizedContact{lifecycle_state: :completed}} =
             ContactStore.update_realized_lifecycle(
               realized_contact,
               :completed,
               %{"reason" => "window ended"}
             )
  end
end
