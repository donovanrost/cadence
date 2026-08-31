defmodule CadenceWeb.FrontendReleasePublication.ReleaseArtifact do
  @moduledoc "Immutable declared artifact metadata for one admitted release."

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:artifact_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "frontend_release_artifacts" do
    field(:release_publication_id, :string)
    field(:release_id, :string)
    field(:path, :string)
    field(:sha256, :string)
    field(:size, :integer)
    field(:media_type, :string)
    field(:object_key, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @fields [
    :artifact_id,
    :release_publication_id,
    :release_id,
    :path,
    :sha256,
    :size,
    :media_type,
    :object_key,
    :metadata
  ]

  @required_fields @fields -- [:metadata]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:release_publication_id, :path],
      name: :frontend_release_artifacts_publication_path_idx
    )
    |> check_constraint(:sha256, name: :frontend_release_artifacts_sha256_check)
    |> check_constraint(:size, name: :frontend_release_artifacts_size_check)
    |> check_constraint(:object_key, name: :frontend_release_artifacts_object_key_check)
  end
end
