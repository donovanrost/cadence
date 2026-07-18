defmodule Cadence.Persistence.Schemas.ContactPlanApprovalRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactPlanApproval
  alias Cadence.Persistence.JsonDocument

  @primary_key {:contact_plan_approval_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "contact_plan_approvals" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_plan_id, :string)
    field(:contact_plan_version, :integer)
    field(:decision, :string)
    field(:content_sha256, :string)
    field(:reason, :string)
    field(:actor_kind, :string)
    field(:actor_id, :string)
    field(:actor_document, :map)
    field(:automation_grant_id, :string)
    field(:automation_grant_content_sha256, :string)
    field(:decided_at, :utc_datetime_usec)

    timestamps(updated_at: false)
  end

  @fields [
    :contact_plan_approval_id,
    :organization_id,
    :mission_id,
    :contact_plan_id,
    :contact_plan_version,
    :decision,
    :content_sha256,
    :reason,
    :actor_kind,
    :actor_id,
    :actor_document,
    :automation_grant_id,
    :automation_grant_content_sha256,
    :decided_at
  ]

  @spec changeset(ContactPlanApproval.t()) :: Ecto.Changeset.t()
  def changeset(%ContactPlanApproval{} = approval) do
    %__MODULE__{}
    |> cast(domain_attrs(approval), @fields)
    |> validate_required(@fields -- [:automation_grant_id, :automation_grant_content_sha256])
    |> validate_number(:contact_plan_version, greater_than: 0)
    |> validate_inclusion(:decision, ~w(approved rejected))
    |> validate_inclusion(:actor_kind, ~w(user service))
    |> validate_automation_shape()
    |> validate_format(:content_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> validate_length(:reason, min: 1, max: 2_000)
    |> unique_constraint(
      [:contact_plan_id, :contact_plan_version],
      name: :contact_plan_approvals_version_idx
    )
    |> foreign_key_constraint(:contact_plan_version,
      name: :contact_plan_approvals_plan_version_fk
    )
  end

  @spec to_domain(struct()) :: ContactPlanApproval.t()
  def to_domain(%__MODULE__{} = row) do
    ContactPlanApproval.new(%{
      contact_plan_approval_id: row.contact_plan_approval_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      contact_plan_id: row.contact_plan_id,
      contact_plan_version: row.contact_plan_version,
      decision: row.decision,
      content_sha256: row.content_sha256,
      reason: row.reason,
      actor_kind: row.actor_kind,
      actor_id: row.actor_id,
      actor_document: JsonDocument.unwrap_value(row.actor_document),
      automation_grant_id: row.automation_grant_id,
      automation_grant_content_sha256: row.automation_grant_content_sha256,
      decided_at: row.decided_at,
      inserted_at: row.inserted_at
    })
  end

  defp domain_attrs(approval) do
    %{
      contact_plan_approval_id: approval.contact_plan_approval_id,
      organization_id: approval.organization_id,
      mission_id: approval.mission_id,
      contact_plan_id: approval.contact_plan_id,
      contact_plan_version: approval.contact_plan_version,
      decision: Atom.to_string(approval.decision),
      content_sha256: approval.content_sha256,
      reason: approval.reason,
      actor_kind: Atom.to_string(approval.actor_kind),
      actor_id: approval.actor_id,
      actor_document: JsonDocument.wrap_value(approval.actor_document),
      automation_grant_id: approval.automation_grant_id,
      automation_grant_content_sha256: approval.automation_grant_content_sha256,
      decided_at: approval.decided_at
    }
  end

  defp validate_automation_shape(changeset) do
    kind = get_field(changeset, :actor_kind)
    grant_id = get_field(changeset, :automation_grant_id)
    grant_hash = get_field(changeset, :automation_grant_content_sha256)

    case {kind, grant_id, grant_hash} do
      {"user", nil, nil} -> changeset
      {"service", id, hash} when is_binary(id) and is_binary(hash) -> changeset
      _shape -> add_error(changeset, :automation_grant_id, "does not match actor kind")
    end
  end
end
