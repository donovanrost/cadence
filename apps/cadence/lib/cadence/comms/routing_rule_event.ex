defmodule Cadence.Comms.RoutingRuleEvent do
  @moduledoc """
  Append-only event for Routing Rule state changes.
  """

  alias Cadence.Ids

  @type event_type :: :created | :updated | :enabled | :disabled | :archived | :materialized

  @type t :: %__MODULE__{
          routing_rule_event_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          routing_rule_id: binary(),
          event_type: event_type(),
          actor_id: binary() | nil,
          occurred_at: DateTime.t(),
          payload: map()
        }

  defstruct [
    :routing_rule_event_id,
    :organization_id,
    :mission_id,
    :routing_rule_id,
    :event_type,
    :actor_id,
    :occurred_at,
    payload: %{}
  ]

  @event_types [:created, :updated, :enabled, :disabled, :archived, :materialized]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      routing_rule_event_id:
        Map.get(
          attrs,
          :routing_rule_event_id,
          Map.get(attrs, "routing_rule_event_id", Ids.new("routing_rule_event"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      routing_rule_id: Map.fetch!(attrs, :routing_rule_id),
      event_type:
        attrs
        |> Map.get(:event_type, Map.get(attrs, "event_type"))
        |> normalize_event_type(),
      actor_id: Map.get(attrs, :actor_id, Map.get(attrs, "actor_id")),
      occurred_at:
        Map.get(attrs, :occurred_at, Map.get(attrs, "occurred_at", DateTime.utc_now())),
      payload: Map.get(attrs, :payload, Map.get(attrs, "payload", %{}))
    }
  end

  defp normalize_event_type(value) when is_atom(value) and value in @event_types, do: value

  defp normalize_event_type(value) when is_binary(value) do
    Enum.find(@event_types, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported event_type: #{inspect(value)}"
  end

  defp normalize_event_type(value) do
    raise ArgumentError, "unsupported event_type: #{inspect(value)}"
  end
end
