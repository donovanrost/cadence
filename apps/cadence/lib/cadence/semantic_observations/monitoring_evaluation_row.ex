defmodule Cadence.SemanticObservations.MonitoringEvaluationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.MissionModel.Canonical
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

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
      Map.put_new(attrs, :evaluation_id, Canonical.content_id("monitoring_evaluation", attrs))

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

    Map.put(base, :evaluation_id, Canonical.content_id("monitoring_evaluation", base))
  end

  defp atom_string(nil), do: nil
  defp atom_string(value), do: Atom.to_string(value)
end
