defmodule Cadence.Dashboards.DashboardDeployment do
  @moduledoc "Immutable record of a governed dashboard artifact prepared for deployment."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dashboard_deployment_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]
  @type t :: %__MODULE__{}

  schema "dashboard_deployments" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:dashboard_id, :string)
    field(:dashboard_version, :integer)
    field(:environment, :string)
    field(:artifact_digest, :string)
    field(:status, :string)
    field(:created_by, :string)
    timestamps()
  end

  def changeset(deployment, attrs) do
    deployment
    |> cast(attrs, [
      :dashboard_deployment_id,
      :organization_id,
      :mission_id,
      :dashboard_id,
      :dashboard_version,
      :environment,
      :artifact_digest,
      :status,
      :created_by
    ])
    |> validate_required([
      :dashboard_deployment_id,
      :mission_id,
      :dashboard_id,
      :dashboard_version,
      :environment,
      :artifact_digest,
      :status
    ])
    |> validate_inclusion(:status, ["validated", "exported"])
  end
end
