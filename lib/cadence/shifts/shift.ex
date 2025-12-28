defmodule Cadence.Shifts.Shift do
  @moduledoc """
  Operator shift management.

  Shifts represent scheduled work periods for operators. Each shift
  automatically creates a corresponding bucket for access control
  and recording scoping.

  ## Status

  - `scheduled` - Shift is planned but not started
  - `active` - Shift is currently in progress
  - `completed` - Shift has ended normally
  - `cancelled` - Shift was cancelled

  ## Example

      %Shift{
        name: "Alpha",
        shift_type: "operational",
        scheduled_start: ~U[2025-01-15 08:00:00Z],
        scheduled_end: ~U[2025-01-15 16:00:00Z],
        status: "scheduled"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ["scheduled", "active", "completed", "cancelled"]
  @shift_types ["operational", "maintenance", "training", "standby"]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          organization_id: Ecto.UUID.t(),
          mission_id: Ecto.UUID.t(),
          name: String.t() | nil,
          shift_type: String.t() | nil,
          scheduled_start: DateTime.t(),
          scheduled_end: DateTime.t(),
          actual_start: DateTime.t() | nil,
          actual_end: DateTime.t() | nil,
          status: String.t(),
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "shifts" do
    field :name, :string
    field :shift_type, :string
    field :scheduled_start, :utc_datetime_usec
    field :scheduled_end, :utc_datetime_usec
    field :actual_start, :utc_datetime_usec
    field :actual_end, :utc_datetime_usec
    field :status, :string, default: "scheduled"
    field :metadata, :map, default: %{}

    belongs_to :organization, Organization
    belongs_to :mission, Mission

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:organization_id, :mission_id, :scheduled_start, :scheduled_end]
  @optional_fields [:name, :shift_type, :actual_start, :actual_end, :status, :metadata]

  def changeset(shift, attrs) do
    shift
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:shift_type, @shift_types)
    |> validate_schedule()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
  end

  defp validate_schedule(changeset) do
    start_time = get_field(changeset, :scheduled_start)
    end_time = get_field(changeset, :scheduled_end)

    if start_time && end_time && DateTime.compare(start_time, end_time) != :lt do
      add_error(changeset, :scheduled_end, "must be after scheduled start")
    else
      changeset
    end
  end

  def statuses, do: @statuses
  def shift_types, do: @shift_types
end

defimpl Cadence.Buckets.Bucketable, for: Cadence.Shifts.Shift do
  @moduledoc false

  def bucket_type(_), do: :shift
  def bucketable_type(_), do: :shift
  def bucket_name(shift), do: shift.name
  def bucket_started_at(shift), do: shift.scheduled_start
  def bucket_ended_at(shift), do: shift.scheduled_end
  def parent_bucket_id(_), do: nil
  def bucket_metadata(shift), do: shift.metadata || %{}
end
