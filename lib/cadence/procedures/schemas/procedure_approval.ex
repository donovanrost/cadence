defmodule Cadence.Procedures.ProcedureApproval do
  @moduledoc """
  A record of an approval or rejection decision for a procedure version.

  Each user can only submit one decision per version. The decision can be
  either `:approved` or `:rejected`, with an optional comment explaining
  the reasoning.

  ## Decision Types

  - `:approved` - User approves the version for use
  - `:rejected` - User rejects the version, returning it to draft status
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Procedures.ProcedureVersion
  alias Cadence.Accounts.User

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @decisions [:approved, :rejected]

  schema "procedure_approvals" do
    belongs_to :procedure_version, ProcedureVersion
    belongs_to :user, User

    field :decision, Ecto.Enum, values: @decisions
    field :comment, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new approval decision.
  """
  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [:procedure_version_id, :user_id, :decision, :comment])
    |> validate_required([:procedure_version_id, :user_id, :decision])
    |> validate_length(:comment, max: 2000)
    |> foreign_key_constraint(:procedure_version_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:procedure_version_id, :user_id],
      message: "you have already submitted a decision for this version"
    )
  end

  @doc """
  Returns the list of valid decision types.
  """
  def decisions, do: @decisions
end
