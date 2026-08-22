defmodule Cadence.Contacts.CombinedDownlinkRecord do
  @moduledoc """
  Canonical merged operational downlink record chosen by the contact combiner.
  """

  alias Cadence.Ids

  @type selected_reason :: :accepted | :selected_path_preferred | :higher_quality_preferred

  @type t :: %__MODULE__{
          merged_record_id: binary(),
          mission_id: binary(),
          realized_contact_id: binary(),
          observation_key: binary(),
          source_endpoint_ref: binary() | nil,
          selected_path_id: binary(),
          selected_observation_id: binary(),
          payload: term(),
          selected_reason: selected_reason(),
          observed_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :merged_record_id,
    :mission_id,
    :realized_contact_id,
    :observation_key,
    :source_endpoint_ref,
    :selected_path_id,
    :selected_observation_id,
    :payload,
    :selected_reason,
    :observed_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      merged_record_id:
        Map.get(
          attrs,
          :merged_record_id,
          Map.get(attrs, "merged_record_id", Ids.new("merged_downlink"))
        ),
      mission_id: Map.fetch!(attrs, :mission_id),
      realized_contact_id: Map.fetch!(attrs, :realized_contact_id),
      observation_key: Map.fetch!(attrs, :observation_key),
      source_endpoint_ref:
        Map.get(attrs, :source_endpoint_ref, Map.get(attrs, "source_endpoint_ref")),
      selected_path_id: Map.fetch!(attrs, :selected_path_id),
      selected_observation_id: Map.fetch!(attrs, :selected_observation_id),
      payload: Map.get(attrs, :payload, Map.get(attrs, "payload")),
      selected_reason: Map.fetch!(attrs, :selected_reason),
      observed_at: Map.fetch!(attrs, :observed_at),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end
end
