defmodule Cadence.Limits.DefinitionInterval do
  @moduledoc """
  Effective interval for a governed limit definition.
  """

  alias Cadence.Limits.{Definition, DefinitionLifecycleEvent}

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
          observed_at: DateTime.t(),
          thresholds: map(),
          metadata: map(),
          complete?: boolean()
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
    :observed_at,
    thresholds: %{},
    metadata: %{},
    complete?: true
  ]

  @spec from_event(DefinitionLifecycleEvent.t(), DateTime.t() | nil, Definition.t() | nil) :: t()
  def from_event(%DefinitionLifecycleEvent{} = event, active_to, definition) do
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
      active_to: event.active_to || active_to,
      observed_at: event.observed_at,
      thresholds: thresholds(definition),
      metadata: metadata(event, definition),
      complete?: not is_nil(definition)
    }
  end

  defp thresholds(%Definition{} = definition), do: definition.thresholds || %{}
  defp thresholds(nil), do: %{}

  defp metadata(%DefinitionLifecycleEvent{} = event, %Definition{} = definition) do
    (definition.metadata || %{})
    |> Map.merge(event.payload || %{})
    |> Map.put("limit_definition_lifecycle_event_id", event.limit_definition_lifecycle_event_id)
    |> Map.put("definition_activation_key", event.definition_activation_key)
  end

  defp metadata(%DefinitionLifecycleEvent{} = event, nil) do
    event.payload
    |> Map.merge(%{
      "limit_definition_lifecycle_event_id" => event.limit_definition_lifecycle_event_id,
      "definition_activation_key" => event.definition_activation_key,
      "missing_limit_definition" => true
    })
  end
end
