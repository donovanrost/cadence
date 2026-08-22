defmodule Cadence.Contacts.DownlinkDiagnostic do
  @moduledoc """
  Canonical diagnostic emitted by the contact-level downlink combiner.
  """

  alias Cadence.Ids

  @type diagnostic_kind ::
          :accepted
          | :selected_path_preferred
          | :higher_quality_preferred
          | :existing_selection_retained

  @type t :: %__MODULE__{
          diagnostic_id: binary(),
          mission_id: binary(),
          realized_contact_id: binary(),
          observation_key: binary(),
          path_id: binary(),
          selected_path_id: binary(),
          observation_id: binary(),
          competing_observation_id: binary() | nil,
          diagnostic_kind: diagnostic_kind(),
          recorded_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :diagnostic_id,
    :mission_id,
    :realized_contact_id,
    :observation_key,
    :path_id,
    :selected_path_id,
    :observation_id,
    :competing_observation_id,
    :diagnostic_kind,
    :recorded_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      diagnostic_id:
        Map.get(
          attrs,
          :diagnostic_id,
          Map.get(attrs, "diagnostic_id", Ids.new("downlink_diagnostic"))
        ),
      mission_id: Map.fetch!(attrs, :mission_id),
      realized_contact_id: Map.fetch!(attrs, :realized_contact_id),
      observation_key: Map.fetch!(attrs, :observation_key),
      path_id: Map.fetch!(attrs, :path_id),
      selected_path_id: Map.fetch!(attrs, :selected_path_id),
      observation_id: Map.fetch!(attrs, :observation_id),
      competing_observation_id:
        Map.get(attrs, :competing_observation_id, Map.get(attrs, "competing_observation_id")),
      diagnostic_kind: Map.fetch!(attrs, :diagnostic_kind),
      recorded_at: Map.fetch!(attrs, :recorded_at),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end
end
