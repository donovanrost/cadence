defmodule Cadence.Projections.ContactStatus do
  @moduledoc """
  Read-side Contact Plan status without collapsing plane-owned truth.

  `requested` is Management intent, `operational` is Control execution,
  `applied` is the resulting scheduled Contact, and `observed` is live runtime
  evidence when a Contact has been realized.
  """

  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Runtime.Contacts, as: RuntimeContacts

  @spec project(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def project(organization_id, mission_id, plan_id) do
    with {:ok, plan, version} <-
           ManagementContacts.fetch_plan(organization_id, mission_id, plan_id) do
      execution_version = plan.approved_version || version.version

      items =
        ControlContacts.list_plan_execution(
          organization_id,
          mission_id,
          plan.contact_plan_id,
          execution_version
        )

      reservations = reservations(organization_id, mission_id, items)
      scheduled_contacts = scheduled_contacts(organization_id, mission_id, reservations)

      {:ok,
       %{
         requested: %{
           plan: plan,
           version: version,
           selected_opportunities:
             ManagementContacts.selected_opportunities(
               organization_id,
               mission_id,
               plan.contact_plan_id,
               version.version
             ),
           approvals:
             ManagementContacts.list_approvals(organization_id, mission_id, plan.contact_plan_id)
         },
         operational: %{execution_items: items, provider_reservations: reservations},
         applied: %{scheduled_contacts: scheduled_contacts},
         observed: %{realized_contacts: observations(mission_id, scheduled_contacts)}
       }}
    end
  end

  defp reservations(organization_id, mission_id, items) do
    items
    |> Enum.filter(&is_binary(&1.provider_reservation_id))
    |> Enum.flat_map(fn item ->
      case ControlContacts.fetch_provider_reservation(
             organization_id,
             mission_id,
             item.provider_reservation_id
           ) do
        {:ok, reservation} -> [reservation]
        {:error, _reason} -> []
      end
    end)
  end

  defp scheduled_contacts(organization_id, mission_id, reservations) do
    Enum.flat_map(reservations, fn reservation ->
      case ControlContacts.fetch_scheduled_contact(
             organization_id,
             mission_id,
             reservation.scheduled_contact_id
           ) do
        {:ok, contact} -> [contact]
        {:error, _reason} -> []
      end
    end)
  end

  defp observations(mission_id, scheduled_contacts) do
    scheduled_contacts
    |> Enum.filter(&is_binary(&1.realized_contact_id))
    |> Enum.map(fn contact ->
      %{
        realized_contact_id: contact.realized_contact_id,
        observation: RuntimeContacts.snapshot(mission_id, contact.realized_contact_id)
      }
    end)
  end
end
