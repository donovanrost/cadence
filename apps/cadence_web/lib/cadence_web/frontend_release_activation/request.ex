defmodule CadenceWeb.FrontendReleaseActivation.Request do
  @moduledoc "Immutable frontend release catalog activation request ledger row."

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:request_id, :string, autogenerate: false}

  schema "frontend_release_activation_requests" do
    field(:idempotency_key_digest, :string)
    field(:document_digest, :string)
    field(:outcome, :string)
    field(:response_status, :integer)
    field(:response_body, :binary)
    field(:catalog_publication_id, :string)
    field(:generation_id, :string)
    field(:publisher_identity, :string)
    field(:inserted_at, :utc_datetime_usec)
  end

  @fields [
    :request_id,
    :idempotency_key_digest,
    :document_digest,
    :outcome,
    :response_status,
    :response_body,
    :catalog_publication_id,
    :generation_id,
    :publisher_identity,
    :inserted_at
  ]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(
      @fields -- [:catalog_publication_id, :generation_id, :publisher_identity]
    )
    |> unique_constraint(:idempotency_key_digest, name: :frar_idempotency_key_idx)
    |> unique_constraint(:catalog_publication_id, name: :frar_catalog_publication_idx)
    |> unique_constraint(:generation_id, name: :frar_generation_idx)
    |> check_constraint(:idempotency_key_digest, name: :frar_idempotency_key_digest_check)
    |> check_constraint(:document_digest, name: :frar_document_digest_check)
    |> check_constraint(:outcome, name: :frar_outcome_check)
    |> check_constraint(:response_status, name: :frar_response_status_check)
    |> check_constraint(:response_body, name: :frar_response_body_check)
    |> check_constraint(:outcome, name: :frar_outcome_response_check)
    |> check_constraint(:publisher_identity, name: :frar_publisher_identity_check)
  end
end
