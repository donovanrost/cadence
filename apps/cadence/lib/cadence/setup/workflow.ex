defmodule Cadence.Setup.Workflow do
  @moduledoc """
  Durable workflow state for Cadence first-run setup.
  """

  @initial_workflow_id "initial_setup"
  @steps [
    :pending_tenant_creation,
    :pending_durable_admin_handoff,
    :pending_completion,
    :completed
  ]

  @type step ::
          :pending_tenant_creation
          | :pending_durable_admin_handoff
          | :pending_completion
          | :completed

  @type t :: %__MODULE__{
          setup_workflow_id: binary(),
          current_step: step(),
          active_organization_id: binary() | nil,
          created_by_user_id: binary() | nil,
          completed_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :setup_workflow_id,
    :current_step,
    :active_organization_id,
    :created_by_user_id,
    :completed_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      setup_workflow_id:
        Map.get(
          attrs,
          :setup_workflow_id,
          Map.get(attrs, "setup_workflow_id", @initial_workflow_id)
        ),
      current_step:
        attrs
        |> Map.get(:current_step, Map.get(attrs, "current_step", :pending_tenant_creation))
        |> normalize_step(),
      active_organization_id:
        Map.get(attrs, :active_organization_id, Map.get(attrs, "active_organization_id")),
      created_by_user_id:
        Map.get(attrs, :created_by_user_id, Map.get(attrs, "created_by_user_id")),
      completed_at: Map.get(attrs, :completed_at, Map.get(attrs, "completed_at")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  @spec initial_workflow_id() :: binary()
  def initial_workflow_id, do: @initial_workflow_id

  @spec steps() :: [step()]
  def steps, do: @steps

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{current_step: :completed}), do: false
  def active?(%__MODULE__{}), do: true

  @spec pending_tenant_creation?(t()) :: boolean()
  def pending_tenant_creation?(%__MODULE__{current_step: :pending_tenant_creation}), do: true
  def pending_tenant_creation?(%__MODULE__{}), do: false

  defp normalize_step(step) when step in @steps, do: step

  defp normalize_step(step) when is_binary(step) do
    step
    |> String.to_existing_atom()
    |> normalize_step()
  rescue
    ArgumentError -> :pending_tenant_creation
  end
end
