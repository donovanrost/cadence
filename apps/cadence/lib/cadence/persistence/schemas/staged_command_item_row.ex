defmodule Cadence.Persistence.Schemas.StagedCommandItemRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Commanding.StagedCommandItem
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:staged_command_item_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "staged_command_items" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:command_stage_id, :string)
    field(:source_endpoint_ref, :string)
    field(:command_snapshot_id, :string)
    field(:command_id, :string)
    field(:argument_values_document, :map, default: %{})
    field(:priority, :integer, default: 3)
    field(:not_before, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
    field(:notes, :string)
    field(:item_order, :integer, default: 0)
    field(:lifecycle_state, :string)
    field(:submitted_command_request_id, :string)
    field(:metadata_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :staged_command_item_id,
    :mission_id,
    :command_stage_id,
    :source_endpoint_ref,
    :command_snapshot_id,
    :command_id,
    :argument_values_document,
    :priority,
    :item_order,
    :lifecycle_state,
    :metadata_document
  ]

  @spec changeset(StagedCommandItem.t()) :: Ecto.Changeset.t()
  def changeset(%StagedCommandItem{} = staged_command_item) do
    %__MODULE__{}
    |> cast(domain_attrs(staged_command_item), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_number(:item_order, greater_than_or_equal_to: 0)
    |> unique_constraint([:mission_id, :staged_command_item_id],
      name: :staged_command_items_scope_idx
    )
  end

  @spec update_changeset(struct(), StagedCommandItem.t()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = row, %StagedCommandItem{} = staged_command_item) do
    row
    |> cast(domain_attrs(staged_command_item), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_number(:item_order, greater_than_or_equal_to: 0)
  end

  @spec submission_changeset(struct(), binary()) :: Ecto.Changeset.t()
  def submission_changeset(%__MODULE__{} = row, command_request_id)
      when is_binary(command_request_id) do
    change(row, %{
      lifecycle_state: "submitted",
      submitted_command_request_id: command_request_id
    })
  end

  @spec to_domain(struct()) :: StagedCommandItem.t()
  def to_domain(%__MODULE__{} = row) do
    StagedCommandItem.new(%{
      staged_command_item_id: row.staged_command_item_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      command_stage_id: row.command_stage_id,
      source_endpoint_ref: row.source_endpoint_ref,
      command_snapshot_id: row.command_snapshot_id,
      command_id: row.command_id,
      argument_values: JsonDocument.unwrap_value(row.argument_values_document),
      priority: row.priority,
      not_before: row.not_before,
      expires_at: row.expires_at,
      notes: row.notes,
      item_order: row.item_order,
      lifecycle_state: row.lifecycle_state,
      submitted_command_request_id: row.submitted_command_request_id,
      metadata: JsonDocument.unwrap_value(row.metadata_document)
    })
  end

  defp domain_attrs(%StagedCommandItem{} = staged_command_item) do
    %{
      staged_command_item_id: staged_command_item.staged_command_item_id,
      organization_id: staged_command_item.organization_id,
      mission_id: staged_command_item.mission_id,
      command_stage_id: staged_command_item.command_stage_id,
      source_endpoint_ref: staged_command_item.source_endpoint_ref,
      command_snapshot_id: staged_command_item.command_snapshot_id,
      command_id: staged_command_item.command_id,
      argument_values_document: JsonDocument.wrap_value(staged_command_item.argument_values),
      priority: staged_command_item.priority,
      not_before: staged_command_item.not_before,
      expires_at: staged_command_item.expires_at,
      notes: staged_command_item.notes,
      item_order: staged_command_item.item_order,
      lifecycle_state: Atom.to_string(staged_command_item.lifecycle_state),
      submitted_command_request_id: staged_command_item.submitted_command_request_id,
      metadata_document: JsonDocument.wrap_value(staged_command_item.metadata)
    }
  end

  defp all_fields do
    [
      :staged_command_item_id,
      :organization_id,
      :mission_id,
      :command_stage_id,
      :source_endpoint_ref,
      :command_snapshot_id,
      :command_id,
      :argument_values_document,
      :priority,
      :not_before,
      :expires_at,
      :notes,
      :item_order,
      :lifecycle_state,
      :submitted_command_request_id,
      :metadata_document
    ]
  end
end
