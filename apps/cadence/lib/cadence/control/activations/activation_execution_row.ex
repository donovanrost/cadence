defmodule Cadence.Control.Activations.ActivationExecutionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Control.Activations.ActivationExecution
  alias Cadence.Persistence.JsonDocument

  @primary_key {:activation_execution_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "activation_executions" do
    field(:activation_request_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:status, Ecto.Enum, values: [:in_progress, :succeeded, :failed])
    field(:executor_actor_document, :map, default: %{})
    field(:activation_id, :string)
    field(:generation, :integer)
    field(:binding_set_content_sha256, :string)
    field(:error_document, :map, default: %{})
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)

    timestamps()
  end

  @fields [
    :activation_execution_id,
    :activation_request_id,
    :organization_id,
    :mission_id,
    :status,
    :executor_actor_document,
    :activation_id,
    :generation,
    :binding_set_content_sha256,
    :error_document,
    :started_at,
    :completed_at
  ]

  @required_fields [
    :activation_execution_id,
    :activation_request_id,
    :organization_id,
    :mission_id,
    :status,
    :executor_actor_document,
    :binding_set_content_sha256,
    :error_document,
    :started_at
  ]

  def changeset(%ActivationExecution{} = execution) do
    %__MODULE__{}
    |> cast(domain_attrs(execution), @fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:activation_request_id, name: :activation_executions_request_idx)
  end

  def completion_changeset(%__MODULE__{} = row, attrs) do
    row
    |> cast(attrs, [:status, :activation_id, :generation, :error_document, :completed_at])
    |> validate_required([:status, :error_document, :completed_at])
  end

  def to_domain(%__MODULE__{} = row) do
    %ActivationExecution{
      activation_execution_id: row.activation_execution_id,
      activation_request_id: row.activation_request_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      status: row.status,
      executor_actor_document: JsonDocument.unwrap_value(row.executor_actor_document),
      activation_id: row.activation_id,
      generation: row.generation,
      binding_set_content_sha256: row.binding_set_content_sha256,
      error_document: JsonDocument.unwrap_value(row.error_document),
      started_at: row.started_at,
      completed_at: row.completed_at
    }
  end

  defp domain_attrs(execution) do
    execution
    |> Map.from_struct()
    |> Map.update!(:executor_actor_document, &JsonDocument.wrap_value/1)
    |> Map.update!(:error_document, &JsonDocument.wrap_value/1)
  end
end
