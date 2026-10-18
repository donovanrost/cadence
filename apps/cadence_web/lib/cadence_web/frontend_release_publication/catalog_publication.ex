defmodule CadenceWeb.FrontendReleasePublication.CatalogPublication do
  @moduledoc "Immutable admitted signed promotion catalog."

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:publication_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "frontend_release_catalog_publications" do
    field(:sequence, :integer)
    field(:catalog_digest, :string)
    field(:signed_document_digest, :string)
    field(:signed_document_bytes, :binary)
    field(:payload_bytes, :binary)
    field(:signing_key_id, :string)
    field(:signing_role, :string)
    field(:published_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
    field(:acceptance_state, :string)
    field(:transition, :string)
    field(:identity_count, :integer)
    field(:snapshot_digest, :string)
    field(:accepted_state, :map, default: %{})
    field(:release_references, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:accepted_at, :utc_datetime_usec)

    timestamps()
  end

  @fields [
    :publication_id,
    :sequence,
    :catalog_digest,
    :signed_document_digest,
    :signed_document_bytes,
    :payload_bytes,
    :signing_key_id,
    :signing_role,
    :published_at,
    :expires_at,
    :acceptance_state,
    :transition,
    :identity_count,
    :snapshot_digest,
    :accepted_state,
    :release_references,
    :metadata,
    :accepted_at
  ]

  @required_fields @fields -- [:metadata, :transition, :identity_count, :snapshot_digest]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:acceptance_state, ["accepted"])
    |> unique_constraint(:sequence, name: :frcp_sequence_idx)
    |> unique_constraint(:catalog_digest, name: :frcp_catalog_digest_idx)
    |> unique_constraint(:signed_document_digest, name: :frcp_signed_document_digest_idx)
    |> check_constraint(:sequence, name: :frcp_sequence_check)
    |> check_constraint(:catalog_digest, name: :frcp_catalog_digest_check)
    |> check_constraint(:signed_document_digest, name: :frcp_signed_document_digest_check)
    |> check_constraint(:signing_role, name: :frcp_signing_role_check)
    |> check_constraint(:acceptance_state, name: :frcp_acceptance_state_check)
    |> check_constraint(:expires_at, name: :frcp_window_check)
    |> check_constraint(:transition, name: :frcp_v2_transition_fields_check)
  end
end
