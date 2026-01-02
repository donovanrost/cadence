defmodule Cadence.Procedures.ProcedureReview do
  @moduledoc """
  A review decision for a procedure version.

  Unlike the old ProcedureApproval, users can submit multiple reviews
  (e.g., re-reviewing after changes). When a user submits a new review,
  their previous reviews for the same version are marked as `superseded`.

  ## Decision Types

  - `:approve` - User approves the version
  - `:request_changes` - User requests changes before approval (requires body)

  ## Review Flow

  1. Reviewer submits review with decision + optional body
  2. If request_changes, a review thread is created for discussion
  3. Author addresses feedback and resubmits
  4. On resubmit, all reviews are marked superseded (fresh review cycle)
  5. Reviewers can then approve or request more changes
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Procedures.ProcedureVersion

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @decisions [:approve, :request_changes]

  schema "procedure_reviews" do
    belongs_to :procedure_version, ProcedureVersion
    belongs_to :user, User

    field :decision, Ecto.Enum, values: @decisions
    field :body, :string
    field :superseded, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new review decision.
  """
  def changeset(review, attrs) do
    review
    |> cast(attrs, [:procedure_version_id, :user_id, :decision, :body, :superseded])
    |> validate_required([:procedure_version_id, :user_id, :decision])
    |> validate_body_for_request_changes()
    |> validate_length(:body, max: 10_000)
    |> foreign_key_constraint(:procedure_version_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for marking a review as superseded.
  """
  def supersede_changeset(review) do
    review
    |> change()
    |> put_change(:superseded, true)
  end

  defp validate_body_for_request_changes(changeset) do
    decision = get_field(changeset, :decision)
    body = get_field(changeset, :body)

    if decision == :request_changes && (is_nil(body) || String.trim(body) == "") do
      add_error(changeset, :body, "is required when requesting changes")
    else
      changeset
    end
  end

  @doc """
  Returns the list of valid decision types.
  """
  def decisions, do: @decisions
end
