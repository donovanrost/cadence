defmodule Cadence.Dashboards.SourceHealthStatus do
  @moduledoc """
  Latest dashboard source-health projection for one concrete source identity.
  """

  alias Cadence.Dashboards.SourceHealthEvent

  @type t :: %__MODULE__{
          source_health_key: binary(),
          source_health_event_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          logical_source: atom() | binary(),
          data_source_id: binary(),
          source_binding_id: binary() | nil,
          realm: atom() | binary() | nil,
          replay_run_id: binary() | nil,
          dataset: binary() | nil,
          event_type: SourceHealthEvent.event_type(),
          source_health: SourceHealthEvent.source_health(),
          previous_source_health: SourceHealthEvent.source_health() | nil,
          reason: atom() | binary() | nil,
          observed_at: DateTime.t(),
          last_seen_at: DateTime.t(),
          transition_count: non_neg_integer(),
          payload: map()
        }

  defstruct [
    :source_health_key,
    :source_health_event_id,
    :organization_id,
    :mission_id,
    :logical_source,
    :data_source_id,
    :source_binding_id,
    :realm,
    :replay_run_id,
    :dataset,
    :event_type,
    :source_health,
    :previous_source_health,
    :reason,
    :observed_at,
    :last_seen_at,
    transition_count: 0,
    payload: %{}
  ]

  @spec from_event(SourceHealthEvent.t(), non_neg_integer()) :: t()
  def from_event(%SourceHealthEvent{} = event, transition_count \\ 1) do
    %__MODULE__{
      source_health_key: event.source_health_key,
      source_health_event_id: event.source_health_event_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      logical_source: event.logical_source,
      data_source_id: event.data_source_id,
      source_binding_id: event.source_binding_id,
      realm: event.realm,
      replay_run_id: event.replay_run_id,
      dataset: event.dataset,
      event_type: event.event_type,
      source_health: event.source_health,
      previous_source_health: event.previous_source_health,
      reason: event.reason,
      observed_at: event.observed_at,
      last_seen_at: event.observed_at,
      transition_count: transition_count,
      payload: event.payload
    }
  end
end
