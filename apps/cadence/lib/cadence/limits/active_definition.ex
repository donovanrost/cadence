defmodule Cadence.Limits.ActiveDefinition do
  @moduledoc """
  Latest effective limit definition projection for a point/scope/realm.
  """

  alias Cadence.Limits.DefinitionLifecycleEvent

  @type t :: %__MODULE__{
          definition_activation_key: binary(),
          limit_definition_lifecycle_event_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          point_id: binary(),
          limit_set_name: binary(),
          scope_type: atom() | binary() | nil,
          scope_ref: binary() | nil,
          realm: atom() | binary() | nil,
          event_type: DefinitionLifecycleEvent.event_type(),
          limit_definition_id: binary(),
          limit_definition_version: pos_integer(),
          previous_limit_definition_id: binary() | nil,
          previous_limit_definition_version: pos_integer() | nil,
          active_from: DateTime.t(),
          active_to: DateTime.t() | nil,
          reason: atom() | binary() | nil,
          last_seen_at: DateTime.t(),
          transition_count: non_neg_integer(),
          payload: map()
        }

  defstruct [
    :definition_activation_key,
    :limit_definition_lifecycle_event_id,
    :organization_id,
    :mission_id,
    :point_id,
    :limit_set_name,
    :scope_type,
    :scope_ref,
    :realm,
    :event_type,
    :limit_definition_id,
    :limit_definition_version,
    :previous_limit_definition_id,
    :previous_limit_definition_version,
    :active_from,
    :active_to,
    :reason,
    :last_seen_at,
    transition_count: 1,
    payload: %{}
  ]

  @spec from_event(DefinitionLifecycleEvent.t(), pos_integer()) :: t()
  def from_event(%DefinitionLifecycleEvent{} = event, transition_count) do
    %__MODULE__{
      definition_activation_key: event.definition_activation_key,
      limit_definition_lifecycle_event_id: event.limit_definition_lifecycle_event_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      point_id: event.point_id,
      limit_set_name: event.limit_set_name,
      scope_type: event.scope_type,
      scope_ref: event.scope_ref,
      realm: event.realm,
      event_type: event.event_type,
      limit_definition_id: event.limit_definition_id,
      limit_definition_version: event.limit_definition_version,
      previous_limit_definition_id: event.previous_limit_definition_id,
      previous_limit_definition_version: event.previous_limit_definition_version,
      active_from: event.active_from,
      active_to: event.active_to,
      reason: event.reason,
      last_seen_at: event.observed_at,
      transition_count: transition_count,
      payload: event.payload
    }
  end
end
