defmodule Cadence.SemanticObservations.AlarmAcknowledgementRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.{JsonDocument, OrganizationScope}

  @primary_key {:acknowledgement_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "semantic_alarm_acknowledgements" do
    field(:transition_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:actor, :map)
    field(:note, :string)
    field(:acknowledged_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(attrs) do
    attrs = Map.update!(attrs, :actor, &JsonDocument.wrap_value/1)

    %__MODULE__{}
    |> cast(attrs, Map.keys(attrs))
    |> OrganizationScope.put_organization_id()
    |> validate_required([
      :acknowledgement_id,
      :transition_id,
      :mission_id,
      :actor,
      :acknowledged_at
    ])
  end
end
