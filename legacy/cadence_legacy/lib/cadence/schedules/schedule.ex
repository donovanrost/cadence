defmodule Cadence.Schedules.Schedule do
  @moduledoc """
  Schema for scheduled procedure executions.

  Schedules define when procedures should be automatically executed.
  They support cron expressions for recurring schedules or one-time
  execution at a specific datetime.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Oban.Plugins.Cron

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "schedules" do
    field :name, :string
    field :description, :string
    field :enabled, :boolean, default: true

    # Schedule type and timing
    field :schedule_type, Ecto.Enum, values: [:cron, :once], default: :cron
    field :cron_expression, :string
    field :scheduled_at, :utc_datetime
    field :timezone, :string, default: "UTC"

    # Execution configuration
    field :parameters, :map, default: %{}

    # Tracking
    field :last_run_at, :utc_datetime
    field :next_run_at, :utc_datetime
    field :run_count, :integer, default: 0

    # Relationships
    belongs_to :procedure, Cadence.Procedures.Procedure
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :target, Cadence.Targets.Target

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [
      :name,
      :description,
      :enabled,
      :schedule_type,
      :cron_expression,
      :scheduled_at,
      :timezone,
      :parameters,
      :procedure_id,
      :organization_id,
      :mission_id,
      :target_id
    ])
    |> validate_required([:name, :schedule_type, :procedure_id, :organization_id])
    |> validate_schedule_timing()
    |> validate_cron_expression()
    |> foreign_key_constraint(:procedure_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:target_id)
  end

  @doc false
  def run_changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:last_run_at, :next_run_at, :run_count])
  end

  defp validate_schedule_timing(changeset) do
    schedule_type = get_field(changeset, :schedule_type)

    case schedule_type do
      :cron ->
        if get_field(changeset, :cron_expression) in [nil, ""] do
          add_error(changeset, :cron_expression, "is required for cron schedules")
        else
          changeset
        end

      :once ->
        if get_field(changeset, :scheduled_at) == nil do
          add_error(changeset, :scheduled_at, "is required for one-time schedules")
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  defp validate_cron_expression(changeset) do
    cron = get_field(changeset, :cron_expression)

    if cron && cron != "" do
      case Cron.parse(cron) do
        {:ok, _} -> changeset
        {:error, _} -> add_error(changeset, :cron_expression, "is not a valid cron expression")
      end
    else
      changeset
    end
  end
end
