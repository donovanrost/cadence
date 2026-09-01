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
  @process_publication_config_key {__MODULE__, :publication_config}

  @spec admit_release(binary() | map(), artifact_input(), keyword()) ::
          {:ok, ReleasePublication.t()} | {:error, term()}
  def admit_release(document, artifact_input, opts \\ []) when is_list(opts) do
    with {:ok, document_bytes} <- signed_document_bytes(document),
         {:ok, verified} <- verify_release(document_bytes, opts),
         {:ok, artifact_bytes} <- normalize_artifact_inputs(artifact_input),
         {:ok, artifact_specs} <- validate_artifact_inputs(verified.release, artifact_bytes) do
      persist_release(verified, document_bytes, artifact_specs, opts)
    end
  end

  @spec publish_release(binary() | map(), artifact_input(), keyword()) ::
          {:ok, ReleasePublication.t()} | {:error, term()}
  def publish_release(document, artifact_input, opts \\ []),
    do: admit_release(document, artifact_input, opts)

  @spec publish_release_with_outcome(binary() | map(), artifact_input(), keyword()) ::
          {:ok, ReleasePublication.t(), :created | :replayed} | {:error, term()}
  def publish_release_with_outcome(document, artifact_input, opts \\ []) when is_list(opts) do
    admit_release(document, artifact_input, Keyword.put(opts, :return_outcome, true))
  end

  @spec stage_artifact(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def stage_artifact(digest, file_path) when is_binary(digest) and is_binary(file_path) do
    case DatabaseArtifactStore.put_file(digest, file_path) do
      {:ok, stored} -> {:ok, stored}
      {:error, reason} -> {:error, normalize_artifact_store_error(reason)}
    end
  end

  def stage_artifact(_digest, _file_path),
    do: {:error, error(:invalid_artifact_input, "$.artifact")}

  @spec admit_catalog(binary() | map(), keyword()) ::
          {:ok, CatalogPublication.t()} | {:error, term()}
  def admit_catalog(_document, _opts \\ []), do: {:error, :catalog_activation_required}

  @spec publish_catalog(binary() | map(), keyword()) ::
          {:ok, CatalogPublication.t()} | {:error, term()}
  def publish_catalog(_document, _opts \\ []), do: {:error, :catalog_activation_required}

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
      configured_trust_records(opts),
      verifier_opts(opts)
    )
  end

  defp persist_release(verified, document_bytes, artifact_specs, opts) do
    release = verified.release
    release_id = release["releaseId"]

    transaction_result =
      Repo.transaction(fn ->
        :ok = advisory_lock("frontend-release:" <> release_id)
        persist_locked_or_new_release(verified, document_bytes, artifact_specs, opts)
      end)

    normalize_transaction_result(transaction_result, Keyword.get(opts, :return_outcome, false))
  end

  defp persist_locked_or_new_release(verified, document_bytes, artifact_specs, opts) do
    release_id = verified.release["releaseId"]

    case locked_release_by_identity(release_id) do
      %ReleasePublication{} = existing ->
        persist_locked_release(existing, verified, document_bytes, opts)

      nil ->
        persist_missing_release(verified, document_bytes, artifact_specs, opts)
    end
  end

  defp persist_missing_release(verified, document_bytes, artifact_specs, opts) do
    case store_and_verify(artifact_specs) do
      {:ok, stored_artifacts} ->
        {:created, persist_new_release(verified, document_bytes, stored_artifacts, opts)}

      {:error, reason} ->
        Repo.rollback(normalize_artifact_store_error(reason))
    end
  end

  defp persist_new_release(verified, document_bytes, stored_artifacts, opts) do
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

    attrs = release_publication_attrs(verified, document_bytes, opts)

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

  defp persist_locked_release(existing, verified, document_bytes, _opts) do
    if exact_release_retry?(existing, verified, document_bytes) do
      {:replayed, Repo.preload(existing, :artifacts)}
    else
      Repo.rollback(error(:release_identity_fork, "$.payload.releaseId"))
    end
  end

  defp locked_release_by_identity(release_id) do
    ReleasePublication
    |> where([row], row.release_id == ^release_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp exact_release_retry?(existing, verified, document_bytes) do
    existing.payload_digest == verified.digest and
      existing.payload_bytes == verified.payload_bytes and
      existing.signed_document_bytes == document_bytes and
      existing.signed_document_digest == digest(document_bytes)
  end

  defp release_publication_attrs(verified, document_bytes, opts) do
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
      manifest_path: release["manifest"]["path"],
      manifest_sha256: release["manifest"]["sha256"],
      manifest_size: release["manifest"]["size"],
      manifest_media_type: release["manifest"]["mediaType"],
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
      metadata: publication_metadata(opts)
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
    normalize_artifact_pairs(pairs, 0, MapSet.new(), %{})
  end

  defp normalize_artifact_pairs([], _index, _paths, values), do: {:ok, values}

  defp normalize_artifact_pairs([pair | rest], index, paths, acc) do
    case artifact_pair(pair) do
      {:ok, path, source} ->
        case add_artifact(path, source, index, paths, acc) do
          {:cont, {:ok, paths, acc}} ->
            normalize_artifact_pairs(rest, index + 1, paths, acc)

          {:halt, failure} ->
            failure
        end

      :error ->
        {:error, error(:invalid_artifact_input, "$.artifacts[#{index}]")}
    end
  end

  defp normalize_artifact_pairs(_pairs, _index, _paths, _acc),
    do: {:error, error(:invalid_artifact_input, "$.artifacts")}

  defp add_artifact(path, source, index, paths, acc) do
    cond do
      not is_binary(path) or not valid_artifact_source?(source) ->
        {:halt, {:error, error(:invalid_artifact_input, "$.artifacts[#{index}]")}}

      MapSet.member?(paths, path) ->
        {:halt, {:error, error(:duplicate_artifact_path, "$.artifacts[#{index}].path")}}

      true ->
        {:cont, {:ok, MapSet.put(paths, path), Map.put(acc, path, source)}}
    end
  end

  defp artifact_pair({path, bytes}), do: {:ok, path, bytes}
  defp artifact_pair(%{"path" => path, "bytes" => bytes}), do: {:ok, path, bytes}

  defp artifact_pair(%{"path" => path, "sha256" => digest, "size" => size}),
    do: {:ok, path, {:object, digest, size}}

  defp artifact_pair(%{path: path, bytes: bytes}), do: {:ok, path, bytes}
  defp artifact_pair(_pair), do: :error

  defp valid_artifact_source?(source) when is_binary(source), do: true

  defp valid_artifact_source?({:object, digest, size})
       when is_binary(digest) and is_integer(size) and size >= 0,
       do: true

  defp valid_artifact_source?(_source), do: false

  defp validate_artifact_inputs(release, artifact_inputs) do
    declarations = release["artifacts"]
    declared_paths = Enum.map(declarations, & &1["path"])
    actual_paths = Map.keys(artifact_inputs)

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
          &validate_artifact_declaration(&1, &2, artifact_inputs)
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
         artifact_inputs
       ) do
    path = declaration["path"]
    source = Map.fetch!(artifact_inputs, path)

    case source do
      bytes when is_binary(bytes) ->
        validate_inline_artifact(declaration, index, acc, bytes)

      {:object, digest, size} ->
        validate_staged_artifact(declaration, index, acc, source, digest, size)

      _invalid ->
        {:halt, {:error, error(:invalid_artifact_input, "$.artifacts[#{index}]")}}
    end
  end

  defp validate_inline_artifact(declaration, index, acc, bytes) do
    cond do
      byte_size(bytes) != declaration["size"] ->
        {:halt, {:error, error(:artifact_size_mismatch, "$.artifacts[#{index}].size")}}

      digest_hex(bytes) != declaration["sha256"] ->
        {:halt, {:error, error(:artifact_hash_mismatch, "$.artifacts[#{index}].sha256")}}

      true ->
        {:cont, {:ok, [artifact_spec(declaration, bytes) | acc]}}
    end
  end

  defp validate_staged_artifact(declaration, index, acc, source, digest, size) do
    cond do
      digest != "sha256:" <> declaration["sha256"] ->
        {:halt, {:error, error(:artifact_hash_mismatch, "$.artifacts[#{index}].sha256")}}

      size != declaration["size"] ->
        {:halt, {:error, error(:artifact_size_mismatch, "$.artifacts[#{index}].size")}}

      true ->
        {:cont, {:ok, [artifact_spec(declaration, source) | acc]}}
    end
  end

  defp artifact_spec(declaration, source) do
    %{
      path: declaration["path"],
      source: source,
      sha256: declaration["sha256"],
      size: declaration["size"],
      media_type: declaration["mediaType"]
    }
  end

  defp store_and_verify(artifact_specs) do
    store_artifacts(artifact_specs)
  end

  defp store_artifacts(artifact_specs) do
    Enum.reduce_while(
      artifact_specs,
      {:ok, []},
      &store_artifact_step/2
    )
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      failure -> failure
    end
  end

  defp store_artifact_step(artifact, {:ok, acc}) do
    case store_one_artifact(artifact) do
      {:ok, stored_artifact} -> {:cont, {:ok, [stored_artifact | acc]}}
      {:error, reason} -> {:halt, {:error, normalize_artifact_store_error(reason)}}
    end
  end

  defp store_one_artifact(artifact) do
    digest_value = "sha256:" <> artifact.sha256

    result =
      case artifact.source do
        bytes when is_binary(bytes) -> DatabaseArtifactStore.put(digest_value, bytes)
        {:object, digest, size} -> DatabaseArtifactStore.promote_staged(digest, size)
      end

    case result do
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

  defp normalize_artifact_store_error(:artifact_bytes_mismatch),
    do: error(:artifact_conflict, "$.artifacts")

  defp normalize_artifact_store_error(:artifact_digest_mismatch),
    do: error(:artifact_hash_mismatch, "$.artifacts")

  defp normalize_artifact_store_error(:artifact_size_mismatch),
    do: error(:artifact_size_mismatch, "$.artifacts")

  defp normalize_artifact_store_error(:artifact_too_large),
    do: error(:artifact_byte_cap_exceeded, "$.artifacts")

  defp normalize_artifact_store_error(:artifact_not_found),
    do: error(:artifact_not_found, "$.artifacts")

  defp normalize_artifact_store_error(%DBConnection.ConnectionError{} = failure), do: failure

  defp normalize_artifact_store_error(
         %Postgrex.Error{postgres: %{code: :admin_shutdown}} = failure
       ),
       do: failure

  defp normalize_artifact_store_error(
         {operation, %DBConnection.ConnectionError{}} = tagged_failure
       )
       when operation in [:object_insert, :object_metadata, :object_chunk],
       do: tagged_failure

  defp normalize_artifact_store_error(
         {operation, %Postgrex.Error{postgres: %{code: :admin_shutdown}}} = tagged_failure
       )
       when operation in [:object_insert, :object_metadata, :object_chunk],
       do: tagged_failure

  defp normalize_artifact_store_error(%{code: _code} = failure), do: failure
  defp normalize_artifact_store_error(reason), do: error(:artifact_store_failure, inspect(reason))

  defp signed_document_bytes(document) when is_binary(document), do: {:ok, document}

  defp signed_document_bytes(document) when is_map(document) do
    case Jason.encode(document, maps: :strict) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, _reason} -> {:error, error(:invalid_document, "$")}
    end
  end

  defp signed_document_bytes(_document), do: {:error, error(:invalid_document, "$")}

  defp configured_trust_records(opts),
    do: Keyword.get(publication_config(opts), :trust_records, [])

  defp verifier_opts(opts) do
    base = [allowed_origins: Keyword.get(publication_config(opts), :allowed_origins, [])]

    case Keyword.fetch(opts, :now) do
      {:ok, now} -> Keyword.put(base, :now, now)
      :error -> base
    end
  end

  defp publication_config(opts) do
    case Keyword.fetch(opts, :publication_config) do
      {:ok, config} -> normalize_publication_config(config)
      :error -> process_or_application_publication_config()
    end
  end

  defp process_or_application_publication_config do
    case Process.get(@process_publication_config_key, :not_configured) do
      :not_configured -> application_publication_config()
      config -> normalize_publication_config(config)
    end
  end

  defp application_publication_config do
    case Application.get_env(:cadence_web, :frontend_release_publication, []) do
      config when is_list(config) -> config
      _ -> []
    end
  end

  defp normalize_publication_config(config) when is_list(config), do: config
  defp normalize_publication_config(_config), do: []

  defp publication_metadata(opts) do
    case Keyword.get(opts, :publisher_identity) do
      identity
      when is_binary(identity) and byte_size(identity) > 0 and byte_size(identity) <= 128 ->
        if String.valid?(identity),
          do: %{"publisher_identity" => identity},
          else: %{}

      _missing_or_invalid ->
        %{}
    end
  end

  defp advisory_lock(lock_key) do
    _ = Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [lock_key])
    :ok
  end

  defp normalize_transaction_result({:ok, {outcome, row}}, true), do: {:ok, row, outcome}
  defp normalize_transaction_result({:ok, {_outcome, row}}, false), do: {:ok, row}
  defp normalize_transaction_result({:error, reason}, _return_outcome), do: {:error, reason}

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

  @doc "Canonical JSON used by signed release and catalog documents."
  @spec canonical_json(term()) :: binary()
  def canonical_json(value) when is_map(value) do
    value
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map_join(",", fn key ->
      Jason.encode!(key) <> ":" <> canonical_json(Map.fetch!(value, key))
    end)
    |> then(&("{" <> &1 <> "}"))
  end

  def canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  def canonical_json(value) when is_binary(value), do: Jason.encode!(value)
  def canonical_json(value) when is_integer(value), do: Integer.to_string(value)
  def canonical_json(true), do: "true"
  def canonical_json(false), do: "false"
  def canonical_json(nil), do: "null"

  defp error(code, path), do: %{code: code, path: path}
end
