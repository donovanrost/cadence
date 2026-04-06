defmodule Cadence.Persistence.Schemas.SetupWorkflowRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Setup.Workflow

  @primary_key {:setup_workflow_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]
  @required_fields [:setup_workflow_id, :current_step, :metadata]
  @current_step_values Enum.map(Workflow.steps(), &Atom.to_string/1)

  schema "setup_workflows" do
    field(:current_step, :string)
    field(:active_organization_id, :string)
    field(:created_by_user_id, :string)
    field(:completed_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @spec changeset(Workflow.t()) :: Ecto.Changeset.t()
  def changeset(%Workflow{} = workflow) do
    %__MODULE__{}
    |> cast(row_attrs(workflow), all_fields())
    |> validate_required(@required_fields)
    |> validate_inclusion(:current_step, @current_step_values)
    |> unique_constraint(:setup_workflow_id, name: :setup_workflows_pkey)
  end

  @spec update_changeset(struct(), Workflow.t()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = row, %Workflow{} = workflow) do
    row
    |> cast(row_attrs(workflow), updatable_fields())
    |> validate_required([:current_step, :metadata])
    |> validate_inclusion(:current_step, @current_step_values)
  end

  @spec to_domain(struct()) :: Workflow.t()
  def to_domain(%__MODULE__{} = row) do
    Workflow.new(%{
      setup_workflow_id: row.setup_workflow_id,
      current_step: row.current_step,
      active_organization_id: row.active_organization_id,
      created_by_user_id: row.created_by_user_id,
      completed_at: row.completed_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp row_attrs(%Workflow{} = workflow) do
    %{
      setup_workflow_id: workflow.setup_workflow_id,
      current_step: Atom.to_string(workflow.current_step),
      active_organization_id: workflow.active_organization_id,
      created_by_user_id: workflow.created_by_user_id,
      completed_at: workflow.completed_at,
      metadata: JsonDocument.wrap_value(workflow.metadata)
    }
  end

  defp all_fields do
    [
      :setup_workflow_id,
      :current_step,
      :active_organization_id,
      :created_by_user_id,
      :completed_at,
      :metadata
    ]
  end

  defp updatable_fields do
    [:current_step, :active_organization_id, :created_by_user_id, :completed_at, :metadata]
  end
end
