defmodule CadenceWeb.FrontendReleasePublication do
  @moduledoc """
  Persistence and admission boundary for signed frontend releases and catalogs.

  This module owns no signing authority. Every admission delegates envelope,
  release, artifact, origin, and catalog-state verification to
  `CadenceWeb.FrontendReleaseCatalog`, using trust records and allowed origins
  from application configuration.
  """

  import Ecto.Query

  alias Cadence.Ids
  alias Cadence.Repo

  alias CadenceWeb.FrontendReleaseCatalog

  alias CadenceWeb.FrontendReleasePublication.{
    CatalogPublication,
    DatabaseArtifactStore,
    ReleaseArtifact,
    ReleaseObject,
    ReleasePublication
  }

  @type artifact_input :: map() | list()
  @max_artifact_bytes 100_000_000
  @max_media_type_bytes 128
  @safe_media_type ~r/^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}\/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}$/

  @spec admit_release(binary() | map(), artifact_input(), keyword()) ::
          {:ok, ReleasePublication.t()} | {:error, term()}
  def admit_release(document, artifact_input, opts \\ []) when is_list(opts) do
    with {:ok, document_bytes} <- signed_document_bytes(document),
         {:ok, verified} <- verify_release(document_bytes, opts),
         {:ok, artifact_bytes} <- normalize_artifact_inputs(artifact_input),
         {:ok, artifact_specs} <- validate_artifact_bytes(verified.release, artifact_bytes) do
      persist_release(verified, document_bytes, artifact_specs)
    end
  end

  @spec publish_release(binary() | map(), artifact_input(), keyword()) ::
          {:ok, ReleasePublication.t()} | {:error, term()}
  def publish_release(document, artifact_input, opts \\ []),
    do: admit_release(document, artifact_input, opts)

  @spec admit_catalog(binary() | map(), keyword()) ::
          {:ok, CatalogPublication.t()} | {:error, term()}
  def admit_catalog(document, opts \\ []) when is_list(opts) do
    with {:ok, document_bytes} <- signed_document_bytes(document) do
      persist_catalog(document_bytes, opts)
    end
  end

  @spec publish_catalog(binary() | map(), keyword()) ::
          {:ok, CatalogPublication.t()} | {:error, term()}
  def publish_catalog(document, opts \\ []), do: admit_catalog(document, opts)

  @spec fetch_release(binary()) :: {:ok, ReleasePublication.t()} | {:error, :not_found}
  def fetch_release(release_id) when is_binary(release_id) do
    case Repo.get_by(ReleasePublication, release_id: release_id) do
      nil -> {:error, :not_found}
      %ReleasePublication{} = row -> {:ok, Repo.preload(row, :artifacts)}
    end
  end

  @spec fetch_artifact(binary(), binary(), binary()) ::
          {:ok, map()} | {:error, :not_found}
  def fetch_artifact(application_id, release_id, path)
      when is_binary(application_id) and is_binary(release_id) and is_binary(path) do
    if valid_artifact_lookup?(application_id, release_id, path),
      do: fetch_valid_artifact(application_id, release_id, path),
      else: {:error, :not_found}
  end

  def fetch_artifact(_application_id, _release_id, _path), do: {:error, :not_found}

  @spec fetch_catalog(pos_integer()) :: {:ok, CatalogPublication.t()} | {:error, :not_found}
  def fetch_catalog(sequence) when is_integer(sequence) and sequence > 0 do
    case Repo.get_by(CatalogPublication, sequence: sequence) do
      nil -> {:error, :not_found}
      %CatalogPublication{} = row -> {:ok, row}
    end
  end

  @spec latest_catalog() :: {:ok, CatalogPublication.t()} | {:error, :not_found}
  def latest_catalog do
    case CatalogPublication |> order_by(desc: :sequence) |> limit(1) |> Repo.one() do
      nil -> {:error, :not_found}
      %CatalogPublication{} = row -> {:ok, row}
    end
  end

  defp verify_release(document, opts) do
    FrontendReleaseCatalog.verify_release(
      document,
      configured_trust_records(),
      verifier_opts(opts)
    )
  end

  defp verify_catalog(document, opts, accepted_state) do
    FrontendReleaseCatalog.verify_catalog(
      document,
      configured_trust_records(),
      verifier_opts(opts) |> Keyword.put(:accepted_state, accepted_state)
    )
  end

  defp persist_release(verified, document_bytes, artifact_specs) do
    release = verified.release
    release_id = release["releaseId"]

    transaction_result =
      Repo.transaction(fn ->
        :ok = advisory_lock("frontend-release:" <> release_id)

        case store_and_verify(artifact_specs) do
          {:ok, stored_artifacts} ->
            persist_locked_release(
              locked_release_by_identity(release_id),
              verified,
              document_bytes,
              stored_artifacts
            )

          {:error, reason} ->
            Repo.rollback(store_error(reason))
        end
      end)

    normalize_transaction_result(transaction_result)
  end

  defp persist_new_release(verified, document_bytes, stored_artifacts) do
    release = verified.release
    release_id = release["releaseId"]

    if Repo.exists?(
         from(row in ReleasePublication, where: row.payload_digest == ^verified.digest)
       ) do
      Repo.rollback(error(:release_digest_conflict, "$.payload.releaseId"))
    end

    if Repo.exists?(
         from(row in ReleasePublication,
           where: row.signed_document_digest == ^digest(document_bytes)
         )
       ) do
      Repo.rollback(error(:release_document_conflict, "$.payload.releaseId"))
    end

    attrs = release_publication_attrs(verified, document_bytes)

    case Repo.insert(ReleasePublication.changeset(attrs)) do
      {:ok, row} ->
        Enum.each(stored_artifacts, fn artifact ->
          artifact
          |> release_artifact_attrs(row.publication_id, release_id)
          |> ReleaseArtifact.changeset()
          |> insert_or_rollback()
        end)

        Repo.preload(row, :artifacts)

      {:error, changeset} ->
        Repo.rollback(persistence_error(changeset))
    end
  end

  defp persist_locked_release(nil, verified, document_bytes, stored_artifacts),
    do: persist_new_release(verified, document_bytes, stored_artifacts)

  defp persist_locked_release(existing, verified, document_bytes, _stored_artifacts) do
    if exact_release_retry?(existing, verified, document_bytes) do
      Repo.preload(existing, :artifacts)
    else
      Repo.rollback(error(:release_identity_fork, "$.payload.releaseId"))
    end
  end

  defp persist_catalog(document_bytes, opts) do
    transaction_result =
      Repo.transaction(fn ->
        :ok = advisory_lock("frontend-release-catalog")

        latest = locked_latest_catalog()
        accepted_state = latest && latest.accepted_state

        with {:ok, verified} <- verify_catalog(document_bytes, opts, accepted_state),
             :ok <- same_sequence_document_is_exact(latest, verified, document_bytes),
             {:ok, release_references} <-
               require_admitted_releases(verified.catalog, verified.entries) do
          persist_catalog_result(verified, document_bytes, release_references)
        else
          {:error, failure} -> Repo.rollback(failure)
        end
      end)

    normalize_transaction_result(transaction_result)
  end

  defp persist_catalog_result(
         %{acceptance: :identical, catalog: catalog},
         _document_bytes,
         _release_references
       ) do
    Repo.get_by!(CatalogPublication, sequence: catalog["sequence"])
  end

  defp persist_catalog_result(verified, document_bytes, release_references) do
    attrs = catalog_publication_attrs(verified, document_bytes, release_references)

    case Repo.insert(CatalogPublication.changeset(attrs)) do
      {:ok, row} -> row
      {:error, changeset} -> Repo.rollback(persistence_error(changeset))
    end
  end

  defp same_sequence_document_is_exact(nil, _verified, _document_bytes), do: :ok

  defp same_sequence_document_is_exact(existing, verified, document_bytes) do
    sequence = verified.catalog["sequence"]

    if existing.sequence == sequence do
      cond do
        existing.catalog_digest != verified.digest ->
          {:error, error(:same_sequence_fork, "$.payload.sequence")}

        existing.signed_document_bytes != document_bytes ->
          {:error, error(:same_sequence_fork, "$.payload.sequence")}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp require_admitted_releases(%{"entries" => raw_entries}, entries)
       when is_list(raw_entries) and is_list(entries) and length(raw_entries) == length(entries) do
    raw_entries
    |> Enum.zip(entries)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{raw_entry, entry}, index}, {:ok, references} ->
      path = "$.payload.entries[#{index}]"

      with {:ok, current} <-
             require_admitted_release(
               Map.fetch!(raw_entry, "current"),
               entry.current,
               path <> ".current"
             ),
           {:ok, fallback} <-
             optional_require_admitted_release(raw_entry, entry.fallback, path <> ".fallback") do
        reference = release_reference(entry, current, fallback)
        {:cont, {:ok, [reference | references]}}
      else
        {:error, _} = failure -> {:halt, failure}
      end
    end)
    |> case do
      {:ok, references} -> {:ok, Enum.reverse(references)}
      failure -> failure
    end
  end

  defp require_admitted_releases(_catalog, _entries),
    do: {:error, error(:invalid_catalog_entries, "$.payload.entries")}

  defp require_admitted_release(signed_envelope, release, path) do
    release_id = release["releaseId"]
    payload_bytes = canonical_json(release)
    expected_digest = digest(payload_bytes)
    signed_document_bytes = canonical_json(signed_envelope)
    signed_document_digest = digest(signed_document_bytes)

    case Repo.get_by(ReleasePublication, release_id: release_id) do
      nil ->
        {:error, error(:missing_release_publication, path)}

      %ReleasePublication{} = row ->
        cond do
          row.payload_digest != expected_digest or row.payload_bytes != payload_bytes ->
            release_publication_mismatch(path)

          row.signed_document_digest != signed_document_digest or
              row.signed_document_bytes != signed_document_bytes ->
            release_publication_mismatch(path)

          release_identity_matches?(row, release) ->
            {:ok, row}

          true ->
            release_publication_mismatch(path)
        end
    end
  end

  defp optional_require_admitted_release(raw_entry, nil, _path) do
    case Map.fetch(raw_entry, "fallback") do
      :error -> {:ok, nil}
      {:ok, _value} -> {:error, error(:invalid_catalog_entries, "$.payload.entries")}
    end
  end

  defp optional_require_admitted_release(raw_entry, release, path) do
    case Map.fetch(raw_entry, "fallback") do
      {:ok, signed_envelope} -> require_admitted_release(signed_envelope, release, path)
      :error -> {:error, error(:invalid_catalog_entries, path)}
    end
  end

  defp release_identity_matches?(row, release) do
    row.release_id == release["releaseId"] and
      row.application_id == release["application"]["id"] and
      row.application_version == release["application"]["version"] and
      row.package_id == release["package"]["id"] and
      row.package_version == release["package"]["version"] and
      row.surface_id == release["surface"]["id"] and
      row.surface_version == release["surface"]["version"]
  end

  defp release_reference(entry, current, fallback) do
    reference = %{
      "identity" => entry.identity,
      "currentReleaseId" => current.release_id,
      "currentReleaseDigest" => current.payload_digest,
      "currentSignedDocumentDigest" => current.signed_document_digest
    }

    if fallback do
      reference
      |> Map.put("fallbackReleaseId", fallback.release_id)
      |> Map.put("fallbackReleaseDigest", fallback.payload_digest)
      |> Map.put("fallbackSignedDocumentDigest", fallback.signed_document_digest)
    else
      reference
    end
  end

  defp release_publication_mismatch(path),
    do: {:error, error(:release_publication_mismatch, path)}

  defp locked_release_by_identity(release_id) do
    ReleasePublication
    |> where([row], row.release_id == ^release_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_latest_catalog do
    CatalogPublication
    |> where([row], row.acceptance_state == "accepted")
    |> order_by(desc: :sequence)
    |> limit(1)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp exact_release_retry?(existing, verified, document_bytes) do
    existing.payload_digest == verified.digest and
      existing.payload_bytes == verified.payload_bytes and
      existing.signed_document_bytes == document_bytes and
      existing.signed_document_digest == digest(document_bytes)
  end

  defp release_publication_attrs(verified, document_bytes) do
    release = verified.release
    application = release["application"]
    package = release["package"]
    surface = release["surface"]

    %{
      publication_id: Ids.new("frontend_release_publication"),
      release_id: release["releaseId"],
      application_id: application["id"],
      application_version: application["version"],
      package_id: package["id"],
      package_version: package["version"],
      surface_id: surface["id"],
      surface_version: surface["version"],
      remote_name: release["remoteName"],
      exposed_module: release["exposedModule"],
      artifact_base_url: release["artifactBaseUrl"],
      payload_digest: verified.digest,
      signed_document_digest: digest(document_bytes),
      signed_document_bytes: document_bytes,
      payload_bytes: verified.payload_bytes,
      signing_key_id: verified.key_id,
      signing_role: verified.signing_role,
      provenance: release["provenance"],
      released_at: timestamp!(release["releasedAt"]),
      artifact_count: length(release["artifacts"]),
      acceptance_state: "accepted",
      accepted_at: DateTime.utc_now(),
      metadata: %{}
    }
  end

  defp release_artifact_attrs(artifact, publication_id, release_id) do
    %{
      artifact_id: Ids.new("frontend_release_artifact"),
      release_publication_id: publication_id,
      release_id: release_id,
      path: artifact.path,
      sha256: artifact.sha256,
      size: artifact.size,
      media_type: artifact.media_type,
      object_key: artifact.object_key,
      metadata: %{}
    }
  end

  defp catalog_publication_attrs(verified, document_bytes, release_references) do
    catalog = verified.catalog

    %{
      publication_id: Ids.new("frontend_release_catalog_publication"),
      sequence: catalog["sequence"],
      catalog_digest: verified.digest,
      signed_document_digest: digest(document_bytes),
      signed_document_bytes: document_bytes,
      payload_bytes: verified.payload_bytes,
      signing_key_id: verified.key_id,
      signing_role: verified.signing_role,
      published_at: timestamp!(catalog["publishedAt"]),
      expires_at: timestamp!(catalog["expiresAt"]),
      acceptance_state: "accepted",
      accepted_state: verified.accepted_state,
      release_references: %{"entries" => release_references},
      accepted_at: DateTime.utc_now(),
      metadata: %{}
    }
  end

  defp normalize_artifact_inputs(input) when is_map(input) do
    input
    |> Map.to_list()
    |> normalize_artifact_pairs()
  end

  defp normalize_artifact_inputs(input) when is_list(input),
    do: normalize_artifact_pairs(input)

  defp normalize_artifact_inputs(_input),
    do: {:error, error(:invalid_artifact_input, "$.artifacts")}

  defp normalize_artifact_pairs(pairs) do
    pairs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, MapSet.new(), %{}}, &normalize_artifact_pair(&1, &2))
    |> case do
      {:ok, _paths, values} -> {:ok, values}
      failure -> failure
    end
  rescue
    _ -> {:error, error(:invalid_artifact_input, "$.artifacts")}
  end

  defp normalize_artifact_pair({pair, index}, {:ok, paths, acc}) do
    case artifact_pair(pair) do
      {:ok, path, bytes} -> add_artifact(path, bytes, index, paths, acc)
      :error -> {:halt, {:error, error(:invalid_artifact_input, "$.artifacts[#{index}]")}}
    end
  end

  defp add_artifact(path, bytes, index, paths, acc) do
    cond do
      not is_binary(path) or not is_binary(bytes) ->
        {:halt, {:error, error(:invalid_artifact_input, "$.artifacts[#{index}]")}}

      MapSet.member?(paths, path) ->
        {:halt, {:error, error(:duplicate_artifact_path, "$.artifacts[#{index}].path")}}

      true ->
        {:cont, {:ok, MapSet.put(paths, path), Map.put(acc, path, bytes)}}
    end
  end

  defp artifact_pair({path, bytes}), do: {:ok, path, bytes}
  defp artifact_pair(%{"path" => path, "bytes" => bytes}), do: {:ok, path, bytes}
  defp artifact_pair(%{path: path, bytes: bytes}), do: {:ok, path, bytes}
  defp artifact_pair(_pair), do: :error

  defp validate_artifact_bytes(release, artifact_bytes) do
    declarations = release["artifacts"]
    declared_paths = Enum.map(declarations, & &1["path"])
    actual_paths = Map.keys(artifact_bytes)

    cond do
      actual_paths -- declared_paths != [] ->
        {:error, error(:undeclared_artifact, "$.artifacts")}

      declared_paths -- actual_paths != [] ->
        {:error, error(:missing_artifact, "$.artifacts")}

      true ->
        declarations
        |> Enum.with_index()
        |> Enum.reduce_while(
          {:ok, []},
          &validate_artifact_declaration(&1, &2, artifact_bytes)
        )
        |> case do
          {:ok, values} ->
            validate_artifact_total(values)

          failure ->
            failure
        end
    end
  end

  defp validate_artifact_total(values) do
    values = Enum.reverse(values)

    if Enum.sum(Enum.map(values, & &1.size)) <= @max_artifact_bytes,
      do: {:ok, values},
      else: {:error, error(:artifact_byte_cap_exceeded, "$.artifacts")}
  end

  defp validate_artifact_declaration(
         {declaration, index},
         {:ok, acc},
         artifact_bytes
       ) do
    path = declaration["path"]
    bytes = Map.fetch!(artifact_bytes, path)

    cond do
      byte_size(bytes) != declaration["size"] ->
        {:halt, {:error, error(:artifact_size_mismatch, "$.artifacts[#{index}].size")}}

      digest_hex(bytes) != declaration["sha256"] ->
        {:halt, {:error, error(:artifact_hash_mismatch, "$.artifacts[#{index}].sha256")}}

      true ->
        {:cont,
         {:ok,
          [
            %{
              path: path,
              bytes: bytes,
              sha256: declaration["sha256"],
              size: declaration["size"],
              media_type: declaration["mediaType"]
            }
            | acc
          ]}}
    end
  end

  defp store_and_verify(artifact_specs) do
    store_artifacts(DatabaseArtifactStore, artifact_specs)
  end

  defp store_artifacts(store, artifact_specs) do
    Enum.reduce_while(
      artifact_specs,
      {:ok, []},
      &store_artifact_step(&1, &2, store)
    )
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      failure -> failure
    end
  end

  defp store_artifact_step(artifact, {:ok, acc}, store) do
    case store_one_artifact(store, artifact) do
      {:ok, stored_artifact} -> {:cont, {:ok, [stored_artifact | acc]}}
      {:error, reason} -> {:halt, {:error, store_error(reason)}}
    end
  end

  defp store_one_artifact(store, artifact) do
    digest_value = "sha256:" <> artifact.sha256

    case safe_store_call(store, :put, [digest_value, artifact.bytes]) do
      {:ok, stored} when is_map(stored) ->
        object_key = Map.get(stored, :object_key, Map.get(stored, "object_key"))
        stored_size = Map.get(stored, :size, Map.get(stored, "size"))

        if object_key == digest_value and stored_size == artifact.size do
          {:ok, Map.merge(artifact, %{object_key: object_key, digest: digest_value})}
        else
          {:error, error(:artifact_store_invalid_result, "$.artifacts")}
        end

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, error(:artifact_store_invalid_result, inspect(other))}
    end
  end

  defp safe_store_call(store, function, args) do
    apply(store, function, args)
  rescue
    error -> {:error, {:artifact_store_exception, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:artifact_store_throw, kind, reason}}
  end

  defp store_error(:artifact_bytes_mismatch), do: error(:artifact_conflict, "$.artifacts")
  defp store_error(:artifact_digest_mismatch), do: error(:artifact_hash_mismatch, "$.artifacts")
  defp store_error(:artifact_size_mismatch), do: error(:artifact_size_mismatch, "$.artifacts")
  defp store_error(:artifact_too_large), do: error(:artifact_byte_cap_exceeded, "$.artifacts")
  defp store_error(:artifact_not_found), do: error(:artifact_not_found, "$.artifacts")

  defp store_error(%{code: _code} = failure), do: failure
  defp store_error(reason), do: error(:artifact_store_failure, inspect(reason))

  defp signed_document_bytes(document) when is_binary(document), do: {:ok, document}

  defp signed_document_bytes(document) when is_map(document) do
    {:ok, Jason.encode!(document, maps: :strict)}
  rescue
    _ -> {:error, error(:invalid_document, "$")}
  end

  defp signed_document_bytes(_document), do: {:error, error(:invalid_document, "$")}

  defp configured_trust_records, do: Keyword.get(publication_config(), :trust_records, [])

  defp verifier_opts(opts) do
    base = [allowed_origins: Keyword.get(publication_config(), :allowed_origins, [])]

    case Keyword.fetch(opts, :now) do
      {:ok, now} -> Keyword.put(base, :now, now)
      :error -> base
    end
  end

  defp publication_config do
    case Application.get_env(:cadence_web, :frontend_release_publication, []) do
      config when is_list(config) -> config
      _ -> []
    end
  end

  defp advisory_lock(lock_key) do
    _ = Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [lock_key])
    :ok
  end

  defp normalize_transaction_result({:ok, row}), do: {:ok, row}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}

  defp valid_artifact_lookup?(application_id, release_id, path) do
    valid_identifier?(application_id) and valid_release_id?(release_id) and
      valid_artifact_path?(path)
  end

  defp fetch_valid_artifact(application_id, release_id, path) do
    case Repo.one(artifact_lookup_query(application_id, release_id, path)) do
      nil -> {:error, :not_found}
      artifact -> validate_artifact_lookup(artifact)
    end
  end

  # Artifact bytes are digest-verified before publication and both publication
  # tables and objects are append-only. Request-time serving therefore
  # reconciles immutable signed metadata with immutable object metadata, while
  # keeping the bytea bounded to the chunk reads performed by the controller.
  defp artifact_lookup_query(application_id, release_id, path) do
    from(publication in ReleasePublication,
      join: artifact in ReleaseArtifact,
      on:
        artifact.release_publication_id == publication.publication_id and
          artifact.release_id == publication.release_id,
      join: object in ReleaseObject,
      on: object.sha256 == artifact.sha256,
      where:
        publication.application_id == ^application_id and
          publication.release_id == ^release_id and
          publication.acceptance_state == "accepted" and
          artifact.path == ^path and
          artifact.size == object.size,
      select: %{
        digest: artifact.object_key,
        artifact_sha256: artifact.sha256,
        object_sha256: object.sha256,
        artifact_size: artifact.size,
        object_size: object.size,
        media_type: artifact.media_type
      }
    )
  end

  defp validate_artifact_lookup(%{
         digest: digest,
         artifact_sha256: artifact_sha256,
         object_sha256: object_sha256,
         artifact_size: artifact_size,
         object_size: object_size,
         media_type: media_type
       }) do
    with :ok <- validate_lookup_digest(digest, artifact_sha256),
         :ok <- validate_lookup_sha256(artifact_sha256, object_sha256),
         :ok <- validate_lookup_size(artifact_size, object_size),
         :ok <- validate_lookup_media_type(media_type) do
      {:ok,
       %{
         digest: digest,
         sha256: object_sha256,
         size: artifact_size,
         media_type: media_type
       }}
    else
      {:error, :invalid_artifact_metadata} -> {:error, :not_found}
    end
  end

  defp validate_artifact_lookup(_artifact), do: {:error, :not_found}

  defp validate_lookup_digest("sha256:" <> sha256, sha256),
    do: validate_lookup_sha256(sha256, sha256)

  defp validate_lookup_digest(_digest, _sha256), do: {:error, :invalid_artifact_metadata}

  defp validate_lookup_sha256(sha256, sha256) when is_binary(sha256) do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, sha256),
      do: :ok,
      else: {:error, :invalid_artifact_metadata}
  end

  defp validate_lookup_sha256(_artifact_sha256, _object_sha256),
    do: {:error, :invalid_artifact_metadata}

  defp validate_lookup_size(size, size)
       when is_integer(size) and size >= 0 and size <= @max_artifact_bytes,
       do: :ok

  defp validate_lookup_size(_artifact_size, _object_size),
    do: {:error, :invalid_artifact_metadata}

  defp validate_lookup_media_type(media_type)
       when is_binary(media_type) and byte_size(media_type) <= @max_media_type_bytes do
    if String.valid?(media_type) and Regex.match?(@safe_media_type, media_type),
      do: :ok,
      else: {:error, :invalid_artifact_metadata}
  end

  defp validate_lookup_media_type(_media_type), do: {:error, :invalid_artifact_metadata}

  defp valid_identifier?(value) do
    byte_size(value) <= 128 and String.valid?(value) and
      Regex.match?(~r/^[a-z][a-z0-9._-]{0,127}$/, value)
  end

  defp valid_release_id?(value),
    do: String.valid?(value) and Regex.match?(~r/^sha256:[0-9a-f]{64}$/, value)

  defp valid_artifact_path?(value) do
    byte_size(value) > 0 and byte_size(value) <= 256 and String.valid?(value) and
      not String.starts_with?(value, "/") and not String.contains?(value, "\\") and
      Enum.all?(String.split(value, "/"), &(&1 not in ["", ".", ".."]))
  end

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, row} -> row
      {:error, changeset} -> Repo.rollback(persistence_error(changeset))
    end
  end

  defp persistence_error(%Ecto.Changeset{} = changeset),
    do: error(:persistence_constraint, inspect(changeset.errors))

  defp timestamp!(value) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    DateTime.truncate(datetime, :microsecond)
  end

  defp digest(bytes),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp digest_hex(bytes),
    do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp canonical_json(value) when is_map(value) do
    value
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map_join(",", fn key ->
      Jason.encode!(key) <> ":" <> canonical_json(Map.fetch!(value, key))
    end)
    |> then(&("{" <> &1 <> "}"))
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_binary(value), do: Jason.encode!(value)
  defp canonical_json(value) when is_integer(value), do: Integer.to_string(value)
  defp canonical_json(true), do: "true"
  defp canonical_json(false), do: "false"
  defp canonical_json(nil), do: "null"

  defp error(code, path), do: %{code: code, path: path}
end
