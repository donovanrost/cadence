defmodule CadenceWeb.FrontendReleasePublication.ReleasePublication do
  @moduledoc "Immutable admitted signed frontend release."

  use Ecto.Schema

  import Ecto.Changeset

  alias CadenceWeb.FrontendReleasePublication.ReleaseArtifact

  @primary_key {:publication_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "frontend_release_publications" do
    field(:release_id, :string)
    field(:application_id, :string)
    field(:application_version, :integer)
    field(:package_id, :string)
    field(:package_version, :integer)
    field(:surface_id, :string)
    field(:surface_version, :integer)
    field(:remote_name, :string)
    field(:exposed_module, :string)
    field(:artifact_base_url, :string)
    field(:payload_digest, :string)
    field(:signed_document_digest, :string)
    field(:signed_document_bytes, :binary)
    field(:payload_bytes, :binary)
    field(:signing_key_id, :string)
    field(:signing_role, :string)
    field(:provenance, :map, default: %{})
    field(:released_at, :utc_datetime_usec)
    field(:artifact_count, :integer)
    field(:acceptance_state, :string)
    field(:accepted_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    has_many(:artifacts, ReleaseArtifact,
      foreign_key: :release_publication_id,
      references: :publication_id
    )

    timestamps()
  end

  @fields [
    :publication_id,
    :release_id,
    :application_id,
    :application_version,
    :package_id,
    :package_version,
    :surface_id,
    :surface_version,
    :remote_name,
    :exposed_module,
    :artifact_base_url,
    :payload_digest,
    :signed_document_digest,
    :signed_document_bytes,
    :payload_bytes,
    :signing_key_id,
    :signing_role,
    :provenance,
    :released_at,
    :artifact_count,
    :acceptance_state,
    :accepted_at,
    :metadata
  ]

  @required_fields @fields -- [:metadata]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:acceptance_state, ["accepted"])
    |> unique_constraint(:release_id, name: :frontend_release_publications_release_idx)
    |> unique_constraint(:payload_digest, name: :frontend_release_publications_payload_digest_idx)
    |> unique_constraint(:signed_document_digest,
      name: :frontend_release_publications_signed_document_digest_idx
    )
    |> check_constraint(:release_id, name: :frontend_release_publications_release_id_check)
    |> check_constraint(:payload_digest,
      name: :frontend_release_publications_payload_digest_check
    )
    |> check_constraint(:signed_document_digest,
      name: :frontend_release_publications_signed_document_digest_check
    )
    |> check_constraint(:artifact_count,
      name: :frontend_release_publications_artifact_count_check
    )
    |> check_constraint(:signing_role, name: :frontend_release_publications_signing_role_check)
    |> check_constraint(:acceptance_state,
      name: :frontend_release_publications_acceptance_state_check
    )
  end
end
