defmodule Cadence.Contacts.ScheduledContactRevision do
  @moduledoc "Immutable execution snapshot for one Scheduled Contact revision."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @type t :: %__MODULE__{}

  defstruct [
    :scheduled_contact_revision_id,
    :organization_id,
    :mission_id,
    :scheduled_contact_id,
    :revision,
    :provider_reservation_change_id,
    :created_by,
    :created_at,
    snapshot_document: %{},
    reason_document: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      scheduled_contact_revision_id:
        value(attrs, :scheduled_contact_revision_id, Ids.new("scheduled_contact_revision")),
      organization_id: required(attrs, :organization_id),
      mission_id: required(attrs, :mission_id),
      scheduled_contact_id: required(attrs, :scheduled_contact_id),
      revision: positive(attrs, :revision),
      provider_reservation_change_id: value(attrs, :provider_reservation_change_id),
      snapshot_document: attrs |> value(:snapshot_document, %{}) |> JsonDocument.encode(),
      reason_document: attrs |> value(:reason_document, %{}) |> JsonDocument.encode(),
      created_by: required(attrs, :created_by),
      created_at: value(attrs, :created_at, DateTime.utc_now())
    }
  end

  defp required(attrs, key) do
    case value(attrs, key) do
      text when is_binary(text) and text != "" -> text
      _other -> raise ArgumentError, "#{key} is required"
    end
  end

  defp positive(attrs, key) do
    case value(attrs, key) do
      number when is_integer(number) and number > 0 -> number
      _other -> raise ArgumentError, "#{key} must be positive"
    end
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
