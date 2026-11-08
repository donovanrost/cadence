defmodule Cadence.SemanticRuntime.CommitRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:commit_sequence, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "semantic_runtime_commits" do
    field(:commit_id, :string)
    field(:organization_scope_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:partition_id, :string)
    field(:mission_model_revision_id, :string)
    field(:runtime_basis_sha256, :string)
    field(:input_term, :binary)
    field(:result_term, :binary)
    field(:state_term, :binary)
    field(:ownership_epoch, :integer)
    field(:predecessor_sequence, :integer)
    field(:projected_at, :utc_datetime_usec)
    field(:input_kind, :string)
    field(:timer_key, :string)
    field(:timer_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(attrs) do
    attrs =
      Map.put(
        attrs,
        :organization_scope_id,
        Map.get(attrs, :organization_id) || "__unscoped_organization__"
      )

    %__MODULE__{}
    |> change(attrs)
    |> validate_required(Map.keys(attrs) -- [:organization_id, :timer_key, :timer_at])
    |> unique_constraint(
      [:organization_scope_id, :mission_id, :partition_id, :runtime_basis_sha256, :commit_id],
      name: :semantic_runtime_commits_identity_idx
    )
  end
end
