defmodule Cadence.Runtime.TransportRecords.TransportActionRequestRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Runtime.TransportActionRequest

  @primary_key {:action_request_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "transport_action_requests" do
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
    field(:command_release_attempt_id, :string)
    field(:command_request_id, :string)
    field(:source_endpoint_ref, :string)
    field(:command_name, :string)
    field(:signal_phase, :string)
    field(:action_kind, :string)
    field(:request_document, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:requested_at, :utc_datetime_usec)

    timestamps(updated_at: false)
  end

  @required_fields [
    :action_request_id,
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
    :action_kind,
    :request_document,
    :metadata,
    :requested_at
  ]

  @spec changeset(TransportActionRequest.t()) :: Ecto.Changeset.t()
  def changeset(%TransportActionRequest{} = action_request) do
    %__MODULE__{}
    |> cast(domain_attrs(action_request), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: TransportActionRequest.t()
  def to_domain(%__MODULE__{} = row) do
    %TransportActionRequest{
      action_request_id: row.action_request_id,
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
      command_release_attempt_id: row.command_release_attempt_id,
      command_request_id: row.command_request_id,
      source_endpoint_ref: row.source_endpoint_ref,
      command_name: row.command_name,
      signal_phase:
        case row.signal_phase do
          nil -> nil
          signal_phase -> String.to_existing_atom(signal_phase)
        end,
      action_kind: String.to_existing_atom(row.action_kind),
      request_document: JsonDocument.unwrap_value(row.request_document),
      requested_at: row.requested_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    }
  end

  defp domain_attrs(%TransportActionRequest{} = action_request) do
    %{
      action_request_id: action_request.action_request_id,
      mission_id: action_request.mission_id,
      realized_contact_id: action_request.realized_contact_id,
      path_id: action_request.path_id,
      capability_instance_id: action_request.capability_instance_id,
      family_key: Atom.to_string(action_request.family_key),
      activation_id: action_request.activation_id,
      binding_set_id: action_request.binding_set_id,
      binding_set_version: action_request.binding_set_version,
      partition_affinity: Atom.to_string(action_request.partition_affinity),
      partition_value: action_request.partition_value,
      command_release_attempt_id: action_request.command_release_attempt_id,
      command_request_id: action_request.command_request_id,
      source_endpoint_ref: action_request.source_endpoint_ref,
      command_name: action_request.command_name,
      signal_phase:
        case action_request.signal_phase do
          nil -> nil
          signal_phase -> Atom.to_string(signal_phase)
        end,
      action_kind: Atom.to_string(action_request.action_kind),
      request_document: JsonDocument.encode(action_request.request_document),
      metadata: JsonDocument.encode(action_request.metadata),
      requested_at: action_request.requested_at
    }
  end

  defp all_fields do
    [
      :action_request_id,
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
      :command_release_attempt_id,
      :command_request_id,
      :source_endpoint_ref,
      :command_name,
      :signal_phase,
      :action_kind,
      :request_document,
      :metadata,
      :requested_at
    ]
  end
end
