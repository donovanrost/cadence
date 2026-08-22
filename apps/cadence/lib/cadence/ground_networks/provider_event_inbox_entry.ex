defmodule Cadence.GroundNetworks.ProviderEventInboxEntry do
  @moduledoc "Immutable provider event delivery plus mutable processing state."

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @states [:received, :processing, :processed, :quarantined, :reprocessing]

  @type t :: %__MODULE__{}

  # The aggregate mirrors immutable provider evidence and operational processing state.
  # credo:disable-for-next-line Credo.Check.Warning.StructFieldAmount
  defstruct [
    :provider_event_inbox_id,
    :organization_id,
    :provider_account_id,
    :provider_account_version,
    :provider_event_cursor_id,
    :environment_ref,
    :channel_ref,
    :provider_event_id,
    :schema_version,
    :event_type,
    :sequence,
    :resource_type,
    :resource_id,
    :resource_revision,
    :request_id,
    :correlation_id,
    :client_reference,
    :provider_occurred_at,
    :received_at,
    :content_sha256,
    :provider_evidence_id,
    :processing_state,
    :last_attempted_at,
    :processed_at,
    :mission_id,
    :provider_id,
    :provider_reservation_id,
    :scheduled_contact_id,
    :contact_id,
    payload_document: %{},
    attempt_count: 0,
    error_document: %{},
    identity_collision: false
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    fields =
      __MODULE__.__struct__()
      |> Map.keys()
      |> Enum.reject(&(&1 == :__struct__))

    values =
      Enum.reduce(fields, %{}, fn field, acc ->
        Map.put(acc, field, value(attrs, field, Map.fetch!(__struct__(), field)))
      end)

    values =
      values
      |> Map.put(
        :provider_event_inbox_id,
        value(attrs, :provider_event_inbox_id, Ids.new("provider_event_inbox"))
      )
      |> Map.update!(:processing_state, &state!/1)
      |> Map.update!(:payload_document, &JsonDocument.encode/1)
      |> Map.update!(:error_document, &JsonDocument.encode/1)

    struct!(__MODULE__, values)
  end

  defp state!(state) when state in @states, do: state

  defp state!(state) when is_binary(state) do
    Enum.find(@states, &(Atom.to_string(&1) == state)) ||
      raise ArgumentError, "unsupported processing_state"
  end

  defp state!(_state), do: raise(ArgumentError, "unsupported processing_state")

  defp value(attrs, key, default),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
