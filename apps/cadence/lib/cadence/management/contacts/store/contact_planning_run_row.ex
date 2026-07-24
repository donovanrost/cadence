defmodule Cadence.Management.Contacts.Store.ContactPlanningRunRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactPlanningRun
  alias Cadence.Persistence.JsonDocument

  @primary_key {:contact_planning_run_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "contact_planning_runs" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:contact_requirement_id, :string)
    field(:contact_requirement_version, :integer)
    field(:lifecycle_state, :string)
    field(:requested_by, :string)
    field(:started_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)
    field(:summary_document, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :contact_planning_run_id,
    :organization_id,
    :mission_id,
    :contact_requirement_id,
    :contact_requirement_version,
    :lifecycle_state,
    :requested_by,
    :started_at,
    :summary_document
  ]

  @spec changeset(ContactPlanningRun.t()) :: Ecto.Changeset.t()
  def changeset(%ContactPlanningRun{} = run) do
    %__MODULE__{}
    |> cast(domain_attrs(run), fields())
    |> validate_required(@required_fields)
    |> validate_number(:contact_requirement_version, greater_than: 0)
    |> validate_inclusion(:lifecycle_state, ~w(running completed partial failed))
    |> foreign_key_constraint(:contact_requirement_version,
      name: :contact_planning_runs_requirement_version_fk
    )
  end

  @spec completion_changeset(struct(), map()) :: Ecto.Changeset.t()
  def completion_changeset(%__MODULE__{} = row, attrs) do
    row
    |> cast(attrs, [:lifecycle_state, :completed_at, :summary_document])
    |> validate_required([:lifecycle_state, :completed_at, :summary_document])
    |> validate_inclusion(:lifecycle_state, ~w(completed partial failed))
  end

  @spec to_domain(struct()) :: ContactPlanningRun.t()
  def to_domain(%__MODULE__{} = row) do
    ContactPlanningRun.new(%{
      contact_planning_run_id: row.contact_planning_run_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      contact_requirement_id: row.contact_requirement_id,
      contact_requirement_version: row.contact_requirement_version,
      lifecycle_state: row.lifecycle_state,
      requested_by: row.requested_by,
      started_at: row.started_at,
      completed_at: row.completed_at,
      summary_document: JsonDocument.unwrap_value(row.summary_document),
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp domain_attrs(run) do
    %{
      contact_planning_run_id: run.contact_planning_run_id,
      organization_id: run.organization_id,
      mission_id: run.mission_id,
      contact_requirement_id: run.contact_requirement_id,
      contact_requirement_version: run.contact_requirement_version,
      lifecycle_state: Atom.to_string(run.lifecycle_state),
      requested_by: run.requested_by,
      started_at: run.started_at,
      completed_at: run.completed_at,
      summary_document: JsonDocument.wrap_value(run.summary_document)
    }
  end

  defp fields, do: @required_fields ++ [:completed_at]
end
