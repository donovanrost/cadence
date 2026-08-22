defmodule Cadence.Commanding.CommandApprovalRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Commanding.CommandApproval
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:command_approval_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "command_approvals" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:command_request_id, :string)
    field(:decision, :string)
    field(:decided_by_document, :map, default: %{})
    field(:decided_at, :utc_datetime_usec)
    field(:reason, :string)
    field(:metadata_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :command_approval_id,
    :mission_id,
    :command_request_id,
    :decision,
    :decided_by_document,
    :decided_at,
    :metadata_document
  ]

  @spec changeset(CommandApproval.t()) :: Ecto.Changeset.t()
  def changeset(%CommandApproval{} = command_approval) do
    %__MODULE__{}
    |> cast(domain_attrs(command_approval), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :command_approval_id], name: :command_approvals_scope_idx)
  end

  @spec to_domain(struct()) :: CommandApproval.t()
  def to_domain(%__MODULE__{} = row) do
    CommandApproval.new(%{
      command_approval_id: row.command_approval_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      command_request_id: row.command_request_id,
      decision: row.decision,
      decided_by: JsonDocument.unwrap_value(row.decided_by_document),
      decided_at: row.decided_at,
      reason: row.reason,
      metadata: JsonDocument.unwrap_value(row.metadata_document)
    })
  end

  defp domain_attrs(%CommandApproval{} = command_approval) do
    %{
      command_approval_id: command_approval.command_approval_id,
      organization_id: command_approval.organization_id,
      mission_id: command_approval.mission_id,
      command_request_id: command_approval.command_request_id,
      decision: Atom.to_string(command_approval.decision),
      decided_by_document: JsonDocument.wrap_value(command_approval.decided_by),
      decided_at: command_approval.decided_at,
      reason: command_approval.reason,
      metadata_document: JsonDocument.wrap_value(command_approval.metadata)
    }
  end

  defp all_fields do
    [
      :command_approval_id,
      :organization_id,
      :mission_id,
      :command_request_id,
      :decision,
      :decided_by_document,
      :decided_at,
      :reason,
      :metadata_document
    ]
  end
end
