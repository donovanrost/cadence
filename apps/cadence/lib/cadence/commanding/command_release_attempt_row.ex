defmodule Cadence.Commanding.CommandReleaseAttemptRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Commanding.CommandReleaseAttempt
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:command_release_attempt_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "command_release_attempts" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:command_queue_entry_id, :string)
    field(:command_request_id, :string)
    field(:source_endpoint_ref, :string)
    field(:realized_contact_id, :string)
    field(:path_id, :string)
    field(:transport_binding_id, :string)
    field(:command_snapshot_id, :string)
    field(:command_id, :string)
    field(:command_name, :string)
    field(:layout_kind, :string)
    field(:preferred_uplink_service, :string)
    field(:apid, :integer)
    field(:service_type, :integer)
    field(:service_subtype, :integer)
    field(:opcode_document, :map, default: %{})
    field(:encoded_binary_base64, :string)
    field(:encoded_size_bytes, :integer)
    field(:lifecycle_state, :string)
    field(:verification_state, :string)
    field(:failure_reason, :string)
    field(:released_by_document, :map, default: %{})
    field(:attempted_at, :utc_datetime_usec)
    field(:released_at, :utc_datetime_usec)
    field(:metadata_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :command_release_attempt_id,
    :mission_id,
    :command_queue_entry_id,
    :command_request_id,
    :source_endpoint_ref,
    :realized_contact_id,
    :command_snapshot_id,
    :command_id,
    :lifecycle_state,
    :released_by_document,
    :attempted_at,
    :metadata_document
  ]

  @spec changeset(CommandReleaseAttempt.t()) :: Ecto.Changeset.t()
  def changeset(%CommandReleaseAttempt{} = command_release_attempt) do
    %__MODULE__{}
    |> cast(domain_attrs(command_release_attempt), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:encoded_size_bytes, greater_than_or_equal_to: 0)
    |> unique_constraint([:mission_id, :command_release_attempt_id],
      name: :command_release_attempts_scope_idx
    )
  end

  @spec update_changeset(struct(), CommandReleaseAttempt.t()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = row, %CommandReleaseAttempt{} = command_release_attempt) do
    row
    |> cast(domain_attrs(command_release_attempt), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:encoded_size_bytes, greater_than_or_equal_to: 0)
  end

  @spec verification_state_changeset(struct(), atom() | nil) :: Ecto.Changeset.t()
  def verification_state_changeset(%__MODULE__{} = row, nil) do
    change(row, %{verification_state: nil})
  end

  def verification_state_changeset(%__MODULE__{} = row, verification_state)
      when is_atom(verification_state) do
    change(row, %{verification_state: Atom.to_string(verification_state)})
  end

  @spec to_domain(struct()) :: CommandReleaseAttempt.t()
  def to_domain(%__MODULE__{} = row) do
    CommandReleaseAttempt.new(%{
      command_release_attempt_id: row.command_release_attempt_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      command_queue_entry_id: row.command_queue_entry_id,
      command_request_id: row.command_request_id,
      source_endpoint_ref: row.source_endpoint_ref,
      realized_contact_id: row.realized_contact_id,
      path_id: row.path_id,
      transport_binding_id: row.transport_binding_id,
      command_snapshot_id: row.command_snapshot_id,
      command_id: row.command_id,
      command_name: row.command_name,
      layout_kind: row.layout_kind,
      preferred_uplink_service: row.preferred_uplink_service,
      apid: row.apid,
      service_type: row.service_type,
      service_subtype: row.service_subtype,
      opcode: JsonDocument.unwrap_value(row.opcode_document),
      encoded_binary_base64: row.encoded_binary_base64,
      encoded_size_bytes: row.encoded_size_bytes,
      lifecycle_state: row.lifecycle_state,
      verification_state: row.verification_state,
      failure_reason: row.failure_reason,
      released_by: JsonDocument.unwrap_value(row.released_by_document),
      attempted_at: row.attempted_at,
      released_at: row.released_at,
      metadata: JsonDocument.unwrap_value(row.metadata_document)
    })
  end

  defp domain_attrs(%CommandReleaseAttempt{} = command_release_attempt) do
    %{
      command_release_attempt_id: command_release_attempt.command_release_attempt_id,
      organization_id: command_release_attempt.organization_id,
      mission_id: command_release_attempt.mission_id,
      command_queue_entry_id: command_release_attempt.command_queue_entry_id,
      command_request_id: command_release_attempt.command_request_id,
      source_endpoint_ref: command_release_attempt.source_endpoint_ref,
      realized_contact_id: command_release_attempt.realized_contact_id,
      path_id: command_release_attempt.path_id,
      transport_binding_id: command_release_attempt.transport_binding_id,
      command_snapshot_id: command_release_attempt.command_snapshot_id,
      command_id: command_release_attempt.command_id,
      command_name: command_release_attempt.command_name,
      layout_kind:
        case command_release_attempt.layout_kind do
          nil -> nil
          layout_kind -> Atom.to_string(layout_kind)
        end,
      preferred_uplink_service: command_release_attempt.preferred_uplink_service,
      apid: command_release_attempt.apid,
      service_type: command_release_attempt.service_type,
      service_subtype: command_release_attempt.service_subtype,
      opcode_document: JsonDocument.wrap_value(command_release_attempt.opcode),
      encoded_binary_base64: command_release_attempt.encoded_binary_base64,
      encoded_size_bytes: command_release_attempt.encoded_size_bytes,
      lifecycle_state: Atom.to_string(command_release_attempt.lifecycle_state),
      verification_state:
        case command_release_attempt.verification_state do
          nil -> nil
          verification_state -> Atom.to_string(verification_state)
        end,
      failure_reason: command_release_attempt.failure_reason,
      released_by_document: JsonDocument.wrap_value(command_release_attempt.released_by),
      attempted_at: command_release_attempt.attempted_at,
      released_at: command_release_attempt.released_at,
      metadata_document: JsonDocument.wrap_value(command_release_attempt.metadata)
    }
  end

  defp all_fields do
    [
      :command_release_attempt_id,
      :organization_id,
      :mission_id,
      :command_queue_entry_id,
      :command_request_id,
      :source_endpoint_ref,
      :realized_contact_id,
      :path_id,
      :transport_binding_id,
      :command_snapshot_id,
      :command_id,
      :command_name,
      :layout_kind,
      :preferred_uplink_service,
      :apid,
      :service_type,
      :service_subtype,
      :opcode_document,
      :encoded_binary_base64,
      :encoded_size_bytes,
      :lifecycle_state,
      :verification_state,
      :failure_reason,
      :released_by_document,
      :attempted_at,
      :released_at,
      :metadata_document
    ]
  end
end
