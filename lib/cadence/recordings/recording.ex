defmodule Cadence.Recordings.Recording do
  @moduledoc """
  Pure index table for the event sourcing system.

  Recordings link events (recordables) to aggregates and buckets without duplicating
  any data from the recordable. This provides a unified timeline view across all
  event types while keeping event-specific data in their own tables.

  ## Fields

  - `aggregate_type` - The entity type: "Command", "Alarm", "Procedure", etc.
  - `aggregate_id` - The specific entity instance this event belongs to
  - `recordable_type` - The event type: "CommandDispatched", "AlarmTriggered", etc.
  - `recordable_id` - Foreign key to the specific recordable table
  - `parent_id` - Links to the parent recording for causality chains
  - `root_id` - Denormalized root of the causality tree for fast queries
  - `timestamp` - When the event occurred (not when it was recorded)

  ## Example

      # A command dispatch creates a recording pointing to CommandDispatched
      %Recording{
        aggregate_type: "Command",
        aggregate_id: "cmd-123",
        recordable_type: "CommandDispatched",
        recordable_id: "rec-456",
        timestamp: ~U[2025-01-15 14:30:00Z]
      }

      # Later, CommandSent creates another recording with parent_id
      %Recording{
        aggregate_type: "Command",
        aggregate_id: "cmd-123",
        recordable_type: "CommandSent",
        recordable_id: "rec-789",
        parent_id: "rec-456",
        root_id: "cmd-123",
        timestamp: ~U[2025-01-15 14:30:01Z]
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Buckets.Bucket
  alias Cadence.Organizations.Organization

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          organization_id: Ecto.UUID.t(),
          bucket_id: Ecto.UUID.t() | nil,
          aggregate_type: String.t(),
          aggregate_id: Ecto.UUID.t(),
          recordable_type: String.t(),
          recordable_id: Ecto.UUID.t(),
          parent_id: Ecto.UUID.t() | nil,
          root_id: Ecto.UUID.t() | nil,
          actor_id: Ecto.UUID.t() | nil,
          actor_type: String.t(),
          timestamp: DateTime.t(),
          inserted_at: DateTime.t()
        }

  schema "recordings" do
    field :aggregate_type, :string
    field :aggregate_id, :binary_id
    field :recordable_type, :string
    field :recordable_id, :binary_id
    field :parent_id, :binary_id
    field :root_id, :binary_id
    field :actor_type, :string, default: "user"
    field :timestamp, :utc_datetime_usec

    belongs_to :organization, Organization
    belongs_to :bucket, Bucket
    belongs_to :actor, User, foreign_key: :actor_id
    belongs_to :parent, __MODULE__, foreign_key: :parent_id, define_field: false

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [
    :organization_id,
    :aggregate_type,
    :aggregate_id,
    :recordable_type,
    :recordable_id,
    :timestamp
  ]

  @optional_fields [
    :bucket_id,
    :parent_id,
    :root_id,
    :actor_id,
    :actor_type
  ]

  @doc """
  Creates a changeset for a new recording.
  """
  def changeset(recording, attrs) do
    recording
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> maybe_set_root_id()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:bucket_id)
    |> foreign_key_constraint(:actor_id)
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint([:recordable_type, :recordable_id])
  end

  defp maybe_set_root_id(changeset) do
    root_id = get_field(changeset, :root_id)
    parent_id = get_field(changeset, :parent_id)
    aggregate_id = get_field(changeset, :aggregate_id)

    cond do
      root_id != nil ->
        changeset

      parent_id != nil ->
        # If there's a parent, root_id should be set explicitly by caller
        # or we can look it up (but that requires a query)
        changeset

      aggregate_id != nil ->
        # No parent means this is the root
        put_change(changeset, :root_id, aggregate_id)

      true ->
        changeset
    end
  end
end
