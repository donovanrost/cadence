defmodule Cadence.Contacts.ContactAction do
  @moduledoc """
  First-class audit/action record for operator-driven contact lifecycle changes.
  """

  alias Cadence.Contacts.KnownAtom
  alias Cadence.Ids

  @type action_kind :: :scheduled_contact_canceled | :realized_contact_ended_early

  @type t :: %__MODULE__{
          contact_action_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          scheduled_contact_id: binary() | nil,
          realized_contact_id: binary() | nil,
          action_kind: action_kind(),
          reason: binary() | nil,
          actor: map(),
          metadata: map(),
          occurred_at: DateTime.t()
        }

  defstruct [
    :contact_action_id,
    :organization_id,
    :mission_id,
    :scheduled_contact_id,
    :realized_contact_id,
    :action_kind,
    :reason,
    :occurred_at,
    actor: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      contact_action_id:
        Map.get(
          attrs,
          :contact_action_id,
          Map.get(attrs, "contact_action_id", Ids.new("contact_action"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      scheduled_contact_id:
        Map.get(attrs, :scheduled_contact_id, Map.get(attrs, "scheduled_contact_id")),
      realized_contact_id:
        Map.get(attrs, :realized_contact_id, Map.get(attrs, "realized_contact_id")),
      action_kind:
        Map.get(attrs, :action_kind, Map.get(attrs, "action_kind"))
        |> normalize_action_kind(),
      reason: Map.get(attrs, :reason, Map.get(attrs, "reason")),
      actor: Map.get(attrs, :actor, Map.get(attrs, "actor", %{})),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{})),
      occurred_at: Map.get(attrs, :occurred_at, Map.get(attrs, "occurred_at", DateTime.utc_now()))
    }
  end

  defp normalize_action_kind(action_kind), do: KnownAtom.contact_action_kind!(action_kind)
end
