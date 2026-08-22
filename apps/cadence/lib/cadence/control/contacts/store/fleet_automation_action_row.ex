defmodule Cadence.Control.Contacts.Store.FleetAutomationActionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.FleetAutomationAction
  alias Cadence.Persistence.JsonDocument

  @primary_key {:fleet_automation_action_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "fleet_automation_actions" do
    field(:idempotency_key, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:automation_grant_id, :string)
    field(:automation_grant_content_sha256, :string)
    field(:service_identity_id, :string)
    field(:fleet_planning_run_id, :string)
    field(:contact_plan_id, :string)
    field(:contact_plan_version, :integer)
    field(:action, :string)
    field(:lifecycle_state, :string)
    field(:attempt_count, :integer, default: 1)
    field(:evidence_document, :map, default: %{})
    field(:result_document, :map, default: %{})
    field(:error_document, :map, default: %{})
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps()
  end

  @fields [
    :fleet_automation_action_id,
    :idempotency_key,
    :organization_id,
    :mission_id,
    :automation_grant_id,
    :automation_grant_content_sha256,
    :service_identity_id,
    :fleet_planning_run_id,
    :contact_plan_id,
    :contact_plan_version,
    :action,
    :lifecycle_state,
    :attempt_count,
    :evidence_document,
    :result_document,
    :error_document,
    :started_at,
    :completed_at
  ]

  @required @fields -- [:contact_plan_id, :contact_plan_version, :completed_at]

  @spec changeset(FleetAutomationAction.t()) :: Ecto.Changeset.t()
  def changeset(%FleetAutomationAction{} = action) do
    %__MODULE__{}
    |> cast(domain_attrs(action), @fields)
    |> validate_required(@required)
    |> common_validations()
    |> unique_constraint(:idempotency_key,
      name: :fleet_automation_actions_idempotency_idx
    )
  end

  @spec completion_changeset(struct(), map()) :: Ecto.Changeset.t()
  def completion_changeset(%__MODULE__{} = row, attrs) do
    row
    |> cast(attrs, [
      :contact_plan_id,
      :contact_plan_version,
      :lifecycle_state,
      :attempt_count,
      :result_document,
      :error_document,
      :completed_at
    ])
    |> validate_required([
      :lifecycle_state,
      :result_document,
      :error_document,
      :completed_at
    ])
    |> common_validations()
  end

  @spec restart_changeset(struct(), DateTime.t()) :: Ecto.Changeset.t()
  def restart_changeset(%__MODULE__{} = row, started_at) do
    row
    |> cast(
      %{
        lifecycle_state: "running",
        attempt_count: row.attempt_count + 1,
        result_document: %{},
        error_document: %{},
        started_at: started_at,
        completed_at: nil
      },
      [
        :lifecycle_state,
        :attempt_count,
        :result_document,
        :error_document,
        :started_at,
        :completed_at
      ]
    )
    |> validate_required([
      :lifecycle_state,
      :attempt_count,
      :result_document,
      :error_document,
      :started_at
    ])
    |> common_validations()
  end

  @spec to_domain(struct()) :: FleetAutomationAction.t()
  def to_domain(%__MODULE__{} = row) do
    FleetAutomationAction.new(%{
      fleet_automation_action_id: row.fleet_automation_action_id,
      idempotency_key: row.idempotency_key,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      automation_grant_id: row.automation_grant_id,
      automation_grant_content_sha256: row.automation_grant_content_sha256,
      service_identity_id: row.service_identity_id,
      fleet_planning_run_id: row.fleet_planning_run_id,
      contact_plan_id: row.contact_plan_id,
      contact_plan_version: row.contact_plan_version,
      action: row.action,
      lifecycle_state: row.lifecycle_state,
      attempt_count: row.attempt_count,
      evidence_document: JsonDocument.unwrap_value(row.evidence_document),
      result_document: JsonDocument.unwrap_value(row.result_document),
      error_document: JsonDocument.unwrap_value(row.error_document),
      started_at: row.started_at,
      completed_at: row.completed_at,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp common_validations(changeset) do
    changeset
    |> validate_optional_positive(:contact_plan_version)
    |> validate_number(:attempt_count, greater_than: 0)
    |> validate_inclusion(:action, ~w(plan repair submit approve execute))
    |> validate_inclusion(:lifecycle_state, ~w(running succeeded failed skipped))
    |> validate_plan_binding()
  end

  defp validate_plan_binding(changeset) do
    if is_nil(get_field(changeset, :contact_plan_id)) ==
         is_nil(get_field(changeset, :contact_plan_version)),
       do: changeset,
       else: add_error(changeset, :contact_plan_id, "must be set with version")
  end

  defp validate_optional_positive(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than: 0)
    end
  end

  defp domain_attrs(action) do
    %{
      fleet_automation_action_id: action.fleet_automation_action_id,
      idempotency_key: action.idempotency_key,
      organization_id: action.organization_id,
      mission_id: action.mission_id,
      automation_grant_id: action.automation_grant_id,
      automation_grant_content_sha256: action.automation_grant_content_sha256,
      service_identity_id: action.service_identity_id,
      fleet_planning_run_id: action.fleet_planning_run_id,
      contact_plan_id: action.contact_plan_id,
      contact_plan_version: action.contact_plan_version,
      action: Atom.to_string(action.action),
      lifecycle_state: Atom.to_string(action.lifecycle_state),
      attempt_count: action.attempt_count,
      evidence_document: JsonDocument.wrap_value(action.evidence_document),
      result_document: JsonDocument.wrap_value(action.result_document),
      error_document: JsonDocument.wrap_value(action.error_document),
      started_at: action.started_at,
      completed_at: action.completed_at
    }
  end
end
