defmodule Cadence.MissionModels.QualificationCaseRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument

  @primary_key {:qualification_case_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "mission_model_qualification_cases" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:name, :string)
    field(:status, Ecto.Enum, values: [:approved, :retired])
    field(:input_term, :binary)
    field(:expected_result_sha256, :string)
    field(:approved_by, :map)
    field(:approved_at, :utc_datetime_usec)
    field(:metadata, :map)

    timestamps()
  end

  def changeset(attrs) do
    attrs =
      attrs
      |> Map.update!(:approved_by, &JsonDocument.wrap_value/1)
      |> Map.update!(:metadata, &JsonDocument.wrap_value/1)

    %__MODULE__{}
    |> cast(attrs, Map.keys(attrs))
    |> validate_required(Map.keys(attrs) -- [:expected_result_sha256])
  end
end
