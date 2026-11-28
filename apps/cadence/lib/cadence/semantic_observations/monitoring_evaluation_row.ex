defmodule Cadence.SemanticObservations.MonitoringEvaluationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.{JsonDocument, OrganizationScope}
  alias Cadence.Platform.ContentBasis

  # The evaluation id (#950): a versioned basis of NAMED scalars, the evaluation's identity and
  # nothing else (the outcome, counts, plan and times are payload, `unique (policy_id, update_id)`
  # already makes the pair the row's natural key). A replay that recomputes the outcome under a
  # newer struct, plan or recovery finds the same id. Adding a field to the basis needs a version
  # bump; the struct canary (`evidence_id_basis_test.exs`) pins what the result struct may carry.
  @basis_name "monitoring_evaluation"
  @basis_version 1
  @basis_fields [
    :organization_id,
    :mission_id,
    :spacecraft_id,
    :parameter_id,
    :policy_id,
    :update_id
  ]

  @doc false
  def basis_fields, do: @basis_fields

  @doc "The evaluation id of attrs carrying the basis fields."
  @spec evaluation_id(map()) :: binary()
  def evaluation_id(attrs) do
    ContentBasis.digest(
      @basis_name,
      @basis_version,
      Enum.map(@basis_fields, &{&1, Map.get(attrs, &1)})
    )
  end

  @primary_key {:evaluation_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "semantic_monitoring_evaluations" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_id, :string)
    field(:parameter_id, :string)
    field(:policy_id, :string)
    field(:update_id, :string)
    field(:mission_model_revision_id, :string)
    field(:runtime_plan_id, :string)
    field(:evaluated_state, :string)
    field(:effective_state, :string)
    field(:previous_state, :string)
    field(:transitioned, :boolean)
    field(:matched_context, :string)
    field(:violation_count, :integer)
    field(:conformance_count, :integer)
    field(:generation_time, :utc_datetime_usec)
    field(:receipt_time, :utc_datetime_usec)
    field(:evaluation_document, :map)

    timestamps()
  end

  def changeset(attrs) do
    attrs =
      Map.put_new_lazy(attrs, :evaluation_id, fn -> evaluation_id(attrs) end)

    %__MODULE__{}
    |> cast(attrs, Map.keys(attrs))
    |> OrganizationScope.put_organization_id()
    |> validate_required([
      :evaluation_id,
      :mission_id,
      :parameter_id,
      :policy_id,
      :update_id,
      :mission_model_revision_id,
      :runtime_plan_id,
      :evaluated_state,
      :effective_state,
      :transitioned,
      :violation_count,
      :conformance_count,
      :receipt_time,
      :evaluation_document
    ])
    |> unique_constraint([:policy_id, :update_id])
  end

  def attrs(result, update, context) do
    base = %{
      organization_id: context.organization_id,
      mission_id: context.mission_id,
      spacecraft_id:
        Map.get(update.metadata, :spacecraft_id, Map.get(update.metadata, "spacecraft_id")),
      parameter_id: result.parameter_id,
      policy_id: result.policy_id,
      update_id: result.update_id,
      mission_model_revision_id: context.mission_model_revision_id,
      runtime_plan_id: context.runtime_plan_id,
      evaluated_state: Atom.to_string(result.evaluated_state),
      effective_state: Atom.to_string(result.effective_state),
      previous_state: atom_string(result.previous_state),
      transitioned: not is_nil(result.transition),
      matched_context: result.matched_context,
      violation_count: result.violation_count,
      conformance_count: result.conformance_count,
      generation_time: update.generation_time,
      receipt_time: update.receipt_time,
      evaluation_document: JsonDocument.wrap_value(result)
    }

    Map.put(base, :evaluation_id, evaluation_id(base))
  end

  defp atom_string(nil), do: nil
  defp atom_string(value), do: Atom.to_string(value)
end
