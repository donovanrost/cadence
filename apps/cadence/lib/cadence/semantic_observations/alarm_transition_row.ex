defmodule Cadence.SemanticObservations.AlarmTransitionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.{JsonDocument, OrganizationScope}
  alias Cadence.Platform.ContentBasis

  # The transition id (#950): a versioned basis of NAMED scalars: the evaluation it came from
  # (itself an identity, `MonitoringEvaluationRow`) and the two states. The transition document, the
  # times and the rest are payload, so a replay under a newer struct finds the same id (episode
  # events and the latest state reference it).
  @basis_name "alarm_transition"
  @basis_version 1
  @basis_fields [:evaluation_id, :from_state, :to_state]

  @doc false
  def basis_fields, do: @basis_fields

  @doc "The transition id of attrs carrying the basis fields."
  @spec transition_id(map()) :: binary()
  def transition_id(attrs) do
    ContentBasis.digest(
      @basis_name,
      @basis_version,
      Enum.map(@basis_fields, &{&1, Map.get(attrs, &1)})
    )
  end

  @primary_key {:transition_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "semantic_alarm_transitions" do
    field(:evaluation_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_id, :string)
    field(:parameter_id, :string)
    field(:policy_id, :string)
    field(:from_state, :string)
    field(:to_state, :string)
    field(:receipt_time, :utc_datetime_usec)
    field(:transition_document, :map)

    timestamps()
  end

  def changeset(attrs) do
    attrs = Map.put_new_lazy(attrs, :transition_id, fn -> transition_id(attrs) end)

    %__MODULE__{}
    |> cast(attrs, Map.keys(attrs))
    |> OrganizationScope.put_organization_id()
    |> validate_required(Map.keys(attrs) -- [:organization_id, :spacecraft_id])
  end

  def attrs(evaluation_attrs, result) do
    base = %{
      evaluation_id: evaluation_attrs.evaluation_id,
      organization_id: evaluation_attrs.organization_id,
      mission_id: evaluation_attrs.mission_id,
      spacecraft_id: evaluation_attrs.spacecraft_id,
      parameter_id: evaluation_attrs.parameter_id,
      policy_id: evaluation_attrs.policy_id,
      from_state: Atom.to_string(result.transition.from),
      to_state: Atom.to_string(result.transition.to),
      receipt_time: evaluation_attrs.receipt_time,
      transition_document: JsonDocument.wrap_value(result.transition)
    }

    Map.put(base, :transition_id, transition_id(base))
  end
end
