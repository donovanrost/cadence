defmodule CadenceWeb.FrontendReleaseActivation.CatalogBinding do
  @moduledoc "Immutable generation-to-release identity binding."

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  schema "frontend_release_catalog_bindings" do
    field(:generation_id, :string, primary_key: true)
    field(:application_id, :string, primary_key: true)
    field(:application_version, :integer, primary_key: true)
    field(:package_id, :string, primary_key: true)
    field(:package_version, :integer, primary_key: true)
    field(:surface_id, :string, primary_key: true)
    field(:surface_version, :integer, primary_key: true)
    field(:current_publication_id, :string)
    field(:current_release_id, :string)
    field(:previous_publication_id, :string)
    field(:previous_release_id, :string)
    field(:inserted_at, :utc_datetime_usec)
  end

  @fields [
    :generation_id,
    :application_id,
    :application_version,
    :package_id,
    :package_version,
    :surface_id,
    :surface_version,
    :current_publication_id,
    :current_release_id,
    :previous_publication_id,
    :previous_release_id,
    :inserted_at
  ]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@fields -- [:previous_publication_id, :previous_release_id])
    |> unique_constraint(
      [
        :generation_id,
        :application_id,
        :application_version,
        :package_id,
        :package_version,
        :surface_id,
        :surface_version
      ],
      name: :frcb_identity_pkey
    )
    |> foreign_key_constraint(:generation_id)
    |> foreign_key_constraint(:current_publication_id, name: :frcb_current_release_fk)
    |> foreign_key_constraint(:previous_publication_id, name: :frcb_previous_release_fk)
    |> check_constraint(:current_publication_id, name: :frcb_current_pair_check)
    |> check_constraint(:previous_publication_id, name: :frcb_previous_pair_check)
    |> check_constraint(:application_version, name: :frcb_identity_version_check)
  end
end
