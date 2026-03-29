defmodule Cadence.Persistence.Schemas.TransportTimerEventRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Runtime.TransportTimerEvent

  @primary_key {:timer_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "transport_timer_events" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:realized_contact_id, :string)
    field(:path_id, :string)
    field(:capability_instance_id, :string)
    field(:family_key, :string)
    field(:activation_id, :string)
    field(:binding_set_id, :string)
    field(:binding_set_version, :integer)
    field(:partition_affinity, :string)
    field(:partition_value, :string)
    field(:timer_key, :string)
    field(:event_kind, :string)
    field(:due_at, :utc_datetime_usec)
    field(:occurred_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps(updated_at: false)
  end

  @required_fields [
    :timer_event_id,
    :mission_id,
    :realized_contact_id,
    :path_id,
    :capability_instance_id,
    :family_key,
    :activation_id,
    :binding_set_id,
    :binding_set_version,
    :partition_affinity,
    :partition_value,
    :timer_key,
    :event_kind,
    :occurred_at,
    :metadata
  ]

  @spec changeset(TransportTimerEvent.t()) :: Ecto.Changeset.t()
  def changeset(%TransportTimerEvent{} = timer_event) do
    %__MODULE__{}
    |> cast(domain_attrs(timer_event), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  defp domain_attrs(%TransportTimerEvent{} = timer_event) do
    %{
      timer_event_id: timer_event.timer_event_id,
      mission_id: timer_event.mission_id,
      realized_contact_id: timer_event.realized_contact_id,
      path_id: timer_event.path_id,
      capability_instance_id: timer_event.capability_instance_id,
      family_key: Atom.to_string(timer_event.family_key),
      activation_id: timer_event.activation_id,
      binding_set_id: timer_event.binding_set_id,
      binding_set_version: timer_event.binding_set_version,
      partition_affinity: Atom.to_string(timer_event.partition_affinity),
      partition_value: timer_event.partition_value,
      timer_key: timer_event.timer_key,
      event_kind: Atom.to_string(timer_event.event_kind),
      due_at: timer_event.due_at,
      occurred_at: timer_event.occurred_at,
      metadata: JsonDocument.encode(timer_event.metadata)
    }
  end

  defp all_fields do
    [
      :timer_event_id,
      :mission_id,
      :realized_contact_id,
      :path_id,
      :capability_instance_id,
      :family_key,
      :activation_id,
      :binding_set_id,
      :binding_set_version,
      :partition_affinity,
      :partition_value,
      :timer_key,
      :event_kind,
      :due_at,
      :occurred_at,
      :metadata
    ]
  end
end
