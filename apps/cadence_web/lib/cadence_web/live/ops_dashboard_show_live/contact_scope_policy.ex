defmodule CadenceWeb.OpsDashboardShowLive.ContactScopePolicy do
  @moduledoc false

  def valid_contact?(current_scope, mission, contact_id, opts \\ [])

  def valid_contact?(current_scope, mission, contact_id, opts)
      when is_binary(contact_id) do
    organization_id = current_scope.organization_id
    mission_id = mission.mission_id

    case fetch_scheduled_contact_fn(opts).(organization_id, mission_id, contact_id) do
      {:ok, _contact} ->
        true

      {:error, :scheduled_contact_not_found} ->
        realized_contact?(organization_id, mission_id, contact_id, opts)

      {:error, _reason} ->
        false
    end
  end

  def valid_contact?(_current_scope, _mission, _contact_id, _opts), do: false

  defp realized_contact?(organization_id, mission_id, contact_id, opts) do
    case fetch_realized_contact_fn(opts).(organization_id, mission_id, contact_id) do
      {:ok, _contact} -> true
      {:error, :realized_contact_not_found} -> false
      {:error, _reason} -> false
    end
  end

  defp fetch_scheduled_contact_fn(opts) do
    Keyword.get(opts, :fetch_scheduled_contact, &Cadence.Contacts.fetch_scheduled_contact/3)
  end

  defp fetch_realized_contact_fn(opts) do
    Keyword.get(opts, :fetch_realized_contact, &Cadence.Contacts.fetch_realized_contact/3)
  end
end
