defmodule Cadence.SemanticObservations.LatestAlarmStateRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @timestamps_opts [type: :utc_datetime_usec]

  schema "semantic_latest_alarm_states" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_scope_id, :string)
    field(:spacecraft_id, :string)
    field(:parameter_id, :string)
    field(:policy_id, :string)
    field(:evaluation_id, :string)
    field(:transition_id, :string)
    field(:effective_state, :string)
    field(:generation_time, :utc_datetime_usec)
    field(:receipt_time, :utc_datetime_usec)
    field(:state_document, :map)

    timestamps()
  end

  def changeset(attrs) do
    attrs =
      attrs
      |> Map.put(:spacecraft_scope_id, attrs.spacecraft_id || "")
      |> Map.put(:state_document, JsonDocument.wrap_value(attrs))

    %__MODULE__{}
    |> cast(attrs, Map.keys(attrs))
    |> OrganizationScope.put_organization_id()
    |> validate_required(Map.keys(attrs) -- [:organization_id, :spacecraft_id, :transition_id])
    |> unique_constraint([:mission_id, :spacecraft_scope_id, :parameter_id, :policy_id],
      name: :semantic_latest_alarm_states_scope_idx
    )
  end
end
