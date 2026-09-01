defmodule CadenceWeb.FrontendReleaseActivation.CatalogGeneration do
  @moduledoc "Immutable v2 catalog generation and predecessor provenance."

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:generation_id, :string, autogenerate: false}

  schema "frontend_release_catalog_generations" do
    field(:catalog_publication_id, :string)
    field(:sequence, :integer)
    field(:identity_count, :integer)
    field(:predecessor_kind, :string)
    field(:predecessor_catalog_publication_id, :string)
    field(:inserted_at, :utc_datetime_usec)
  end

  @fields [
    :generation_id,
    :catalog_publication_id,
    :sequence,
    :identity_count,
    :predecessor_kind,
    :predecessor_catalog_publication_id,
    :inserted_at
  ]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@fields -- [:predecessor_catalog_publication_id])
    |> unique_constraint(:catalog_publication_id, name: :frcg_catalog_publication_idx)
    |> unique_constraint(:sequence, name: :frcg_sequence_idx)
    |> foreign_key_constraint(:catalog_publication_id)
    |> foreign_key_constraint(:predecessor_catalog_publication_id)
    |> check_constraint(:sequence, name: :frcg_sequence_check)
    |> check_constraint(:identity_count, name: :frcg_identity_count_check)
    |> check_constraint(:predecessor_kind, name: :frcg_predecessor_check)
  end
end
