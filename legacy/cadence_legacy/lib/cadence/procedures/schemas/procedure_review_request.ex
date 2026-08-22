defmodule Cadence.Procedures.ProcedureReviewRequest do
  @moduledoc """
  A request for a specific user to review a procedure version.

  When an author submits a version for review, they can optionally request
  specific users to review it. This creates review requests that appear in
  those users' review inboxes.

  ## Status Values

  - `:pending` - Waiting for the reviewer to respond
  - `:completed` - Reviewer has submitted a review
  - `:cancelled` - Request was cancelled (e.g., version closed or reviewer unavailable)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Procedures.ProcedureVersion
  alias Cadence.Time, as: CadenceTime

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:pending, :completed, :cancelled]

  schema "procedure_review_requests" do
    belongs_to :procedure_version, ProcedureVersion
    belongs_to :requester, User
    belongs_to :reviewer, User

    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :message, :string
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new review request.
  """
  def changeset(request, attrs) do
    request
    |> cast(attrs, [:procedure_version_id, :requester_id, :reviewer_id, :message, :status])
    |> validate_required([:procedure_version_id, :requester_id, :reviewer_id])
    |> validate_length(:message, max: 1000)
    |> foreign_key_constraint(:procedure_version_id)
    |> foreign_key_constraint(:requester_id)
    |> foreign_key_constraint(:reviewer_id)
  end

  @doc """
  Changeset for completing a review request.
  """
  def complete_changeset(request) do
    request
    |> change()
    |> put_change(:status, :completed)
    |> put_change(:completed_at, CadenceTime.now())
  end

  @doc """
  Changeset for cancelling a review request.
  """
  def cancel_changeset(request) do
    request
    |> change()
    |> put_change(:status, :cancelled)
  end

  @doc """
  Returns the list of valid status values.
  """
  def statuses, do: @statuses
end
