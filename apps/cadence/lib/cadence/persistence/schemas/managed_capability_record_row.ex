defmodule Cadence.Persistence.Schemas.ManagedCapabilityRecordRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Runtime.ManagedCapabilityRecord

  @primary_key {:capability_record_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "managed_capability_records" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:capability_instance_id, :string)
    field(:family_key, :string)
    field(:activation_id, :string)
    field(:binding_set_id, :string)
    field(:binding_set_version, :integer)
    field(:partition_affinity, :string)
    field(:partition_value, :string)
    field(:event_kind, :string)
    field(:packet_id, :string)
    field(:evidence_id, :string)
    field(:timer_key, :string)
    field(:emitted_record_kinds, :map, default: %{})
    field(:emitted_record_count, :integer)
    field(:action_request_count, :integer)
    field(:state_snapshot, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:recorded_at, :utc_datetime_usec)

    timestamps(updated_at: false)
  end

  @required_fields [
    :capability_record_id,
    :mission_id,
    :capability_instance_id,
    :family_key,
    :activation_id,
    :binding_set_id,
    :binding_set_version,
    :partition_affinity,
    :partition_value,
    :event_kind,
    :emitted_record_kinds,
    :emitted_record_count,
    :action_request_count,
    :state_snapshot,
    :metadata,
    :recorded_at
  ]

  @spec changeset(ManagedCapabilityRecord.t()) :: Ecto.Changeset.t()
  def changeset(%ManagedCapabilityRecord{} = capability_record) do
    %__MODULE__{}
    |> cast(domain_attrs(capability_record), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  defp domain_attrs(%ManagedCapabilityRecord{} = capability_record) do
    %{
      capability_record_id: capability_record.capability_record_id,
      mission_id: capability_record.mission_id,
      capability_instance_id: capability_record.capability_instance_id,
      family_key: Atom.to_string(capability_record.family_key),
      activation_id: capability_record.activation_id,
      binding_set_id: capability_record.binding_set_id,
      binding_set_version: capability_record.binding_set_version,
      partition_affinity: Atom.to_string(capability_record.partition_affinity),
      partition_value: capability_record.partition_value,
      event_kind: Atom.to_string(capability_record.event_kind),
      packet_id: capability_record.packet_id,
      evidence_id: capability_record.evidence_id,
      timer_key: capability_record.timer_key,
      emitted_record_kinds: JsonDocument.wrap_items(capability_record.emitted_record_kinds),
      emitted_record_count: capability_record.emitted_record_count,
      action_request_count: capability_record.action_request_count,
      state_snapshot: JsonDocument.wrap_value(capability_record.state_snapshot),
      metadata: JsonDocument.encode(capability_record.metadata),
      recorded_at: capability_record.recorded_at
    }
  end

  defp all_fields do
    [
      :capability_record_id,
      :mission_id,
      :capability_instance_id,
      :family_key,
      :activation_id,
      :binding_set_id,
      :binding_set_version,
      :partition_affinity,
      :partition_value,
      :event_kind,
      :packet_id,
      :evidence_id,
      :timer_key,
      :emitted_record_kinds,
      :emitted_record_count,
      :action_request_count,
      :state_snapshot,
      :metadata,
      :recorded_at
    ]
  end
end
