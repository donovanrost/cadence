defmodule Cadence.SemanticObservations.AlarmTransitionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Catalog.MissionModel.Canonical
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

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
    attrs = Map.put_new(attrs, :transition_id, Canonical.content_id("alarm_transition", attrs))

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

    Map.put(base, :transition_id, Canonical.content_id("alarm_transition", base))
  end
end
