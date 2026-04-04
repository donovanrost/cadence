defmodule Cadence.Persistence.Schemas.TransportCapabilityRecordRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Runtime.TransportCapabilityRecord

  @primary_key {:transport_record_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "transport_capability_records" do
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
    field(:event_kind, :string)
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
    :transport_record_id,
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
    :event_kind,
    :emitted_record_kinds,
    :emitted_record_count,
    :action_request_count,
    :state_snapshot,
    :metadata,
    :recorded_at
  ]

  @spec changeset(TransportCapabilityRecord.t()) :: Ecto.Changeset.t()
  def changeset(%TransportCapabilityRecord{} = capability_record) do
    %__MODULE__{}
    |> cast(domain_attrs(capability_record), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: TransportCapabilityRecord.t()
  def to_domain(%__MODULE__{} = row) do
    %TransportCapabilityRecord{
      transport_record_id: row.transport_record_id,
      mission_id: row.mission_id,
      realized_contact_id: row.realized_contact_id,
      path_id: row.path_id,
      capability_instance_id: row.capability_instance_id,
      family_key: String.to_existing_atom(row.family_key),
      activation_id: row.activation_id,
      binding_set_id: row.binding_set_id,
      binding_set_version: row.binding_set_version,
      partition_affinity: String.to_existing_atom(row.partition_affinity),
      partition_value: row.partition_value,
      event_kind: String.to_existing_atom(row.event_kind),
      timer_key: row.timer_key,
      emitted_record_kinds: JsonDocument.unwrap_items(row.emitted_record_kinds),
      emitted_record_count: row.emitted_record_count,
      action_request_count: row.action_request_count,
      state_snapshot: JsonDocument.unwrap_value(row.state_snapshot),
      recorded_at: row.recorded_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    }
  end

  defp domain_attrs(%TransportCapabilityRecord{} = capability_record) do
    %{
      transport_record_id: capability_record.transport_record_id,
      mission_id: capability_record.mission_id,
      realized_contact_id: capability_record.realized_contact_id,
      path_id: capability_record.path_id,
      capability_instance_id: capability_record.capability_instance_id,
      family_key: Atom.to_string(capability_record.family_key),
      activation_id: capability_record.activation_id,
      binding_set_id: capability_record.binding_set_id,
      binding_set_version: capability_record.binding_set_version,
      partition_affinity: Atom.to_string(capability_record.partition_affinity),
      partition_value: capability_record.partition_value,
      event_kind: Atom.to_string(capability_record.event_kind),
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
      :transport_record_id,
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
      :event_kind,
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
