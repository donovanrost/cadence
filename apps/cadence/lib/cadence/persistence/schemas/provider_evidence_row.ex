defmodule Cadence.Persistence.Schemas.ProviderEvidenceRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.GroundNetworks.ProviderEvidence
  alias Cadence.Persistence.JsonDocument

  @primary_key {:provider_evidence_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "provider_evidence" do
    field(:organization_id, :string)
    field(:provider_account_id, :string)
    field(:storage_kind, :string)
    field(:schema_type, :string)
    field(:media_type, :string)
    field(:captured_at, :utc_datetime_usec)
    field(:byte_count, :integer)
    field(:content_sha256, :string)
    field(:document, :map)
    field(:external_object_ref, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @fields [
    :provider_evidence_id,
    :organization_id,
    :provider_account_id,
    :storage_kind,
    :schema_type,
    :media_type,
    :captured_at,
    :byte_count,
    :content_sha256,
    :document,
    :external_object_ref,
    :metadata
  ]

  @spec changeset(ProviderEvidence.t()) :: Ecto.Changeset.t()
  def changeset(%ProviderEvidence{} = evidence) do
    %__MODULE__{}
    |> cast(domain_attrs(evidence), @fields)
    |> validate_required(@fields -- [:document, :external_object_ref])
    |> validate_inclusion(:storage_kind, ["inline", "external"])
    |> validate_number(:byte_count, greater_than_or_equal_to: 0)
    |> validate_format(:content_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> validate_length(:schema_type, min: 1, max: 200)
    |> validate_length(:media_type, min: 1, max: 200)
    |> validate_length(:external_object_ref, max: 2_000)
    |> validate_payload_shape()
    |> unique_constraint(
      [:organization_id, :provider_account_id, :schema_type, :media_type, :content_sha256],
      name: :provider_evidence_content_idx
    )
  end

  @spec to_domain(struct()) :: ProviderEvidence.t()
  def to_domain(%__MODULE__{} = row) do
    %ProviderEvidence{
      provider_evidence_id: row.provider_evidence_id,
      organization_id: row.organization_id,
      provider_account_id: row.provider_account_id,
      storage_kind: existing_storage_kind(row.storage_kind),
      schema_type: row.schema_type,
      media_type: row.media_type,
      captured_at: row.captured_at,
      byte_count: row.byte_count,
      content_sha256: row.content_sha256,
      document: maybe_unwrap(row.document),
      external_object_ref: row.external_object_ref,
      metadata: JsonDocument.unwrap_value(row.metadata)
    }
  end

  defp domain_attrs(%ProviderEvidence{} = evidence) do
    %{
      provider_evidence_id: evidence.provider_evidence_id,
      organization_id: evidence.organization_id,
      provider_account_id: evidence.provider_account_id,
      storage_kind: Atom.to_string(evidence.storage_kind),
      schema_type: evidence.schema_type,
      media_type: evidence.media_type,
      captured_at: evidence.captured_at,
      byte_count: evidence.byte_count,
      content_sha256: evidence.content_sha256,
      document: maybe_wrap(evidence.document),
      external_object_ref: evidence.external_object_ref,
      metadata: JsonDocument.wrap_value(evidence.metadata)
    }
  end

  defp validate_payload_shape(changeset) do
    case {get_field(changeset, :storage_kind), get_field(changeset, :document),
          get_field(changeset, :external_object_ref)} do
      {"inline", document, nil} when is_map(document) -> changeset
      {"external", nil, reference} when is_binary(reference) and reference != "" -> changeset
      _other -> add_error(changeset, :storage_kind, "must match exactly one evidence payload")
    end
  end

  defp existing_storage_kind("inline"), do: :inline
  defp existing_storage_kind("external"), do: :external

  defp maybe_wrap(nil), do: nil
  defp maybe_wrap(document), do: JsonDocument.wrap_value(document)

  defp maybe_unwrap(nil), do: nil
  defp maybe_unwrap(document), do: JsonDocument.unwrap_value(document)
end
