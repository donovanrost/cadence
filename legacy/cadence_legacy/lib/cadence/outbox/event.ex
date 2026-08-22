defmodule Cadence.Outbox.Event do
  @moduledoc """
  An outbox event represents a domain event that needs to be processed asynchronously.

  The transactional outbox pattern ensures that domain events are reliably published
  by storing them in the same transaction as the domain operation, then processing
  them asynchronously.

  ## Event Lifecycle

      ┌─────────┐   processor    ┌───────────┐   success   ┌───────────┐
      │ PENDING │ ─────────────► │ PROCESSING│ ──────────► │ PROCESSED │
      └─────────┘                └───────────┘             └───────────┘
                                      │
                                      │ failure (retries exhausted)
                                      ▼
                                ┌─────────────┐
                                │ DEAD LETTER │
                                └─────────────┘

  ## Scoping

  Events are always scoped to an organization (tenant). Mission-scoped events
  additionally have a `mission_id`. This allows:

  - Organization-wide audit log aggregation
  - Mission-specific event routing
  - Proper tenant isolation

  ## Usage with Ecto.Multi

      Multi.new()
      |> Multi.insert(:entry, queue_entry_changeset)
      |> Multi.insert(:outbox, Outbox.Event.new(%{
        organization_id: org_id,
        mission_id: mission_id,
        event_type: "command_enqueued",
        aggregate_type: "command_queue_entry",
        aggregate_id: entry.id,
        actor_id: user_id,
        actor_type: "user",
        payload: %{command_name: "PING", priority: 0}
      }))
      |> Repo.transaction()
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Recordings.Recording
  alias Cadence.Time, as: CadenceTime

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actor_types ~w(user system api_key)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          organization_id: Ecto.UUID.t(),
          mission_id: Ecto.UUID.t() | nil,
          recording_id: Ecto.UUID.t() | nil,
          event_type: String.t(),
          aggregate_type: String.t(),
          aggregate_id: Ecto.UUID.t(),
          actor_id: Ecto.UUID.t() | nil,
          actor_type: String.t() | nil,
          payload: map(),
          processed_at: DateTime.t() | nil,
          attempts: non_neg_integer(),
          last_error: String.t() | nil,
          last_attempted_at: DateTime.t() | nil,
          dead_lettered_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "outbox_events" do
    belongs_to :organization, Organization
    belongs_to :mission, Mission
    belongs_to :recording, Recording

    # Event identification
    field :event_type, :string
    field :aggregate_type, :string
    field :aggregate_id, :binary_id

    # Actor tracking for audit trail
    field :actor_id, :binary_id
    field :actor_type, :string

    # Event payload
    field :payload, :map, default: %{}

    # Processing state
    field :processed_at, :utc_datetime_usec

    # Failure tracking
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :last_attempted_at, :utc_datetime_usec
    field :dead_lettered_at, :utc_datetime_usec

    # Idempotency support for safe retries
    field :idempotency_key, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a new outbox event.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :recording_id,
      :event_type,
      :aggregate_type,
      :aggregate_id,
      :actor_id,
      :actor_type,
      :payload,
      :idempotency_key
    ])
    |> update_change(:payload, &normalize_payload/1)
    |> validate_required([
      :organization_id,
      :event_type,
      :aggregate_type,
      :aggregate_id
    ])
    |> validate_inclusion(:actor_type, @actor_types ++ [nil])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:recording_id)
    |> unique_constraint(:idempotency_key)
  end

  defp normalize_payload(nil), do: %{}
  defp normalize_payload(payload) when is_map(payload), do: deep_stringify_keys(payload)
  defp normalize_payload(payload), do: payload

  defp deep_stringify_keys(%_{} = value), do: value

  defp deep_stringify_keys(value) when is_list(value) do
    Enum.map(value, &deep_stringify_keys/1)
  end

  defp deep_stringify_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} ->
      {stringify_key(key), deep_stringify_keys(nested)}
    end)
    |> Map.new()
  end

  defp deep_stringify_keys(value), do: value

  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key) when is_integer(key), do: Integer.to_string(key)
  defp stringify_key(key) when is_float(key), do: Float.to_string(key)
  defp stringify_key(key), do: inspect(key)

  @doc """
  Creates a new outbox event struct with a changeset ready for insertion.

  This is the primary way to create outbox events in Ecto.Multi transactions.

  ## Example

      Outbox.Event.new(%{
        organization_id: org_id,
        mission_id: mission_id,
        event_type: "command_enqueued",
        aggregate_type: "command_queue_entry",
        aggregate_id: entry_id,
        actor_id: user_id,
        actor_type: "user",
        payload: %{command_name: "PING"}
      })
  """
  def new(attrs) when is_map(attrs) do
    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Changeset for marking an event as processed.
  """
  def processed_changeset(event) do
    event
    |> change()
    |> put_change(:processed_at, CadenceTime.now())
  end

  @doc """
  Changeset for recording a processing attempt failure.
  """
  def failure_changeset(event, error) do
    error_string =
      case error do
        %{message: msg} -> msg
        error when is_binary(error) -> error
        error -> inspect(error)
      end

    event
    |> change()
    |> put_change(:attempts, event.attempts + 1)
    |> put_change(:last_error, error_string)
    |> put_change(:last_attempted_at, CadenceTime.now())
  end

  @doc """
  Changeset for moving an event to the dead letter state.
  """
  def dead_letter_changeset(event, error) do
    event
    |> failure_changeset(error)
    |> put_change(:dead_lettered_at, CadenceTime.now())
  end

  @doc """
  Returns true if the event is pending processing.
  """
  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{processed_at: nil, dead_lettered_at: nil}), do: true
  def pending?(_), do: false

  @doc """
  Returns true if the event has been dead-lettered.
  """
  @spec dead_lettered?(t()) :: boolean()
  def dead_lettered?(%__MODULE__{dead_lettered_at: dead_lettered_at}) do
    not is_nil(dead_lettered_at)
  end

  @doc """
  Returns the list of valid actor types.
  """
  def valid_actor_types, do: @actor_types
end
