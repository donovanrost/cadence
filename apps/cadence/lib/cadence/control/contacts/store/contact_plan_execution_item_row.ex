defmodule Cadence.Control.Contacts.Store.ContactPlanExecutionItemRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactPlanExecutionItem
  alias Cadence.Persistence.JsonDocument

  @primary_key {:contact_plan_execution_item_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "contact_plan_execution_items" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_plan_id, :string)
    field(:contact_plan_version, :integer)
    field(:contact_opportunity_snapshot_id, :string)
    field(:idempotency_key, :string)
    field(:lifecycle_state, :string)
    field(:provider_reservation_id, :string)
    field(:attempt_count, :integer)
    field(:last_error_document, :map, default: %{})
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :contact_plan_execution_item_id,
    :organization_id,
    :mission_id,
    :contact_plan_id,
    :contact_plan_version,
    :contact_opportunity_snapshot_id,
    :idempotency_key,
    :lifecycle_state,
    :attempt_count,
    :last_error_document
  ]

  @spec changeset(ContactPlanExecutionItem.t()) :: Ecto.Changeset.t()
  def changeset(%ContactPlanExecutionItem{} = item) do
    %__MODULE__{}
    |> cast(domain_attrs(item), fields())
    |> validate_item()
    |> unique_constraint(
      [:contact_plan_id, :contact_plan_version, :contact_opportunity_snapshot_id],
      name: :contact_plan_execution_items_selection_idx
    )
    |> unique_constraint([:mission_id, :idempotency_key],
      name: :contact_plan_execution_items_idempotency_idx
    )
    |> foreign_key_constraint(:contact_plan_version,
      name: :contact_plan_execution_items_plan_version_fk
    )
    |> foreign_key_constraint(:contact_opportunity_snapshot_id,
      name: :contact_plan_execution_items_snapshot_fk
    )
  end

  @spec transition_changeset(struct(), map()) :: Ecto.Changeset.t()
  def transition_changeset(%__MODULE__{} = row, attrs) do
    row
    |> cast(attrs, [
      :lifecycle_state,
      :provider_reservation_id,
      :attempt_count,
      :last_error_document,
      :started_at,
      :completed_at
    ])
    |> validate_item()
    |> foreign_key_constraint(:provider_reservation_id,
      name: :contact_plan_execution_items_reservation_fk
    )
  end

  @spec to_domain(struct()) :: ContactPlanExecutionItem.t()
  def to_domain(%__MODULE__{} = row) do
    ContactPlanExecutionItem.new(%{
      contact_plan_execution_item_id: row.contact_plan_execution_item_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      contact_plan_id: row.contact_plan_id,
      contact_plan_version: row.contact_plan_version,
      contact_opportunity_snapshot_id: row.contact_opportunity_snapshot_id,
      idempotency_key: row.idempotency_key,
      lifecycle_state: row.lifecycle_state,
      provider_reservation_id: row.provider_reservation_id,
      attempt_count: row.attempt_count,
      last_error_document: JsonDocument.unwrap_value(row.last_error_document),
      started_at: row.started_at,
      completed_at: row.completed_at,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp validate_item(changeset) do
    changeset
    |> validate_required(@required_fields)
    |> validate_number(:contact_plan_version, greater_than: 0)
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> validate_inclusion(
      :lifecycle_state,
      Enum.map(ContactPlanExecutionItem.states(), &Atom.to_string/1)
    )
    |> validate_length(:idempotency_key, max: 255)
  end

  defp domain_attrs(item) do
    %{
      contact_plan_execution_item_id: item.contact_plan_execution_item_id,
      organization_id: item.organization_id,
      mission_id: item.mission_id,
      contact_plan_id: item.contact_plan_id,
      contact_plan_version: item.contact_plan_version,
      contact_opportunity_snapshot_id: item.contact_opportunity_snapshot_id,
      idempotency_key: item.idempotency_key,
      lifecycle_state: Atom.to_string(item.lifecycle_state),
      provider_reservation_id: item.provider_reservation_id,
      attempt_count: item.attempt_count,
      last_error_document: JsonDocument.wrap_value(item.last_error_document),
      started_at: item.started_at,
      completed_at: item.completed_at
    }
  end

  defp fields,
    do: @required_fields ++ [:provider_reservation_id, :started_at, :completed_at]
end
