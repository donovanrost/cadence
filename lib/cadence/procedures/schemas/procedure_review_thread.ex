defmodule Cadence.Procedures.ProcedureReviewThread do
  @moduledoc """
  A discussion thread on a procedure version review.

  Threads are created when:
  1. A reviewer requests changes (linked to their review)
  2. Any user starts a general discussion (not linked to a review)

  ## Thread Lifecycle

  1. Created as `:open`
  2. Users add comments to the thread
  3. Thread can be resolved by author or reviewer
  4. For resubmission, all blocking threads (from request_changes) must be resolved
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Procedures.{ProcedureReview, ProcedureReviewComment, ProcedureVersion}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:open, :resolved]
  @anchor_types [:version, :section, :step, :block]

  schema "procedure_review_threads" do
    belongs_to :procedure_version, ProcedureVersion
    belongs_to :author, User
    belongs_to :review, ProcedureReview
    belongs_to :resolved_by, User

    field :status, Ecto.Enum, values: @statuses, default: :open
    field :resolved_at, :utc_datetime_usec

    # Anchor fields for attaching threads to specific content
    # :version = general thread on the version (default, backward compatible)
    # :section = thread on a specific section
    # :step = thread on a specific step
    # :block = thread on a specific block
    field :anchor_type, Ecto.Enum, values: @anchor_types, default: :version
    field :anchor_id, :binary_id

    has_many :comments, ProcedureReviewComment, foreign_key: :thread_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new thread.
  """
  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [
      :procedure_version_id,
      :author_id,
      :review_id,
      :status,
      :anchor_type,
      :anchor_id
    ])
    |> validate_required([:procedure_version_id, :author_id])
    |> validate_anchor()
    |> foreign_key_constraint(:procedure_version_id)
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:review_id)
  end

  # Validates that anchor_id is provided when anchor_type is not :version
  defp validate_anchor(changeset) do
    anchor_type = get_field(changeset, :anchor_type)
    anchor_id = get_field(changeset, :anchor_id)

    cond do
      anchor_type == :version and not is_nil(anchor_id) ->
        add_error(changeset, :anchor_id, "must be nil for version-level threads")

      anchor_type != :version and is_nil(anchor_id) ->
        add_error(changeset, :anchor_id, "is required for #{anchor_type}-level threads")

      true ->
        changeset
    end
  end

  @doc """
  Changeset for resolving a thread.
  """
  def resolve_changeset(thread, user_id) do
    thread
    |> change()
    |> put_change(:status, :resolved)
    |> put_change(:resolved_by_id, user_id)
    |> put_change(:resolved_at, DateTime.utc_now())
  end

  @doc """
  Changeset for reopening a resolved thread.
  """
  def reopen_changeset(thread) do
    thread
    |> change()
    |> put_change(:status, :open)
    |> put_change(:resolved_by_id, nil)
    |> put_change(:resolved_at, nil)
  end

  @doc """
  Returns the list of valid status values.
  """
  def statuses, do: @statuses

  @doc """
  Returns true if the thread is blocking (created from a request_changes review).
  """
  def blocking?(%__MODULE__{review_id: review_id}), do: not is_nil(review_id)

  @doc """
  Returns the list of valid anchor type values.
  """
  def anchor_types, do: @anchor_types

  @doc """
  Returns true if the thread is anchored to specific content (not version-level).
  """
  def anchored?(%__MODULE__{anchor_type: :version}), do: false
  def anchored?(%__MODULE__{}), do: true
end
