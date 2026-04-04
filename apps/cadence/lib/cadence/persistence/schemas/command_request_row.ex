defmodule Cadence.Persistence.Schemas.CommandRequestRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Commanding.CommandRequest
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:command_request_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "command_requests" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:source_endpoint_ref, :string)
    field(:command_snapshot_id, :string)
    field(:command_id, :string)
    field(:command_name, :string)
    field(:command_display_name, :string)
    field(:lifecycle_state, :string)
    field(:verification_state, :string)
    field(:priority, :integer, default: 3)
    field(:not_before, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
    field(:requested_by_document, :map, default: %{})
    field(:source_command_stage_id, :string)
    field(:source_staged_command_item_id, :string)
    field(:argument_values_document, :map, default: %{})
    field(:resolved_argument_values_document, :map, default: %{})
    field(:significance, :string)
    field(:critical, :boolean, default: false)
    field(:hazardous, :boolean, default: false)
    field(:subsystem, :string)
    field(:group_name, :string)
    field(:preferred_uplink_service, :string)
    field(:release_policy_hint, :string)
    field(:apid, :integer)
    field(:service_type, :integer)
    field(:service_subtype, :integer)
    field(:opcode_document, :map, default: %{})
    field(:requested_at, :utc_datetime_usec)
    field(:metadata_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :command_request_id,
    :mission_id,
    :source_endpoint_ref,
    :command_snapshot_id,
    :command_id,
    :command_name,
    :lifecycle_state,
    :priority,
    :requested_by_document,
    :argument_values_document,
    :resolved_argument_values_document,
    :metadata_document,
    :requested_at
  ]

  @spec changeset(CommandRequest.t()) :: Ecto.Changeset.t()
  def changeset(%CommandRequest{} = command_request) do
    %__MODULE__{}
    |> cast(domain_attrs(command_request), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> unique_constraint([:mission_id, :command_request_id], name: :command_requests_scope_idx)
  end

  @spec lifecycle_changeset(struct(), atom()) :: Ecto.Changeset.t()
  def lifecycle_changeset(%__MODULE__{} = row, lifecycle_state) when is_atom(lifecycle_state) do
    change(row, %{lifecycle_state: Atom.to_string(lifecycle_state)})
  end

  @spec verification_state_changeset(struct(), atom() | nil) :: Ecto.Changeset.t()
  def verification_state_changeset(%__MODULE__{} = row, nil) do
    change(row, %{verification_state: nil})
  end

  def verification_state_changeset(%__MODULE__{} = row, verification_state)
      when is_atom(verification_state) do
    change(row, %{verification_state: Atom.to_string(verification_state)})
  end

  @spec to_domain(struct()) :: CommandRequest.t()
  def to_domain(%__MODULE__{} = row) do
    CommandRequest.new(%{
      command_request_id: row.command_request_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      source_endpoint_ref: row.source_endpoint_ref,
      command_snapshot_id: row.command_snapshot_id,
      command_id: row.command_id,
      command_name: row.command_name,
      command_display_name: row.command_display_name,
      lifecycle_state: row.lifecycle_state,
      verification_state: row.verification_state,
      priority: row.priority,
      not_before: row.not_before,
      expires_at: row.expires_at,
      requested_by: JsonDocument.unwrap_value(row.requested_by_document),
      source_command_stage_id: row.source_command_stage_id,
      source_staged_command_item_id: row.source_staged_command_item_id,
      argument_values: JsonDocument.unwrap_value(row.argument_values_document),
      resolved_argument_values: JsonDocument.unwrap_value(row.resolved_argument_values_document),
      significance: row.significance,
      critical: row.critical,
      hazardous: row.hazardous,
      subsystem: row.subsystem,
      group_name: row.group_name,
      preferred_uplink_service: row.preferred_uplink_service,
      release_policy_hint: row.release_policy_hint,
      apid: row.apid,
      service_type: row.service_type,
      service_subtype: row.service_subtype,
      opcode: JsonDocument.unwrap_value(row.opcode_document),
      requested_at: row.requested_at,
      metadata: JsonDocument.unwrap_value(row.metadata_document)
    })
  end

  defp domain_attrs(%CommandRequest{} = command_request) do
    %{
      command_request_id: command_request.command_request_id,
      organization_id: command_request.organization_id,
      mission_id: command_request.mission_id,
      source_endpoint_ref: command_request.source_endpoint_ref,
      command_snapshot_id: command_request.command_snapshot_id,
      command_id: command_request.command_id,
      command_name: command_request.command_name,
      command_display_name: command_request.command_display_name,
      lifecycle_state: Atom.to_string(command_request.lifecycle_state),
      verification_state:
        case command_request.verification_state do
          nil -> nil
          verification_state -> Atom.to_string(verification_state)
        end,
      priority: command_request.priority,
      not_before: command_request.not_before,
      expires_at: command_request.expires_at,
      requested_by_document: JsonDocument.wrap_value(command_request.requested_by),
      source_command_stage_id: command_request.source_command_stage_id,
      source_staged_command_item_id: command_request.source_staged_command_item_id,
      argument_values_document: JsonDocument.wrap_value(command_request.argument_values),
      resolved_argument_values_document:
        JsonDocument.wrap_value(command_request.resolved_argument_values),
      significance:
        case command_request.significance do
          nil -> nil
          significance -> Atom.to_string(significance)
        end,
      critical: command_request.critical,
      hazardous: command_request.hazardous,
      subsystem: command_request.subsystem,
      group_name: command_request.group_name,
      preferred_uplink_service: command_request.preferred_uplink_service,
      release_policy_hint: command_request.release_policy_hint,
      apid: command_request.apid,
      service_type: command_request.service_type,
      service_subtype: command_request.service_subtype,
      opcode_document: JsonDocument.wrap_value(command_request.opcode),
      requested_at: command_request.requested_at,
      metadata_document: JsonDocument.wrap_value(command_request.metadata)
    }
  end

  defp all_fields do
    [
      :command_request_id,
      :organization_id,
      :mission_id,
      :source_endpoint_ref,
      :command_snapshot_id,
      :command_id,
      :command_name,
      :command_display_name,
      :lifecycle_state,
      :verification_state,
      :priority,
      :not_before,
      :expires_at,
      :requested_by_document,
      :source_command_stage_id,
      :source_staged_command_item_id,
      :argument_values_document,
      :resolved_argument_values_document,
      :significance,
      :critical,
      :hazardous,
      :subsystem,
      :group_name,
      :preferred_uplink_service,
      :release_policy_hint,
      :apid,
      :service_type,
      :service_subtype,
      :opcode_document,
      :requested_at,
      :metadata_document
    ]
  end
end
