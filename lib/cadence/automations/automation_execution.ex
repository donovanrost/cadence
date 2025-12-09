defmodule Cadence.Automations.AutomationExecution do
  @moduledoc """
  Schema for tracking automation executions.

  Records when an automation was triggered, what event caused it,
  and what action was taken.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending running completed failed skipped)a

  schema "automation_executions" do
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :trigger_event, :map
    field :action_result, :map
    field :error_message, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    # Idempotency key for preventing duplicate executions from the same event
    field :idempotency_key, :string

    belongs_to :automation, Cadence.Automations.Automation
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission

    # Link to the procedure execution if action is execute_procedure
    belongs_to :procedure_execution, Cadence.Procedures.ProcedureExecution

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :status,
      :trigger_event,
      :action_result,
      :error_message,
      :started_at,
      :completed_at,
      :idempotency_key,
      :automation_id,
      :organization_id,
      :mission_id,
      :procedure_execution_id
    ])
    |> validate_required([:automation_id, :organization_id, :trigger_event])
    |> unique_constraint(:idempotency_key, name: :automation_executions_idempotency_key_index)
    |> foreign_key_constraint(:automation_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:procedure_execution_id)
  end

  @doc false
  def status_changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :status,
      :action_result,
      :error_message,
      :started_at,
      :completed_at,
      :procedure_execution_id
    ])
  end
end
