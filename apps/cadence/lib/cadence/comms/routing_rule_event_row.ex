defmodule Cadence.Comms.RoutingRuleEventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Comms.RoutingRuleEvent
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key false

  schema "comms_routing_rule_events" do
    field(:routing_rule_event_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:routing_rule_id, :string)
    field(:event_type, :string)
    field(:actor_id, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:payload, :map, default: %{})
  end

  @required_fields [
    :routing_rule_event_id,
    :mission_id,
    :routing_rule_id,
    :event_type,
    :occurred_at,
    :payload
  ]

  @spec changeset(RoutingRuleEvent.t()) :: Ecto.Changeset.t()
  def changeset(%RoutingRuleEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:routing_rule_event_id], name: :comms_routing_rule_events_pkey)
  end

  @spec to_domain(struct()) :: RoutingRuleEvent.t()
  def to_domain(%__MODULE__{} = row) do
    RoutingRuleEvent.new(%{
      routing_rule_event_id: row.routing_rule_event_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      routing_rule_id: row.routing_rule_id,
      event_type: row.event_type,
      actor_id: row.actor_id,
      occurred_at: row.occurred_at,
      payload: JsonDocument.unwrap_value(row.payload)
    })
  end

  defp domain_attrs(%RoutingRuleEvent{} = event) do
    %{
      routing_rule_event_id: event.routing_rule_event_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      routing_rule_id: event.routing_rule_id,
      event_type: Atom.to_string(event.event_type),
      actor_id: event.actor_id,
      occurred_at: event.occurred_at,
      payload: JsonDocument.wrap_value(event.payload)
    }
  end

  defp all_fields do
    [
      :routing_rule_event_id,
      :organization_id,
      :mission_id,
      :routing_rule_id,
      :event_type,
      :actor_id,
      :occurred_at,
      :payload
    ]
  end
end
