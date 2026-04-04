defmodule Cadence.Persistence.Schemas.ReplayManagedActionRequestRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Runtime.ManagedActionRequest

  @primary_key {:action_request_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "replay_managed_action_requests" do
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
    field(:action_kind, :string)
    field(:packet_id, :string)
    field(:evidence_id, :string)
    field(:request_document, :map, default: %{})
    field(:requested_at, :utc_datetime_usec)

    timestamps(updated_at: false)
  end

  @required_fields [
    :action_request_id,
    :replay_run_id,
    :mission_id,
    :capability_instance_id,
    :family_key,
    :activation_id,
    :binding_set_id,
    :binding_set_version,
    :partition_affinity,
    :partition_value,
    :action_kind,
    :request_document,
    :requested_at
  ]

  @spec changeset(binary(), ManagedActionRequest.t()) :: Ecto.Changeset.t()
  def changeset(replay_run_id, %ManagedActionRequest{} = action_request)
      when is_binary(replay_run_id) do
    %__MODULE__{}
    |> cast(domain_attrs(replay_run_id, action_request), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:replay_run_id)
    |> foreign_key_constraint(:evidence_id)
  end

  @spec to_domain(struct()) :: ManagedActionRequest.t()
  def to_domain(%__MODULE__{} = row) do
    %ManagedActionRequest{
      action_request_id: row.action_request_id,
      mission_id: row.mission_id,
      capability_instance_id: row.capability_instance_id,
      family_key: String.to_existing_atom(row.family_key),
      activation_id: row.activation_id,
      binding_set_id: row.binding_set_id,
      binding_set_version: row.binding_set_version,
      partition_affinity: String.to_existing_atom(row.partition_affinity),
      partition_value: row.partition_value,
      action_kind: String.to_existing_atom(row.action_kind),
      packet_id: row.packet_id,
      evidence_id: row.evidence_id,
      request_document: row.request_document,
      requested_at: row.requested_at
    }
  end

  defp domain_attrs(replay_run_id, %ManagedActionRequest{} = action_request) do
    %{
      action_request_id: action_request.action_request_id,
      replay_run_id: replay_run_id,
      mission_id: action_request.mission_id,
      capability_instance_id: action_request.capability_instance_id,
      family_key: Atom.to_string(action_request.family_key),
      activation_id: action_request.activation_id,
      binding_set_id: action_request.binding_set_id,
      binding_set_version: action_request.binding_set_version,
      partition_affinity: Atom.to_string(action_request.partition_affinity),
      partition_value: action_request.partition_value,
      action_kind: Atom.to_string(action_request.action_kind),
      packet_id: action_request.packet_id,
      evidence_id: action_request.evidence_id,
      request_document: JsonDocument.encode(action_request.request_document),
      requested_at: action_request.requested_at
    }
  end

  defp all_fields do
    [
      :action_request_id,
      :replay_run_id,
      :mission_id,
      :capability_instance_id,
      :family_key,
      :activation_id,
      :binding_set_id,
      :binding_set_version,
      :partition_affinity,
      :partition_value,
      :action_kind,
      :packet_id,
      :evidence_id,
      :request_document,
      :requested_at
    ]
  end
end
