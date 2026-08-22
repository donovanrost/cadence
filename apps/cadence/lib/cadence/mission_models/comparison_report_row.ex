defmodule Cadence.MissionModels.ComparisonReportRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument

  @primary_key {:comparison_report_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_model_comparison_reports" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:candidate_revision_id, :string)
    field(:baseline_revision_id, :string)
    field(:binding_set_id, :string)
    field(:binding_set_version, :integer)
    field(:status, Ecto.Enum, values: [:passed, :failed])
    field(:risk, Ecto.Enum, values: [:low, :medium, :high])
    field(:report_sha256, :string)
    field(:report, :map)

    timestamps()
  end

  def changeset(attrs) do
    attrs = Map.update!(attrs, :report, &JsonDocument.wrap_value/1)

    %__MODULE__{}
    |> cast(attrs, Map.keys(attrs))
    |> validate_required(Map.keys(attrs) -- [:baseline_revision_id])
    |> unique_constraint(
      [
        :organization_id,
        :mission_id,
        :candidate_revision_id,
        :binding_set_id,
        :binding_set_version,
        :report_sha256
      ],
      name: :mission_model_comparison_reports_identity_idx
    )
  end
end
