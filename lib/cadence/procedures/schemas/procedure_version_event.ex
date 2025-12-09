defmodule Cadence.Procedures.ProcedureVersionEvent do
  @moduledoc """
  Audit log entry for procedure version state changes.

  Every change to a procedure version is recorded as an event, providing
  a complete audit trail of the version's lifecycle.

  ## Event Types

  - `:created` - Version was created
  - `:submitted` - Version was submitted for review
  - `:withdrawn` - Submission was withdrawn by the author
  - `:approval_added` - An approval or rejection was added
  - `:approved` - Version reached required approvals and was approved
  - `:rejected` - Version was rejected and returned to draft
  - `:deprecated` - Version was deprecated

  ## State Snapshots

  `previous_state` and `new_state` capture the version's state before and
  after the event, enabling full reconstruction of version history.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Procedures.ProcedureVersion
  alias Cadence.Accounts.User

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types [
    :created,
    :submitted,
    :withdrawn,
    :approval_added,
    :approved,
    :rejected,
    :deprecated
  ]

  schema "procedure_version_events" do
    belongs_to :procedure_version, ProcedureVersion
    belongs_to :user, User

    field :event_type, Ecto.Enum, values: @event_types
    field :previous_state, :map
    field :new_state, :map
    field :note, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new version event.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :procedure_version_id,
      :user_id,
      :event_type,
      :previous_state,
      :new_state,
      :note,
      :metadata
    ])
    |> validate_required([:procedure_version_id, :event_type])
    |> validate_length(:note, max: 2000)
    |> foreign_key_constraint(:procedure_version_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates event attributes for a version submission.
  """
  @spec submitted(ProcedureVersion.t(), String.t()) :: map()
  def submitted(%ProcedureVersion{} = version, user_id) do
    %{
      procedure_version_id: version.id,
      user_id: user_id,
      event_type: :submitted,
      previous_state: %{"status" => "draft"},
      new_state: %{"status" => "in_review"}
    }
  end

  @doc """
  Creates event attributes for a version withdrawal.
  """
  @spec withdrawn(ProcedureVersion.t(), String.t()) :: map()
  def withdrawn(%ProcedureVersion{} = version, user_id) do
    %{
      procedure_version_id: version.id,
      user_id: user_id,
      event_type: :withdrawn,
      previous_state: %{"status" => "in_review"},
      new_state: %{"status" => "draft"}
    }
  end

  @doc """
  Creates event attributes for an approval or rejection being added.
  """
  @spec approval_added(ProcedureVersion.t(), String.t(), atom(), String.t() | nil) :: map()
  def approval_added(%ProcedureVersion{} = version, user_id, decision, comment) do
    %{
      procedure_version_id: version.id,
      user_id: user_id,
      event_type: :approval_added,
      note: comment,
      metadata: %{"decision" => to_string(decision)}
    }
  end

  @doc """
  Creates event attributes for a version being approved.
  """
  @spec approved(ProcedureVersion.t(), String.t()) :: map()
  def approved(%ProcedureVersion{} = version, user_id) do
    %{
      procedure_version_id: version.id,
      user_id: user_id,
      event_type: :approved,
      previous_state: %{"status" => "in_review"},
      new_state: %{"status" => "approved"}
    }
  end

  @doc """
  Creates event attributes for a version being rejected.
  """
  @spec rejected(ProcedureVersion.t(), String.t(), String.t() | nil) :: map()
  def rejected(%ProcedureVersion{} = version, user_id, reason) do
    %{
      procedure_version_id: version.id,
      user_id: user_id,
      event_type: :rejected,
      previous_state: %{"status" => "in_review"},
      new_state: %{"status" => "draft"},
      note: reason
    }
  end

  @doc """
  Creates event attributes for a version being deprecated.
  """
  @spec deprecated(ProcedureVersion.t(), String.t()) :: map()
  def deprecated(%ProcedureVersion{} = version, user_id) do
    %{
      procedure_version_id: version.id,
      user_id: user_id,
      event_type: :deprecated,
      previous_state: %{"status" => to_string(version.status)},
      new_state: %{"status" => "deprecated"}
    }
  end

  @doc """
  Returns the list of valid event types.
  """
  def event_types, do: @event_types
end
