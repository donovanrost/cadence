defprotocol Cadence.Buckets.Bucketable do
  @moduledoc """
  Protocol for entities that can be organized into buckets.

  Buckets provide hierarchical organization, settings inheritance, permission
  scoping, and recording context for domain entities like Missions, Shifts,
  Targets, and TargetGroups.

  This protocol allows domain entities to declare their bucket properties
  while keeping bucket infrastructure concerns separate from domain logic.

  ## Example Implementation

      defimpl Cadence.Buckets.Bucketable, for: Cadence.Shifts.Shift do
        def bucket_type(_), do: :shift
        def bucketable_type(_), do: :shift
        def bucket_name(shift), do: shift.name
        def bucket_started_at(shift), do: shift.scheduled_start
        def bucket_ended_at(shift), do: shift.scheduled_end
        def parent_bucket_id(_), do: nil
        def bucket_metadata(_), do: %{}
      end

  ## Design Notes

  - Types are atoms (`:shift`, `:mission`) - infrastructure converts to strings for database
  - `bucketable_type/1` is a stable identifier decoupled from module name to avoid
    database migrations if a struct is renamed
  - Implementations live alongside domain entities, not centralized
  """

  @doc """
  Returns the bucket type atom for this entity.

  Examples: `:mission`, `:shift`, `:target`, `:target_group`
  """
  @spec bucket_type(t) :: atom()
  def bucket_type(bucketable)

  @doc """
  Returns the bucketable type atom - a stable identifier for database storage.

  This is intentionally explicit rather than derived from the module name
  to avoid requiring database migrations if a struct is renamed.

  Examples: `:mission`, `:shift`, `:target`, `:target_group`
  """
  @spec bucketable_type(t) :: atom()
  def bucketable_type(bucketable)

  @doc """
  Returns a human-readable name for the bucket.
  """
  @spec bucket_name(t) :: String.t() | nil
  def bucket_name(bucketable)

  @doc """
  Returns when the bucket context started, if applicable.

  For time-bounded buckets like Shifts, this would be the scheduled start time.
  For persistent buckets like Missions or Targets, this may be nil.
  """
  @spec bucket_started_at(t) :: DateTime.t() | nil
  def bucket_started_at(bucketable)

  @doc """
  Returns when the bucket context ended, if applicable.

  For time-bounded buckets like Shifts, this would be the scheduled end time.
  For persistent buckets like Missions or Targets, this may be nil.
  """
  @spec bucket_ended_at(t) :: DateTime.t() | nil
  def bucket_ended_at(bucketable)

  @doc """
  Returns the parent bucket ID for hierarchical organization.

  Returns nil for root buckets (e.g., Organization-level buckets).

  The bucket hierarchy typically follows:
  - Organization → Mission → TargetGroup → Target
  - Organization → Mission → Shift (standalone)
  """
  @spec parent_bucket_id(t) :: Ecto.UUID.t() | nil
  def parent_bucket_id(bucketable)

  @doc """
  Returns custom metadata for the bucket.

  Allows storing entity-specific data without schema changes.
  """
  @spec bucket_metadata(t) :: map()
  def bucket_metadata(bucketable)
end
