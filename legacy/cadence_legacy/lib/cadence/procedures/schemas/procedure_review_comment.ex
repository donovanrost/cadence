defmodule Cadence.Procedures.ProcedureReviewComment do
  @moduledoc """
  A comment within a review thread.

  Comments are the building blocks of threaded discussions on procedure versions.
  They can be added by any user with access to the procedure.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Procedures.ProcedureReviewThread

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "procedure_review_comments" do
    belongs_to :thread, ProcedureReviewThread
    belongs_to :user, User

    field :body, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new comment.
  """
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:thread_id, :user_id, :body])
    |> validate_required([:thread_id, :user_id, :body])
    |> validate_length(:body, min: 1, max: 10_000)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:user_id)
  end
end
