defmodule Cadence.Reads.OrganizationAudit.ContactEvents do
  @moduledoc """
  A mission's contact cancels and early ends for the organization audit (`kind: "contacts"`,
  U55): "Canceled the 13:04Z contact" / "Ended the 13:04Z contact early", the operator's reason
  as `reason`; Cadence's cancels of a contact whose reservation won't fly read "Canceled the
  13:04Z contact (provider_failed)" with no person. Target `{kind: "contact", id, label}`.
  The latest 200.
  """

  alias Cadence.Contacts

  @spec list(binary(), binary()) :: [map()]
  def list(organization_id, mission_id) do
    organization_id
    |> Contacts.list_contact_actions(mission_id, [])
    |> Enum.take(-200)
    |> Enum.map(&event/1)
  end

  defp event(action) do
    user_id = user_id(action.actor || %{})
    contact = action.scheduled_contact_id || action.realized_contact_id

    %{
      id: "contacts:contact_action:#{action.contact_action_id}",
      at: action.occurred_at,
      actor: user_id && %{kind: "user", id: user_id, name: nil},
      kind: "contacts",
      action: words(action.action_kind, cause(action.metadata || %{})),
      target: %{kind: "contact", id: contact, label: "Contact"},
      mission: nil,
      reason: if(user_id, do: action.reason)
    }
  end

  # The acting person, or nil for Cadence's own cancels.
  defp user_id(%{"kind" => "user"} = actor), do: actor["id"] || actor["user_id"]
  defp user_id(%{kind: "user"} = actor), do: actor[:id]
  defp user_id(_actor), do: nil

  defp cause(metadata), do: metadata["cause"] || metadata[:cause]

  defp words(:realized_contact_ended_early, _cause), do: "Ended the contact early"
  defp words(_canceled, "provider_" <> _ = cause), do: "Canceled the contact (#{cause})"
  defp words(_canceled, _cause), do: "Canceled the contact"
end
