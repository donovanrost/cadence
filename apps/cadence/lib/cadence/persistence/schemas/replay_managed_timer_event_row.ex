defmodule Cadence.Persistence.Schemas.ReplayManagedTimerEventRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Runtime.ManagedTimerEvent

  @primary_key {:timer_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "replay_managed_timer_events" do
    field(:replay_run_id, :string)
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:capability_instance_id, :string)
    field(:family_key, :string)
    field(:activation_id, :string)
    field(:binding_set_id, :string)
    field(:binding_set_version, :integer)
    field(:partition_affinity, :string)
    field(:partition_value, :string)
    field(:timer_key, :string)
    field(:event_kind, :string)
    field(:packet_id, :string)
    field(:evidence_id, :string)
    field(:due_at, :utc_datetime_usec)
    field(:occurred_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps(updated_at: false)
  end

  @required_fields [
    :timer_event_id,
    :replay_run_id,
    :mission_id,
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

  @spec changeset(binary(), ManagedTimerEvent.t()) :: Ecto.Changeset.t()
  def changeset(replay_run_id, %ManagedTimerEvent{} = timer_event)
      when is_binary(replay_run_id) do
    %__MODULE__{}
    |> cast(domain_attrs(replay_run_id, timer_event), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:replay_run_id)
    |> foreign_key_constraint(:evidence_id)
  end

  @spec to_domain(struct()) :: ManagedTimerEvent.t()
  def to_domain(%__MODULE__{} = row) do
    %ManagedTimerEvent{
      timer_event_id: row.timer_event_id,
      mission_id: row.mission_id,
      capability_instance_id: row.capability_instance_id,
      family_key: String.to_existing_atom(row.family_key),
      activation_id: row.activation_id,
      binding_set_id: row.binding_set_id,
      binding_set_version: row.binding_set_version,
      partition_affinity: String.to_existing_atom(row.partition_affinity),
      partition_value: row.partition_value,
      timer_key: row.timer_key,
      event_kind: String.to_existing_atom(row.event_kind),
      packet_id: row.packet_id,
      evidence_id: row.evidence_id,
      due_at: row.due_at,
      occurred_at: row.occurred_at,
      metadata: row.metadata
    }
  end

  defp domain_attrs(replay_run_id, %ManagedTimerEvent{} = timer_event) do
    %{
      timer_event_id: timer_event.timer_event_id,
      replay_run_id: replay_run_id,
      mission_id: timer_event.mission_id,
      capability_instance_id: timer_event.capability_instance_id,
      family_key: Atom.to_string(timer_event.family_key),
      activation_id: timer_event.activation_id,
      binding_set_id: timer_event.binding_set_id,
      binding_set_version: timer_event.binding_set_version,
      partition_affinity: Atom.to_string(timer_event.partition_affinity),
      partition_value: timer_event.partition_value,
      timer_key: timer_event.timer_key,
      event_kind: Atom.to_string(timer_event.event_kind),
      packet_id: timer_event.packet_id,
      evidence_id: timer_event.evidence_id,
      due_at: timer_event.due_at,
      occurred_at: timer_event.occurred_at,
      metadata: JsonDocument.encode(timer_event.metadata)
    }
  end

  defp all_fields do
    [
      :timer_event_id,
      :replay_run_id,
      :mission_id,
      :capability_instance_id,
      :family_key,
      :activation_id,
      :binding_set_id,
      :binding_set_version,
      :partition_affinity,
      :partition_value,
      :timer_key,
      :event_kind,
      :packet_id,
      :evidence_id,
      :due_at,
      :occurred_at,
      :metadata
    ]
  end
end
