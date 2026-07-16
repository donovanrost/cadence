defmodule Cadence.GroundNetworks.ProviderEvidenceStore do
  @moduledoc "Organization-scoped storage for sanitized provider evidence."

  import Ecto.Query

  alias Cadence.GroundNetworks.{ProviderEvidence, Validation}
  alias Cadence.Ids
  alias Cadence.Persistence.Schemas.ProviderEvidenceRow
  alias Cadence.Repo

  @inline_byte_limit 262_144
  @metadata_byte_limit 16_384
  @approved_external_schemes ~w(s3 gs azure)
  @sha256_pattern ~r/\A[0-9a-f]{64}\z/

  @spec persist(binary(), binary(), map()) :: {:ok, ProviderEvidence.t()} | {:error, term()}
  def persist(organization_id, provider_account_id, attrs)
      when is_binary(organization_id) and is_binary(provider_account_id) and is_map(attrs) do
    with {:ok, evidence} <- build(organization_id, provider_account_id, attrs) do
      insert_or_fetch(evidence)
    end
  end

  @spec fetch(binary(), binary()) :: {:ok, ProviderEvidence.t()} | {:error, :not_found}
  def fetch(organization_id, provider_evidence_id)
      when is_binary(organization_id) and is_binary(provider_evidence_id) do
    ProviderEvidenceRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_evidence_id == ^provider_evidence_id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      row -> {:ok, ProviderEvidenceRow.to_domain(row)}
    end
  end

  @spec list(binary(), keyword()) :: [ProviderEvidence.t()]
  def list(organization_id, opts \\ [])
      when is_binary(organization_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    ProviderEvidenceRow
    |> where([row], row.organization_id == ^organization_id)
    |> maybe_filter_account(Keyword.get(opts, :provider_account_id))
    |> order_by([row], desc: row.captured_at, desc: row.provider_evidence_id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&ProviderEvidenceRow.to_domain/1)
  end

  @spec canonical_document(map()) :: binary()
  def canonical_document(document) when is_map(document) do
    document
    |> canonical_iodata()
    |> IO.iodata_to_binary()
  end

  @spec hash_document(map()) :: binary()
  def hash_document(document) when is_map(document) do
    document
    |> canonical_document()
    |> sha256()
  end

  defp build(organization_id, provider_account_id, attrs) do
    schema_type = value(attrs, :schema_type, "provider-evidence/v1")
    media_type = value(attrs, :media_type, "application/json")
    captured_at = value(attrs, :captured_at, DateTime.utc_now())
    metadata = attrs |> value(:metadata, %{}) |> Validation.sanitize()

    with :ok <- required_text(organization_id, :organization_id),
         :ok <- required_text(provider_account_id, :provider_account_id),
         :ok <- required_text(schema_type, :schema_type),
         :ok <- required_text(media_type, :media_type),
         :ok <- datetime(captured_at, :captured_at),
         :ok <- bounded_document(metadata, @metadata_byte_limit, :metadata_too_large),
         :ok <- safe_document(metadata) do
      build_storage(
        organization_id,
        provider_account_id,
        schema_type,
        media_type,
        captured_at,
        metadata,
        attrs
      )
    end
  end

  defp build_storage(
         organization_id,
         provider_account_id,
         schema_type,
         media_type,
         captured_at,
         metadata,
         attrs
       ) do
    case {Map.fetch(attrs, :document), Map.fetch(attrs, "document"),
          value(attrs, :external_object_ref)} do
      {{:ok, document}, _string_document, nil} ->
        build_inline(
          organization_id,
          provider_account_id,
          schema_type,
          media_type,
          captured_at,
          metadata,
          document
        )

      {:error, {:ok, document}, nil} ->
        build_inline(
          organization_id,
          provider_account_id,
          schema_type,
          media_type,
          captured_at,
          metadata,
          document
        )

      {:error, :error, external_object_ref} when is_binary(external_object_ref) ->
        build_external(
          organization_id,
          provider_account_id,
          schema_type,
          media_type,
          captured_at,
          metadata,
          external_object_ref,
          attrs
        )

      _other ->
        {:error, :exactly_one_evidence_payload_required}
    end
  end

  defp build_inline(
         organization_id,
         provider_account_id,
         schema_type,
         media_type,
         captured_at,
         metadata,
         document
       ) do
    document = Validation.sanitize(document)
    canonical = canonical_document(document)

    with :ok <- safe_document(document),
         :ok <- bounded_bytes(canonical, @inline_byte_limit, :evidence_document_too_large) do
      {:ok,
       %ProviderEvidence{
         provider_evidence_id: Ids.new("provider_evidence"),
         organization_id: organization_id,
         provider_account_id: provider_account_id,
         storage_kind: :inline,
         schema_type: schema_type,
         media_type: media_type,
         captured_at: captured_at,
         byte_count: byte_size(canonical),
         content_sha256: sha256(canonical),
         document: document,
         metadata: metadata
       }}
    end
  end

  defp build_external(
         organization_id,
         provider_account_id,
         schema_type,
         media_type,
         captured_at,
         metadata,
         external_object_ref,
         attrs
       ) do
    byte_count = value(attrs, :byte_count)
    content_sha256 = value(attrs, :content_sha256)

    with :ok <- approved_external_ref(external_object_ref),
         :ok <- non_negative_integer(byte_count, :byte_count),
         :ok <- sha256_hash(content_sha256) do
      {:ok,
       %ProviderEvidence{
         provider_evidence_id: Ids.new("provider_evidence"),
         organization_id: organization_id,
         provider_account_id: provider_account_id,
         storage_kind: :external,
         schema_type: schema_type,
         media_type: media_type,
         captured_at: captured_at,
         byte_count: byte_count,
         content_sha256: String.downcase(content_sha256),
         external_object_ref: external_object_ref,
         metadata: metadata
       }}
    end
  end

  defp insert_or_fetch(%ProviderEvidence{} = evidence) do
    evidence
    |> ProviderEvidenceRow.changeset()
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [
        :organization_id,
        :provider_account_id,
        :schema_type,
        :media_type,
        :content_sha256
      ],
      returning: true
    )
    |> case do
      {:ok, %ProviderEvidenceRow{}} -> fetch_duplicate(evidence)
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_duplicate(%ProviderEvidence{} = evidence) do
    ProviderEvidenceRow
    |> where(
      [row],
      row.organization_id == ^evidence.organization_id and
        row.provider_account_id == ^evidence.provider_account_id and
        row.schema_type == ^evidence.schema_type and
        row.media_type == ^evidence.media_type and
        row.content_sha256 == ^evidence.content_sha256
    )
    |> Repo.one!()
    |> ProviderEvidenceRow.to_domain()
    |> then(&{:ok, &1})
  end

  defp maybe_filter_account(query, nil), do: query

  defp maybe_filter_account(query, provider_account_id) when is_binary(provider_account_id) do
    where(query, [row], row.provider_account_id == ^provider_account_id)
  end

  defp canonical_iodata(map) when is_map(map) do
    items =
      map
      |> Enum.map(fn {key, item} -> {to_string(key), item} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, item} ->
        [Jason.encode_to_iodata!(key), ?:, canonical_iodata(item)]
      end)

    [?{, Enum.intersperse(items, ?,), ?}]
  end

  defp canonical_iodata(values) when is_list(values) do
    [?[, values |> Enum.map(&canonical_iodata/1) |> Enum.intersperse(?,), ?]]
  end

  defp canonical_iodata(value), do: Jason.encode_to_iodata!(value)

  defp safe_document(document) do
    if unredacted_secret?(document), do: {:error, :unsafe_evidence_document}, else: :ok
  end

  defp unredacted_secret?(map) when is_map(map) do
    Enum.any?(map, fn {key, value} ->
      (sensitive_key?(key) and value != "[REDACTED]") or unredacted_secret?(value)
    end)
  end

  defp unredacted_secret?(values) when is_list(values),
    do: Enum.any?(values, &unredacted_secret?/1)

  defp unredacted_secret?(_value), do: false

  defp sensitive_key?(key) do
    normalized = key |> to_string() |> String.downcase()

    not String.ends_with?(normalized, "_ref") and
      Enum.any?(~w(api_key authorization credential password private_key secret token), fn part ->
        String.contains?(normalized, part)
      end)
  end

  defp bounded_document(document, limit, error) do
    document
    |> canonical_document()
    |> bounded_bytes(limit, error)
  end

  defp bounded_bytes(bytes, limit, _error) when byte_size(bytes) <= limit, do: :ok
  defp bounded_bytes(_bytes, _limit, error), do: {:error, error}

  defp approved_external_ref(reference) do
    uri = URI.parse(reference)

    cond do
      uri.scheme not in @approved_external_schemes -> {:error, :unapproved_external_object_ref}
      not is_nil(uri.userinfo) -> {:error, :external_object_ref_contains_credentials}
      not is_nil(uri.query) -> {:error, :external_object_ref_contains_query}
      reference =~ "@" -> {:error, :external_object_ref_contains_credentials}
      true -> :ok
    end
  end

  defp sha256_hash(value) when is_binary(value) do
    if Regex.match?(@sha256_pattern, String.downcase(value)),
      do: :ok,
      else: {:error, :invalid_content_sha256}
  end

  defp sha256_hash(_value), do: {:error, :invalid_content_sha256}

  defp sha256(bytes),
    do: bytes |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

  defp required_text(value, _field) when is_binary(value) and value != "", do: :ok
  defp required_text(_value, field), do: {:error, {:required, field}}

  defp datetime(%DateTime{}, _field), do: :ok
  defp datetime(_value, field), do: {:error, {:invalid_datetime, field}}

  defp non_negative_integer(value, _field) when is_integer(value) and value >= 0, do: :ok
  defp non_negative_integer(_value, field), do: {:error, {:invalid_integer, field}}

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
