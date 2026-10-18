defmodule CadenceWeb.FrontendReleaseActivation do
  @moduledoc "The sole transactional writer for the v2 frontend release catalog."

  import Ecto.Changeset
  import Ecto.Query

  alias Cadence.Repo

  alias CadenceWeb.FrontendReleaseCatalog

  alias CadenceWeb.FrontendReleaseActivation.{
    CatalogBinding,
    CatalogGeneration,
    Control,
    Request
  }

  alias CadenceWeb.FrontendReleasePublication.{
    CatalogPublication,
    DatabaseArtifactStore,
    ReleaseArtifact,
    ReleaseObject,
    ReleasePublication
  }

  @process_publication_config_key {CadenceWeb.FrontendReleasePublication, :publication_config}
  @max_idempotency_key_bytes 128
  @snapshot_schema "cadence.first-party-frontend-release-persisted-snapshot.v1"
  @accepted_transitions ["initial", "legacy_successor", "promotion", "rollback"]

  @type response :: %{
          required(:status) => 201 | 409 | 422 | 500 | 503,
          required(:body) => binary(),
          optional(:replay?) => boolean()
        }

  @spec activate_catalog(binary(), binary(), keyword()) ::
          {:ok, response()} | {:error, response() | map()}
  def activate_catalog(raw_document_bytes, raw_idempotency_key, opts \\ [])

  def activate_catalog(raw_document_bytes, raw_idempotency_key, opts) when is_list(opts) do
    started_at = System.monotonic_time()

    result =
      with :ok <- valid_raw_idempotency_key(raw_idempotency_key),
           {:ok, document_digest} <- document_digest(raw_document_bytes) do
        idempotency_key_digest = FrontendReleaseCatalog.digest(raw_idempotency_key)
        run_activation(raw_document_bytes, idempotency_key_digest, document_digest, opts)
      else
        {:error, failure} -> {:error, failure}
      end

    emit_activation_telemetry(result, raw_document_bytes, raw_idempotency_key, started_at)
    result
  end

  def activate_catalog(_document, _key, _opts),
    do: {:error, response_error(400, :malformed_body)}

  @doc "Build the exact persisted snapshot used for v2 snapshotDigest verification."
  @spec persisted_snapshot_digest(binary()) :: {:ok, binary()} | {:error, :not_found | :integrity}
  def persisted_snapshot_digest(catalog_publication_id) when is_binary(catalog_publication_id) do
    case Repo.get_by(CatalogGeneration, catalog_publication_id: catalog_publication_id) do
      %CatalogGeneration{} = generation ->
        case persisted_snapshot(catalog_publication_id, generation.generation_id) do
          {:ok, snapshot} ->
            {:ok, FrontendReleaseCatalog.digest(FrontendReleaseCatalog.canonical_json(snapshot))}

          failure ->
            failure
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp run_activation(
         raw_document_bytes,
         idempotency_key_digest,
         document_digest,
         opts
       ) do
    transaction_result =
      Repo.transaction(fn ->
        :ok = advisory_lock()
        control = locked_control!()
        request = locked_request(idempotency_key_digest)

        case request do
          %Request{} = row ->
            replay_or_conflict!(row, document_digest)

          nil ->
            activate_new(
              raw_document_bytes,
              idempotency_key_digest,
              document_digest,
              control,
              opts
            )
        end
      end)

    normalize_transaction_result(transaction_result)
  rescue
    error in [DBConnection.ConnectionError] ->
      {:error, response_error(503, :transient_persistence_failure, error)}

    error in [Postgrex.Error] ->
      if transient_database_failure?(error),
        do: {:error, response_error(503, :transient_persistence_failure, error)},
        else: {:error, response_error(500, :integrity_failure, error)}

    error in [Ecto.ConstraintError, Ecto.ChangeError] ->
      {:error, response_error(500, :integrity_failure, error)}
  end

  defp normalize_transaction_result({:ok, result}), do: normalize_transaction_success(result)
  defp normalize_transaction_result({:error, reason}), do: normalize_transaction_failure(reason)

  defp normalize_transaction_success({:ok, response}), do: {:ok, response}
  defp normalize_transaction_success({:error, response}), do: {:error, response}

  defp normalize_transaction_failure({:semantic, _failure}),
    do: {:error, response_error(500, :integrity_failure)}

  defp normalize_transaction_failure({:integrity, _reason}),
    do: {:error, response_error(500, :integrity_failure)}

  defp normalize_transaction_failure({:transient, _reason}),
    do: {:error, response_error(503, :transient_persistence_failure)}

  defp normalize_transaction_failure(%{} = failure), do: {:error, failure}

  defp normalize_transaction_failure(_reason),
    do: {:error, response_error(500, :integrity_failure)}

  defp activate_new(
         raw_document_bytes,
         idempotency_key_digest,
         document_digest,
         control,
         opts
       ) do
    keys = Keyword.get(publication_config(opts), :trust_records, [])

    case FrontendReleaseCatalog.verify_catalog_v2(
           raw_document_bytes,
           keys,
           verifier_opts(opts)
         ) do
      {:ok, verified} ->
        activate_verified(
          verified,
          raw_document_bytes,
          idempotency_key_digest,
          document_digest,
          control,
          opts
        )

      {:error, failure} ->
        insert_rejected_request!(
          idempotency_key_digest,
          document_digest,
          failure,
          Keyword.get(opts, :publisher_identity)
        )
    end
  end

  defp activate_verified(
         verified,
         raw_document_bytes,
         idempotency_key_digest,
         document_digest,
         control,
         opts
       ) do
    with {:ok, latest_catalog} <- locked_latest_catalog(),
         {:ok, latest_generation} <- locked_latest_generation(),
         {:ok, entries} <- reread_input_entries(verified.entries, opts),
         {:ok, state} <-
           validate_transition(
             verified,
             entries,
             latest_catalog,
             latest_generation,
             control,
             opts
           ),
         {:ok, catalog} <- insert_catalog(verified, raw_document_bytes, entries),
         {:ok, generation} <- insert_generation(verified, catalog, state),
         :ok <- insert_bindings(verified.entries, entries, generation, state),
         :ok <- cut_over_if_required(control, state),
         {:ok, snapshot} <- persisted_snapshot(catalog.publication_id, generation.generation_id),
         :ok <- exact_snapshot_digest(snapshot, verified.snapshot_digest),
         response <- accepted_response(verified, catalog, generation),
         :ok <-
           insert_accepted_request(response, idempotency_key_digest, document_digest, state, opts) do
      {:ok, response}
    else
      {:error, %{code: _code} = failure} ->
        insert_rejected_request!(
          idempotency_key_digest,
          document_digest,
          failure,
          Keyword.get(opts, :publisher_identity)
        )

      {:error, :integrity} ->
        Repo.rollback({:integrity, :persisted_state_mismatch})

      {:error, :snapshot_integrity} ->
        Repo.rollback({:integrity, :snapshot_digest_mismatch})

      {:error, {:persistence, reason}} ->
        Repo.rollback({:integrity, reason})

      {:error, {:transient, reason}} ->
        Repo.rollback({:transient, reason})

      {:error, reason} ->
        Repo.rollback({:integrity, reason})
    end
  end

  defp reread_input_entries(entries, opts) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      path = "$.payload.entries[#{index}]"

      with {:ok, current} <-
             reread_release(
               entry.current_envelope,
               entry.current,
               path <> ".current",
               opts
             ),
           {:ok, fallback} <-
             reread_optional_release(
               entry.fallback_envelope,
               entry.fallback,
               path <> ".fallback",
               opts
             ) do
        {:cont, {:ok, [%{entry: entry, current: current, fallback: fallback} | acc]}}
      else
        {:error, :integrity} -> {:halt, {:error, :integrity}}
        {:error, _} = failure -> {:halt, failure}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      failure -> failure
    end
  end

  defp reread_optional_release(nil, nil, _path, _opts), do: {:ok, nil}

  defp reread_optional_release(envelope, release, path, opts)
       when is_map(envelope) and is_map(release),
       do: reread_release(envelope, release, path, opts)

  defp reread_optional_release(_envelope, _release, _path, _opts),
    do: {:error, :integrity}

  defp reread_release(envelope, release, path, _opts) do
    expected_payload_bytes = FrontendReleaseCatalog.canonical_json(release)
    expected_document_bytes = FrontendReleaseCatalog.canonical_json(envelope)
    release_id = release["releaseId"]

    row =
      ReleasePublication
      |> where([publication], publication.release_id == ^release_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    with %ReleasePublication{} = row <- row,
         true <- row.acceptance_state == "accepted",
         true <- row.release_id == release_id,
         true <- row.payload_bytes == expected_payload_bytes,
         true <- row.payload_digest == FrontendReleaseCatalog.digest(expected_payload_bytes),
         true <- row.signed_document_bytes == expected_document_bytes,
         true <-
           row.signed_document_digest == FrontendReleaseCatalog.digest(expected_document_bytes),
         :ok <- release_identity_matches?(row, release),
         :ok <- release_security_metadata_matches?(row, envelope, release),
         :ok <- release_manifest_matches?(row, release),
         {:ok, artifacts} <- reread_artifacts(row, release, path) do
      {:ok,
       %{
         row: row,
         release: release,
         envelope: envelope,
         publication_id: row.publication_id,
         release_id: row.release_id,
         artifacts: artifacts
       }}
    else
      nil -> {:error, :integrity}
      false -> {:error, :integrity}
      {:error, :integrity} -> {:error, :integrity}
      {:error, _} = failure -> failure
    end
  end

  defp release_identity_matches?(row, release) do
    if release_identity_fields_match?(row, release) and release_metadata_matches?(row, release),
      do: :ok,
      else: {:error, :integrity}
  end

  defp release_identity_fields_match?(row, release) do
    row.application_id == release["application"]["id"] and
      row.application_version == release["application"]["version"] and
      row.package_id == release["package"]["id"] and
      row.package_version == release["package"]["version"] and
      row.surface_id == release["surface"]["id"] and
      row.surface_version == release["surface"]["version"]
  end

  defp release_metadata_matches?(row, release) do
    row.remote_name == release["remoteName"] and
      row.exposed_module == release["exposedModule"] and
      row.artifact_base_url == release["artifactBaseUrl"] and
      row.artifact_count == length(release["artifacts"])
  end

  defp release_security_metadata_matches?(row, envelope, release) do
    if row.signing_key_id == envelope["keyId"] and
         row.signing_role == envelope["signingRole"] and
         row.released_at == persisted_release_datetime(release["releasedAt"]) and
         row.provenance == release["provenance"] do
      :ok
    else
      {:error, :integrity}
    end
  end

  defp persisted_release_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        DateTime.from_unix!(DateTime.to_unix(datetime, :microsecond), :microsecond)

      _ ->
        nil
    end
  end

  defp persisted_release_datetime(_value), do: nil

  defp release_manifest_matches?(row, release) do
    manifest = release["manifest"]

    if row.manifest_path == manifest["path"] and row.manifest_sha256 == manifest["sha256"] and
         row.manifest_size == manifest["size"] and
         row.manifest_media_type == manifest["mediaType"] do
      :ok
    else
      {:error, :integrity}
    end
  end

  defp reread_artifacts(row, release, path) do
    persisted =
      ReleaseArtifact
      |> where([artifact], artifact.release_publication_id == ^row.publication_id)
      |> order_by([artifact], asc: artifact.path)
      |> Repo.all()

    declarations = Map.new(release["artifacts"], &{&1["path"], &1})

    cond do
      length(persisted) != length(release["artifacts"]) -> {:error, :integrity}
      Map.keys(declarations) != Enum.map(persisted, & &1.path) -> {:error, :integrity}
      true -> reread_artifact_rows(persisted, declarations, path, row.release_id)
    end
  end

  defp reread_artifact_rows(rows, declarations, _path, release_id) do
    rows
    |> Enum.reduce_while({:ok, []}, fn artifact, {:ok, acc} ->
      declaration = Map.get(declarations, artifact.path)

      with true <- is_map(declaration),
           true <- artifact.release_id == release_id,
           true <- artifact.path == declaration["path"],
           true <- artifact.sha256 == declaration["sha256"],
           true <- artifact.size == declaration["size"],
           true <- artifact.media_type == declaration["mediaType"],
           true <- artifact.object_key == "sha256:" <> artifact.sha256,
           {:ok, object} <- reread_object(artifact.sha256, artifact.size) do
        {:cont, {:ok, [%{artifact: artifact, object: object} | acc]}}
      else
        false -> {:halt, {:error, :integrity}}
        {:error, :integrity} -> {:halt, {:error, :integrity}}
        {:error, {:transient, _reason} = failure} -> {:halt, {:error, failure}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      failure -> failure
    end
  end

  defp reread_object(sha256, size) do
    case Repo.get(ReleaseObject, sha256) do
      %ReleaseObject{sha256: ^sha256, size: ^size, bytes: bytes} when is_binary(bytes) ->
        if FrontendReleaseCatalog.digest(bytes) == "sha256:" <> sha256,
          do: {:ok, %{sha256: sha256, size: size}},
          else: {:error, :integrity}

      %ReleaseObject{sha256: ^sha256, size: ^size, bytes: nil} ->
        verify_chunk_backed_object(sha256, size)

      _ ->
        {:error, :integrity}
    end
  end

  defp verify_chunk_backed_object(sha256, size) do
    case DatabaseArtifactStore.verify("sha256:" <> sha256, size) do
      :ok ->
        {:ok, %{sha256: sha256, size: size}}

      {:error, reason} ->
        if transient_artifact_store_failure?(reason) do
          {:error, {:transient, reason}}
        else
          {:error, :integrity}
        end

      _other ->
        {:error, :integrity}
    end
  end

  defp transient_artifact_store_failure?({operation, reason})
       when operation in [:object_metadata, :object_chunk],
       do: transient_database_failure?(reason)

  defp transient_artifact_store_failure?(reason), do: transient_database_failure?(reason)

  defp validate_transition(verified, entries, latest_catalog, latest_generation, control, opts) do
    transition = verified.transition

    cond do
      transition == "initial" ->
        validate_initial(verified, entries, latest_catalog, latest_generation, control)

      transition == "legacy_successor" ->
        validate_legacy_successor(
          verified,
          entries,
          latest_catalog,
          latest_generation,
          control,
          opts
        )

      transition in ["promotion", "rollback"] ->
        validate_generation_successor(
          verified,
          entries,
          latest_catalog,
          latest_generation,
          control
        )

      true ->
        {:error, semantic_error(:invalid_transition, "$.payload.transition")}
    end
  end

  defp validate_initial(verified, entries, latest_catalog, latest_generation, control) do
    cond do
      control.cutover_epoch != 0 or latest_catalog != nil or latest_generation != nil ->
        {:error, semantic_error(:invalid_state_transition, "$.payload.transition")}

      verified.sequence != 1 ->
        {:error, semantic_error(:invalid_sequence, "$.payload.sequence")}

      Enum.any?(entries, &(&1.fallback != nil)) ->
        {:error, semantic_error(:fallback_forbidden, "$.payload.entries")}

      true ->
        {:ok,
         %{
           predecessor_kind: "none",
           predecessor_catalog_publication_id: nil,
           previous: %{},
           cutover?: true,
           legacy_catalog_publication_id: nil
         }}
    end
  end

  defp validate_legacy_successor(
         verified,
         entries,
         latest_catalog,
         latest_generation,
         control,
         opts
       ) do
    with true <- control.cutover_epoch == 0,
         true <- latest_generation == nil,
         %CatalogPublication{} = legacy <- latest_catalog,
         true <- is_nil(legacy.transition),
         {:ok, legacy_entries} <- revalidate_legacy_catalog(legacy, opts),
         :ok <- successor_sequence(verified, legacy),
         :ok <- successor_publication_time(verified, legacy),
         :ok <- exact_successor_entries(entries, legacy_entries, :legacy) do
      {:ok,
       %{
         predecessor_kind: "legacy",
         predecessor_catalog_publication_id: legacy.publication_id,
         previous: previous_map(legacy_entries),
         cutover?: true,
         legacy_catalog_publication_id: legacy.publication_id
       }}
    else
      false -> {:error, semantic_error(:invalid_state_transition, "$.payload.transition")}
      {:error, %{code: _} = failure} -> {:error, failure}
      {:error, :integrity} -> {:error, :integrity}
      _ -> {:error, semantic_error(:legacy_predecessor_required, "$.payload.transition")}
    end
  end

  defp validate_generation_successor(
         verified,
         entries,
         latest_catalog,
         latest_generation,
         control
       ) do
    with true <- control.cutover_epoch > 0,
         %CatalogPublication{} = previous_catalog <- latest_catalog,
         %CatalogGeneration{} = generation <- latest_generation,
         true <- previous_catalog.publication_id == generation.catalog_publication_id,
         :ok <- successor_sequence(verified, previous_catalog),
         :ok <- successor_publication_time(verified, previous_catalog),
         {:ok, previous_entries} <- persisted_generation_entries(generation),
         :ok <- exact_generation_transition(verified.transition, entries, previous_entries) do
      {:ok,
       %{
         predecessor_kind: "generation",
         predecessor_catalog_publication_id: generation.catalog_publication_id,
         previous: previous_map(previous_entries),
         cutover?: false,
         legacy_catalog_publication_id: nil
       }}
    else
      false -> {:error, semantic_error(:invalid_state_transition, "$.payload.transition")}
      {:error, %{code: _} = failure} -> {:error, failure}
      {:error, :integrity} -> {:error, :integrity}
      _ -> {:error, semantic_error(:generation_predecessor_required, "$.payload.transition")}
    end
  end

  defp revalidate_legacy_catalog(legacy, opts) do
    keys = Keyword.get(publication_config(opts), :trust_records, [])
    verifier_opts = Keyword.put(verifier_opts(opts), :now, legacy.published_at)

    with true <-
           legacy.transition == nil and legacy.identity_count == nil and
             legacy.snapshot_digest == nil,
         true <-
           legacy.signed_document_digest ==
             FrontendReleaseCatalog.digest(legacy.signed_document_bytes),
         {:ok, verified} <-
           FrontendReleaseCatalog.verify_catalog(
             legacy.signed_document_bytes,
             keys,
             verifier_opts
           ),
         true <- verified.payload_bytes == legacy.payload_bytes,
         true <- verified.digest == legacy.catalog_digest,
         {:ok, raw_catalog} <- Jason.decode(legacy.payload_bytes),
         {:ok, entries} <- legacy_persisted_entries(raw_catalog, verified.entries) do
      {:ok, entries}
    else
      false -> {:error, :integrity}
      {:error, _} -> {:error, :integrity}
      _ -> {:error, :integrity}
    end
  end

  defp legacy_persisted_entries(%{"entries" => raw_entries}, verified_entries)
       when is_list(raw_entries) do
    raw_entries
    |> Enum.zip(verified_entries)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{raw_entry, verified_entry}, index}, {:ok, acc} ->
      path = "$.payload.entries[#{index}]"

      with {:ok, current} <-
             reread_release(raw_entry["current"], verified_entry.current, path <> ".current", []),
           {:ok, fallback} <-
             reread_optional_release(
               raw_entry["fallback"],
               verified_entry.fallback,
               path <> ".fallback",
               []
             ) do
        {:cont,
         {:ok,
          [
            %{identity: verified_entry.identity, current: current, fallback: fallback}
            | acc
          ]}}
      else
        _ -> {:halt, {:error, :integrity}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      failure -> failure
    end
  end

  defp legacy_persisted_entries(_catalog, _entries), do: {:error, :integrity}

  defp persisted_generation_entries(generation) do
    bindings =
      CatalogBinding
      |> where([binding], binding.generation_id == ^generation.generation_id)
      |> order_by(
        [
          binding
        ],
        asc: binding.application_id,
        asc: binding.application_version,
        asc: binding.package_id,
        asc: binding.package_version,
        asc: binding.surface_id,
        asc: binding.surface_version
      )
      |> Repo.all()

    if length(bindings) != generation.identity_count or bindings == [],
      do: {:error, :integrity},
      else: read_generation_bindings(bindings)
  end

  defp read_generation_bindings(bindings) do
    bindings
    |> Enum.reduce_while({:ok, MapSet.new(), []}, &read_generation_binding/2)
    |> case do
      {:ok, _identities, entries} -> {:ok, Enum.reverse(entries)}
      failure -> failure
    end
  end

  defp read_generation_binding(binding, state),
    do: read_binding(binding, state, &generation_entry/3)

  defp generation_entry(binding, current, previous),
    do: %{identity: binding_identity(binding), current: current, fallback: previous}

  defp reread_persisted_pair(publication_id, release_id)
       when is_binary(publication_id) and is_binary(release_id) do
    query =
      from(publication in ReleasePublication,
        where:
          publication.publication_id == ^publication_id and publication.release_id == ^release_id,
        lock: "FOR UPDATE"
      )

    case Repo.one(query) do
      %ReleasePublication{} = row ->
        release = Jason.decode!(row.payload_bytes)
        envelope = Jason.decode!(row.signed_document_bytes)
        reread_release(envelope, release, "$.persisted", [])

      _ ->
        {:error, :integrity}
    end
  rescue
    _ -> {:error, :integrity}
  end

  defp reread_optional_pair(nil, nil), do: {:ok, nil}

  defp reread_optional_pair(publication_id, release_id),
    do: reread_persisted_pair(publication_id, release_id)

  defp binding_matches_release?(binding, %{row: row}) do
    if binding.application_id == row.application_id and
         binding.application_version == row.application_version and
         binding.package_id == row.package_id and
         binding.package_version == row.package_version and
         binding.surface_id == row.surface_id and
         binding.surface_version == row.surface_version do
      :ok
    else
      {:error, :integrity}
    end
  end

  defp binding_identity(binding) do
    %{
      "application" => %{"id" => binding.application_id, "version" => binding.application_version},
      "package" => %{"id" => binding.package_id, "version" => binding.package_version},
      "surface" => %{"id" => binding.surface_id, "version" => binding.surface_version}
    }
  end

  defp exact_successor_entries(entries, previous_entries, _kind) do
    previous = previous_map(previous_entries)

    results =
      Enum.map(entries, fn %{entry: entry, current: current, fallback: fallback} ->
        prior = Map.get(previous, identity_key(entry.identity))

        (prior &&
           current.release_id != prior.current.release_id) and
          exact_release_pair?(fallback, prior.current) and
          true
      end)

    if length(entries) == length(previous_entries) and Enum.all?(results),
      do: :ok,
      else: {:error, semantic_error(:invalid_state_transition, "$.payload.entries")}
  end

  defp exact_generation_transition("promotion", entries, previous_entries) do
    previous = previous_map(previous_entries)

    values =
      Enum.map(entries, fn %{entry: entry, current: current, fallback: fallback} ->
        prior = Map.get(previous, identity_key(entry.identity))

        prior && current.release_id != prior.current.release_id &&
          exact_release_pair?(fallback, prior.current)
      end)

    rollback_count =
      Enum.count(entries, fn %{entry: entry, current: current} ->
        prior = Map.get(previous, identity_key(entry.identity))
        prior && prior.fallback != nil && current.release_id == prior.fallback.release_id
      end)

    cond do
      length(entries) != length(previous_entries) or not Enum.all?(values) ->
        {:error, semantic_error(:invalid_state_transition, "$.payload.entries")}

      rollback_count > 0 ->
        {:error, semantic_error(:mixed_transition, "$.payload.transition")}

      true ->
        :ok
    end
  end

  defp exact_generation_transition("rollback", entries, previous_entries) do
    previous = previous_map(previous_entries)

    values =
      Enum.map(entries, fn %{entry: entry, current: current, fallback: fallback} ->
        prior = Map.get(previous, identity_key(entry.identity))

        prior && prior.fallback != nil && current.release_id == prior.fallback.release_id &&
          exact_release_pair?(fallback, prior.current)
      end)

    if length(entries) == length(previous_entries) and Enum.all?(values),
      do: :ok,
      else: {:error, semantic_error(:rollback_previous_required, "$.payload.entries")}
  end

  defp exact_generation_transition(_transition, _entries, _previous),
    do: {:error, semantic_error(:invalid_transition, "$.payload.transition")}

  defp exact_release_pair?(nil, _right), do: false

  defp exact_release_pair?(left, right) do
    left.release_id == right.release_id and
      left.row.publication_id == right.row.publication_id and
      left.row.signed_document_bytes == right.row.signed_document_bytes
  end

  defp previous_map(entries),
    do: Map.new(entries, fn entry -> {identity_key(entry.identity), entry} end)

  defp identity_key(%{"application" => application, "package" => package, "surface" => surface}),
    do:
      {application["id"], application["version"], package["id"], package["version"],
       surface["id"], surface["version"]}

  defp successor_sequence(verified, previous) do
    if verified.sequence == previous.sequence + 1,
      do: :ok,
      else: {:error, semantic_error(:invalid_sequence, "$.payload.sequence")}
  end

  defp successor_publication_time(verified, previous) do
    previous_ms = DateTime.to_unix(previous.published_at, :millisecond)

    if verified.published_at > previous_ms,
      do: :ok,
      else: {:error, semantic_error(:non_monotonic_publication, "$.payload.publishedAt")}
  end

  defp insert_catalog(verified, raw_document_bytes, entries) do
    signed_document_digest = FrontendReleaseCatalog.digest(raw_document_bytes)

    attrs = %{
      publication_id:
        deterministic_id("frontend_release_catalog_publication", raw_document_bytes),
      sequence: verified.sequence,
      catalog_digest: FrontendReleaseCatalog.digest(verified.payload_bytes),
      signed_document_digest: signed_document_digest,
      signed_document_bytes: raw_document_bytes,
      payload_bytes: verified.payload_bytes,
      signing_key_id: verified.key_id,
      signing_role: verified.signing_role,
      published_at: datetime_from_ms(verified.published_at),
      expires_at: datetime_from_ms(verified.expires_at),
      transition: verified.transition,
      identity_count: verified.identity_count,
      snapshot_digest: verified.snapshot_digest,
      acceptance_state: "accepted",
      accepted_state: accepted_state(verified),
      release_references: release_references(entries),
      accepted_at: DateTime.utc_now(),
      metadata: %{}
    }

    case Repo.insert(CatalogPublication.changeset(attrs)) do
      {:ok, row} -> {:ok, row}
      {:error, changeset} -> {:error, {:persistence, changeset}}
    end
  end

  defp accepted_state(verified) do
    %{
      "sequence" => verified.sequence,
      "publishedAt" => verified.catalog["publishedAt"],
      "digest" => verified.digest,
      "entries" => Enum.map(verified.entries, &state_entry/1)
    }
  end

  defp state_entry(entry) do
    value = %{"identity" => entry.identity, "current" => entry.current}
    if entry.fallback, do: Map.put(value, "fallback", entry.fallback), else: value
  end

  defp release_references(entries) do
    %{
      "entries" =>
        Enum.map(entries, fn %{entry: entry, current: current, fallback: fallback} ->
          value = %{
            "identity" => entry.identity,
            "currentReleaseId" => current.release_id,
            "currentDigest" => current.row.payload_digest,
            "currentSignedDocumentDigest" => current.row.signed_document_digest
          }

          if fallback,
            do:
              Map.merge(value, %{
                "fallbackReleaseId" => fallback.release_id,
                "fallbackDigest" => fallback.row.payload_digest,
                "fallbackSignedDocumentDigest" => fallback.row.signed_document_digest
              }),
            else: value
        end)
    }
  end

  defp insert_generation(verified, catalog, state) do
    generation_identity = %{
      "catalogPublicationId" => catalog.publication_id,
      "identityCount" => verified.identity_count,
      "predecessorCatalogPublicationId" => state.predecessor_catalog_publication_id,
      "predecessorKind" => state.predecessor_kind,
      "sequence" => verified.sequence,
      "snapshotDigest" => verified.snapshot_digest,
      "transition" => verified.transition
    }

    attrs = %{
      generation_id:
        deterministic_id(
          "frontend_release_catalog_generation",
          FrontendReleaseCatalog.canonical_json(generation_identity)
        ),
      catalog_publication_id: catalog.publication_id,
      sequence: verified.sequence,
      identity_count: verified.identity_count,
      predecessor_kind: state.predecessor_kind,
      predecessor_catalog_publication_id: state.predecessor_catalog_publication_id,
      inserted_at: DateTime.utc_now()
    }

    case Repo.insert(CatalogGeneration.changeset(attrs)) do
      {:ok, row} -> {:ok, row}
      {:error, changeset} -> {:error, {:persistence, changeset}}
    end
  end

  defp insert_bindings(raw_entries, entries, generation, state) do
    entries
    |> Enum.zip(raw_entries)
    |> Enum.reduce_while(:ok, fn {%{entry: entry, current: current}, _raw_entry}, :ok ->
      previous = Map.get(state.previous, identity_key(entry.identity))
      identity = entry.identity

      attrs = %{
        generation_id: generation.generation_id,
        application_id: identity["application"]["id"],
        application_version: identity["application"]["version"],
        package_id: identity["package"]["id"],
        package_version: identity["package"]["version"],
        surface_id: identity["surface"]["id"],
        surface_version: identity["surface"]["version"],
        current_publication_id: current.row.publication_id,
        current_release_id: current.release_id,
        previous_publication_id: previous && previous.current.row.publication_id,
        previous_release_id: previous && previous.current.release_id,
        inserted_at: DateTime.utc_now()
      }

      case Repo.insert(CatalogBinding.changeset(attrs)) do
        {:ok, _row} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, {:persistence, changeset}}}
      end
    end)
  end

  defp cut_over_if_required(_control, %{cutover?: false}), do: :ok

  defp cut_over_if_required(control, state) do
    attrs = %{
      cutover_epoch: 1,
      cutover_at: DateTime.utc_now(),
      legacy_catalog_publication_id: state.legacy_catalog_publication_id
    }

    case Repo.update(change(control, attrs)) do
      {:ok, _row} -> :ok
      {:error, changeset} -> {:error, {:persistence, changeset}}
    end
  end

  defp persisted_snapshot(catalog_publication_id, generation_id) do
    catalog = Repo.get(CatalogPublication, catalog_publication_id)

    cond do
      catalog == nil ->
        {:error, :not_found}

      generation_id == nil ->
        {:error, :integrity}

      true ->
        case Repo.get_by(CatalogGeneration, generation_id: generation_id) do
          %CatalogGeneration{} = generation -> build_persisted_snapshot(catalog, generation)
          _ -> {:error, :integrity}
        end
    end
  end

  defp build_persisted_snapshot(catalog, generation) do
    bindings =
      CatalogBinding
      |> where([binding], binding.generation_id == ^generation.generation_id)
      |> order_by(
        [
          binding
        ],
        asc: binding.application_id,
        asc: binding.application_version,
        asc: binding.package_id,
        asc: binding.package_version,
        asc: binding.surface_id,
        asc: binding.surface_version
      )
      |> Repo.all()

    cond do
      length(bindings) != generation.identity_count -> {:error, :integrity}
      generation.catalog_publication_id != catalog.publication_id -> {:error, :integrity}
      true -> build_snapshot_from_bindings(catalog, bindings)
    end
  end

  defp build_snapshot_from_bindings(catalog, bindings) do
    case read_snapshot_bindings(bindings) do
      {:ok, entries} ->
        {:ok,
         %{
           "schema" => @snapshot_schema,
           "sequence" => catalog.sequence,
           "publishedAt" => format_datetime(catalog.published_at),
           "expiresAt" => format_datetime(catalog.expires_at),
           "transition" => catalog.transition,
           "identityCount" => catalog.identity_count,
           "entries" => Enum.reverse(entries)
         }}

      failure ->
        failure
    end
  end

  defp read_snapshot_bindings(bindings) do
    Enum.reduce_while(bindings, {:ok, MapSet.new(), []}, &read_snapshot_binding/2)
    |> case do
      {:ok, _identities, entries} -> {:ok, entries}
      failure -> failure
    end
  end

  defp read_snapshot_binding(binding, state),
    do: read_binding(binding, state, &snapshot_entry/3)

  defp read_binding(binding, {:ok, identities, acc}, entry_builder) do
    identity_key = binding_identity_key(binding)

    case MapSet.member?(identities, identity_key) do
      true -> {:halt, {:error, :integrity}}
      false -> reread_binding(binding, identity_key, identities, acc, entry_builder)
    end
  end

  defp reread_binding(binding, identity_key, identities, acc, entry_builder) do
    with {:ok, current} <-
           reread_persisted_pair(binding.current_publication_id, binding.current_release_id),
         {:ok, previous} <-
           reread_optional_pair(binding.previous_publication_id, binding.previous_release_id),
         :ok <- binding_matches_release?(binding, current) do
      {:cont,
       {:ok, MapSet.put(identities, identity_key),
        [entry_builder.(binding, current, previous) | acc]}}
    else
      _ -> {:halt, {:error, :integrity}}
    end
  end

  defp binding_identity_key(binding) do
    {binding.generation_id, binding.application_id, binding.application_version,
     binding.package_id, binding.package_version, binding.surface_id, binding.surface_version}
  end

  defp snapshot_entry(binding, current, previous) do
    %{
      "identity" => binding_identity(binding),
      "current" => snapshot_release(current),
      "previous" => if(previous, do: snapshot_release(previous), else: nil)
    }
  end

  defp snapshot_release(%{row: row, release: _release}) do
    %{
      "releaseId" => row.release_id,
      "payloadDigest" => row.payload_digest,
      "signedDocumentDigest" => row.signed_document_digest,
      "identity" => %{
        "application" => %{"id" => row.application_id, "version" => row.application_version},
        "package" => %{"id" => row.package_id, "version" => row.package_version},
        "surface" => %{"id" => row.surface_id, "version" => row.surface_version}
      },
      "remoteName" => row.remote_name,
      "exposedModule" => row.exposed_module,
      "artifactBaseUrl" => row.artifact_base_url,
      "manifest" => %{
        "path" => row.manifest_path,
        "sha256" => row.manifest_sha256,
        "size" => row.manifest_size,
        "mediaType" => row.manifest_media_type
      },
      "signingKeyId" => row.signing_key_id,
      "signingRole" => row.signing_role,
      "releasedAt" => format_datetime(row.released_at),
      "artifactCount" => row.artifact_count,
      "provenance" => row.provenance
    }
  end

  defp exact_snapshot_digest(snapshot, expected) do
    actual = FrontendReleaseCatalog.digest(FrontendReleaseCatalog.canonical_json(snapshot))
    if actual == expected, do: :ok, else: {:error, :snapshot_integrity}
  end

  defp accepted_response(verified, catalog, generation) do
    data = %{
      "catalogPublicationId" => catalog.publication_id,
      "generationId" => generation.generation_id,
      "identityCount" => verified.identity_count,
      "outcome" => verified.transition,
      "sequence" => verified.sequence,
      "status" => "activated"
    }

    %{
      status: 201,
      body: canonical_response(%{"data" => data}),
      outcome: verified.transition,
      sequence: verified.sequence,
      identity_count: verified.identity_count,
      catalog_publication_id: catalog.publication_id,
      generation_id: generation.generation_id,
      replay?: false
    }
  end

  defp insert_accepted_request(response, idempotency_key_digest, document_digest, _state, opts) do
    attrs = %{
      request_id: activation_request_id(idempotency_key_digest, document_digest),
      idempotency_key_digest: idempotency_key_digest,
      document_digest: document_digest,
      outcome: state_outcome(response),
      response_status: response.status,
      response_body: response.body,
      catalog_publication_id: response.catalog_publication_id,
      generation_id: response.generation_id,
      publisher_identity: Keyword.get(opts, :publisher_identity),
      inserted_at: DateTime.utc_now()
    }

    case Repo.insert(Request.changeset(attrs)) do
      {:ok, _row} -> :ok
      {:error, changeset} -> {:error, {:persistence, changeset}}
    end
  end

  defp state_outcome(%{outcome: outcome}) when outcome in @accepted_transitions, do: outcome

  defp insert_rejected_request!(
         idempotency_key_digest,
         document_digest,
         failure,
         publisher_identity
       ) do
    {code, path} = failure_code_path(failure)
    body = canonical_response(%{"error" => %{"code" => stable_code(code), "path" => path}})

    attrs = %{
      request_id: activation_request_id(idempotency_key_digest, document_digest),
      idempotency_key_digest: idempotency_key_digest,
      document_digest: document_digest,
      outcome: "rejected",
      response_status: 422,
      response_body: body,
      catalog_publication_id: nil,
      generation_id: nil,
      publisher_identity: publisher_identity,
      inserted_at: DateTime.utc_now()
    }

    case Repo.insert(Request.changeset(attrs)) do
      {:ok, _row} ->
        {:ok,
         %{status: 422, body: body, outcome: "rejected", code: code, path: path, replay?: false}}

      {:error, changeset} ->
        Repo.rollback({:integrity, {:request_ledger, changeset}})
    end
  end

  defp replay_or_conflict!(row, document_digest) do
    if row.document_digest == document_digest do
      {:ok,
       %{
         status: row.response_status,
         body: row.response_body,
         outcome: row.outcome,
         catalog_publication_id: row.catalog_publication_id,
         generation_id: row.generation_id,
         replay?: true
       }}
    else
      {:error,
       response_error(
         409,
         :idempotency_key_reused,
         nil,
         canonical_response(%{"error" => %{"code" => "idempotency_key_reused"}})
       )}
    end
  end

  defp locked_control! do
    case Control
         |> where([control], control.control_id == 1)
         |> lock("FOR UPDATE")
         |> Repo.one() do
      %Control{} = control -> control
      _ -> Repo.rollback({:integrity, :missing_activation_control})
    end
  end

  defp locked_request(idempotency_key_digest) do
    Request
    |> where([request], request.idempotency_key_digest == ^idempotency_key_digest)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp locked_latest_catalog do
    row =
      CatalogPublication
      |> where([catalog], catalog.acceptance_state == "accepted")
      |> order_by([catalog], desc: catalog.sequence)
      |> limit(1)
      |> lock("FOR UPDATE")
      |> Repo.one()

    {:ok, row}
  end

  defp locked_latest_generation do
    row =
      CatalogGeneration
      |> order_by([generation], desc: generation.sequence)
      |> limit(1)
      |> lock("FOR UPDATE")
      |> Repo.one()

    {:ok, row}
  end

  defp advisory_lock do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended('frontend-release-catalog', 0))")
    :ok
  end

  defp valid_raw_idempotency_key(value)
       when is_binary(value) and byte_size(value) >= 1 and
              byte_size(value) <= @max_idempotency_key_bytes,
       do: :ok

  defp valid_raw_idempotency_key(_value),
    do: {:error, response_error(400, :malformed_idempotency_key)}

  defp document_digest(value) when is_binary(value),
    do: {:ok, FrontendReleaseCatalog.digest(value)}

  defp document_digest(_value), do: {:error, response_error(400, :malformed_body)}

  defp verifier_opts(opts) do
    config = publication_config(opts)

    base = [
      allowed_origins:
        Keyword.get(opts, :allowed_origins, Keyword.get(config, :allowed_origins, []))
    ]

    case Keyword.fetch(opts, :now) do
      {:ok, now} -> Keyword.put(base, :now, now)
      :error -> base
    end
  end

  defp publication_config(opts) do
    case Keyword.fetch(opts, :publication_config) do
      {:ok, config} when is_list(config) ->
        config

      {:ok, _} ->
        []

      :error ->
        process_or_application_publication_config()
    end
  end

  defp process_or_application_publication_config do
    case Process.get(@process_publication_config_key, :not_configured) do
      config when is_list(config) -> config
      _ -> application_publication_config()
    end
  end

  defp application_publication_config do
    case Application.get_env(:cadence_web, :frontend_release_publication, []) do
      config when is_list(config) -> config
      _ -> []
    end
  end

  defp datetime_from_ms(milliseconds) do
    milliseconds
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.truncate(:microsecond)
  end

  defp format_datetime(%DateTime{} = value) do
    value = DateTime.from_unix!(DateTime.to_unix(value, :microsecond), :microsecond)
    Calendar.strftime(value, "%Y-%m-%dT%H:%M:%S.%fZ")
  end

  defp canonical_response(value), do: FrontendReleaseCatalog.canonical_json(value)

  defp failure_code_path(%{code: code, path: path}), do: {code, path}
  defp failure_code_path(_failure), do: {:invalid_state, "$.payload"}

  defp stable_code(code) when is_atom(code), do: Atom.to_string(code)
  defp stable_code(code) when is_binary(code), do: code
  defp stable_code(_code), do: "invalid_state"

  defp activation_request_id(idempotency_key_digest, document_digest) do
    deterministic_id(
      "frontend_release_activation_request",
      FrontendReleaseCatalog.canonical_json(%{
        "documentDigest" => document_digest,
        "idempotencyKeyDigest" => idempotency_key_digest
      })
    )
  end

  defp deterministic_id(prefix, canonical_bytes)
       when is_binary(prefix) and is_binary(canonical_bytes),
       do: prefix <> "_" <> digest_hex(canonical_bytes)

  defp digest_hex(bytes),
    do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp semantic_error(code, path), do: %{code: code, path: path}

  defp response_error(status, code, reason \\ nil, body \\ nil) do
    %{
      status: status,
      code: code,
      reason: reason,
      body: body || canonical_response(%{"error" => %{"code" => stable_code(code)}})
    }
  end

  defp transient_database_failure?(%Postgrex.Error{postgres: %{code: :admin_shutdown}}), do: true

  defp transient_database_failure?(%Postgrex.Error{postgres: %{code: :connection_failure}}),
    do: true

  defp transient_database_failure?(%DBConnection.ConnectionError{}), do: true

  defp transient_database_failure?(_error), do: false

  defp emit_activation_telemetry(result, document, key, started_at) do
    response = response_from_result(result)
    duration = System.monotonic_time() - started_at

    document_digest = if is_binary(document), do: FrontendReleaseCatalog.digest(document)
    key_digest = if is_binary(key), do: FrontendReleaseCatalog.digest(key)
    outcome = response && Map.get(response, :outcome)
    status = response && Map.get(response, :status)

    metadata = %{
      request_id:
        deterministic_id(
          "frontend_release_activation_log",
          FrontendReleaseCatalog.canonical_json(%{
            "documentDigest" => document_digest,
            "keyDigest" => key_digest,
            "outcome" => outcome,
            "status" => status
          })
        ),
      outcome: outcome,
      status: status,
      document_digest: document_digest,
      key_digest: key_digest,
      transition: outcome,
      sequence: response && Map.get(response, :sequence),
      identity_count: response && Map.get(response, :identity_count),
      code: response && Map.get(response, :code)
    }

    :telemetry.execute(
      [:cadence_web, :frontend_release_activation, :complete],
      %{duration: System.convert_time_unit(duration, :native, :microsecond)},
      metadata
    )

    :ok
  end

  defp response_from_result({:ok, response}), do: response
  defp response_from_result({:error, response}) when is_map(response), do: response
  defp response_from_result(_result), do: nil
end
