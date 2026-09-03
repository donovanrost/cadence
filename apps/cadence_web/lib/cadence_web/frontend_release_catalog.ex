defmodule CadenceWeb.FrontendReleaseCatalog do
  @moduledoc """
  Closed-world, fail-closed v1 verification for signed first-party frontend releases.

  The module intentionally contains verification only. Release and promotion signing
  belongs to publication tooling; test fixtures use OTP's crypto API locally instead.
  """

  @envelope_schema "cadence.signed-frontend-document.v1"
  @release_schema "cadence.first-party-frontend-release.v1"
  @catalog_schema "cadence.first-party-frontend-release-catalog.v1"
  @catalog_v2_schema "cadence.first-party-frontend-release-catalog.v2"
  @algorithm "ed25519"
  @payload_encoding "base64url-json"
  @host_contract "cadence.application-host.v1"
  @vue_range "^3.5.40"

  @max_document_bytes 1_000_000
  @max_payload_bytes 750_000
  @max_encoded_payload_bytes 1_000_004
  @max_key_records 64
  @max_string_bytes 512
  @max_media_type_bytes 128
  @max_identifier_bytes 128
  @max_artifact_path_bytes 256
  @max_artifacts 2_048
  @max_catalog_entries 512
  @max_artifact_size 100_000_000
  @max_version 1_000
  @max_sequence 1_000_000_000
  @max_depth 16
  @max_object_members 64
  @max_array_items 4_096
  @max_catalog_lifetime_seconds 31 * 24 * 60 * 60

  @envelope_fields [
    "schema",
    "keyId",
    "algorithm",
    "signingRole",
    "payloadEncoding",
    "payload",
    "signature"
  ]

  @release_fields [
    "schema",
    "releaseId",
    "application",
    "package",
    "surface",
    "transport",
    "remoteName",
    "exposedModule",
    "artifactBaseUrl",
    "manifest",
    "artifacts",
    "hostCompatibility",
    "provenance",
    "releasedAt"
  ]

  @catalog_fields ["schema", "sequence", "publishedAt", "expiresAt", "entries"]
  @catalog_v2_fields [
    "schema",
    "transition",
    "sequence",
    "publishedAt",
    "expiresAt",
    "identityCount",
    "snapshotDigest",
    "entries"
  ]

  @type error :: %{code: atom(), path: String.t()}
  @type key_record :: map()

  def envelope_schema, do: @envelope_schema
  def release_schema, do: @release_schema
  def catalog_schema, do: @catalog_schema
  def catalog_v2_schema, do: @catalog_v2_schema

  @doc "Verify an envelope and its exact decoded UTF-8 payload bytes."
  @spec verify(binary() | map(), [key_record()] | map(), keyword()) ::
          {:ok, map()} | {:error, error()}
  def verify(document, key_records, opts \\ []) do
    verify_envelope(document, key_records, opts, nil)
  end

  @doc "Verify a release-role envelope and return the verified release."
  @spec verify_release(binary() | map(), [key_record()] | map(), keyword()) ::
          {:ok, map()} | {:error, error()}
  def verify_release(document, key_records, opts \\ []) do
    with {:ok, origins} <- allowed_origins(opts),
         {:ok, verified} <- verify_envelope(document, key_records, opts, "release"),
         {:ok, release} <- validate_release(verified.payload, "$.payload", origins) do
      {:ok,
       %{
         release: release,
         payload: verified.payload,
         payload_bytes: verified.payload_bytes,
         key_id: verified.key_id,
         signing_role: verified.signing_role,
         digest: digest(verified.payload_bytes)
       }}
    end
  end

  @doc "Verify a promotion catalog, every nested release envelope, and its admission state."
  @spec verify_catalog(binary() | map(), [key_record()] | map(), keyword()) ::
          {:ok, map()} | {:error, error()}
  def verify_catalog(document, key_records, opts \\ []) do
    with {:ok, origins} <- allowed_origins(opts),
         {:ok, verified} <- verify_envelope(document, key_records, opts, "promotion") do
      case verified.payload["schema"] do
        @catalog_v2_schema -> verify_catalog_v2_verified(verified, key_records, opts, origins)
        _ -> verify_catalog_v1_verified(verified, key_records, opts, origins)
      end
    end
  end

  @doc "Verify a v2 promotion catalog without performing persisted-state admission."
  @spec verify_catalog_v2(binary() | map(), [key_record()] | map(), keyword()) ::
          {:ok, map()} | {:error, error()}
  def verify_catalog_v2(document, key_records, opts \\ []) do
    with {:ok, origins} <- allowed_origins(opts),
         {:ok, verified} <- verify_envelope(document, key_records, opts, "promotion") do
      if verified.payload["schema"] == @catalog_v2_schema,
        do: verify_catalog_v2_verified(verified, key_records, opts, origins),
        else: {:error, error(:unknown_schema, "$.payload.schema")}
    end
  end

  defp verify_catalog_v1_verified(verified, key_records, opts, origins) do
    with {:ok, catalog} <- validate_catalog(verified.payload, key_records, opts, origins),
         {:ok, now_ms} <- verification_time(opts),
         :ok <- catalog_current(catalog, now_ms),
         catalog_digest = digest(verified.payload_bytes),
         {:ok, acceptance} <-
           admit_catalog(
             catalog,
             catalog_digest,
             Keyword.get(opts, :accepted_state),
             origins
           ) do
      accepted_state = %{
        "sequence" => catalog.sequence,
        "publishedAt" => catalog.payload["publishedAt"],
        "digest" => catalog_digest,
        "entries" => Enum.map(catalog.entries, &state_entry/1)
      }

      {:ok,
       %{
         catalog: verified.payload,
         entries: catalog.entries,
         digest: catalog_digest,
         payload_bytes: verified.payload_bytes,
         key_id: verified.key_id,
         signing_role: verified.signing_role,
         acceptance: acceptance,
         accepted_state: accepted_state
       }}
    end
  end

  defp verify_catalog_v2_verified(verified, key_records, opts, origins) do
    with {:ok, catalog} <- validate_catalog_v2(verified.payload, key_records, opts, origins),
         {:ok, now_ms} <- verification_time(opts),
         :ok <- catalog_current(catalog, now_ms) do
      {:ok,
       %{
         catalog: verified.payload,
         entries: catalog.entries,
         digest: digest(verified.payload_bytes),
         payload_bytes: verified.payload_bytes,
         key_id: verified.key_id,
         signing_role: verified.signing_role,
         transition: catalog.transition,
         sequence: catalog.sequence,
         published_at: catalog.published_at,
         expires_at: catalog.expires_at,
         identity_count: catalog.identity_count,
         snapshot_digest: catalog.snapshot_digest
       }}
    end
  end

  def verify_signed_frontend_document(document, key_records, opts \\ []),
    do: verify(document, key_records, opts)

  defp verify_envelope(document, key_records, opts, expected_role) do
    with {:ok, envelope} <- decode_document(document),
         :ok <- exact_fields(envelope, @envelope_fields, "$"),
         :ok <- exact_constant(envelope, "schema", @envelope_schema, :unknown_schema, "$.schema"),
         :ok <-
           exact_constant(envelope, "algorithm", @algorithm, :invalid_algorithm, "$.algorithm"),
         {:ok, role} <- role(Map.get(envelope, "signingRole"), "$.signingRole"),
         :ok <- expected_role(expected_role, role),
         :ok <-
           exact_constant(
             envelope,
             "payloadEncoding",
             @payload_encoding,
             :invalid_encoding,
             "$.payloadEncoding"
           ),
         :ok <- bounded_string(Map.get(envelope, "keyId"), "$.keyId"),
         :ok <- key_id(Map.get(envelope, "keyId"), "$.keyId"),
         {:ok, payload_bytes} <-
           decode_base64url(Map.get(envelope, "payload"), "$.payload", @max_encoded_payload_bytes),
         :ok <- exact_decoded_payload_size(payload_bytes, "$.payload"),
         {:ok, signature} <- decode_base64url(Map.get(envelope, "signature"), "$.signature", 256),
         :ok <- exact_binary_size(signature, 64, "$.signature"),
         :ok <- valid_utf8(payload_bytes, "$.payload"),
         {:ok, payload} <- decode_payload(payload_bytes),
         :ok <- payload_schema_for_role(payload, role),
         {:ok, keys} <- normalize_key_records(key_records),
         {:ok, now_ms} <- verification_time(opts),
         {:ok, key} <- find_key(keys, Map.get(envelope, "keyId")),
         :ok <- key_allows_role(key, role),
         :ok <- key_lifecycle(key, now_ms),
         :ok <- verify_signature(payload_bytes, signature, key["publicKeyBytes"]) do
      {:ok,
       %{
         payload: payload,
         payload_bytes: payload_bytes,
         key_id: Map.get(envelope, "keyId"),
         signing_role: role
       }}
    end
  end

  defp expected_role(nil, _role), do: :ok
  defp expected_role(expected, expected), do: :ok

  defp expected_role(_expected, _actual),
    do: {:error, error(:schema_role_mismatch, "$.signingRole")}

  defp decode_document(document) when is_map(document) do
    if plain_record?(document) do
      with :ok <- plain_json_tree(document, "$") do
        {:ok, document}
      end
    else
      {:error, error(:invalid_type, "$")}
    end
  end

  defp decode_document(document) when is_binary(document) do
    with :ok <- bounded_binary(document, @max_document_bytes, "$"),
         :ok <- valid_utf8(document, "$"),
         :ok <- preflight_json(document, "$"),
         {:ok, value} <- decode_json(document, "$"),
         :ok <- canonical_payload(document, value, "$") do
      if plain_record?(value), do: {:ok, value}, else: {:error, error(:invalid_type, "$")}
    end
  end

  defp decode_document(_document), do: {:error, error(:invalid_type, "$")}

  defp decode_payload(payload_bytes) do
    with :ok <- preflight_json(payload_bytes, "$.payload"),
         {:ok, value} <- decode_json(payload_bytes, "$.payload"),
         :ok <- canonical_payload(payload_bytes, value, "$.payload"),
         :ok <- plain_json_tree(value, "$.payload") do
      if is_map(value), do: {:ok, value}, else: {:error, error(:invalid_type, "$.payload")}
    end
  end

  defp decode_json(bytes, path) do
    case Jason.decode(bytes) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, error(:invalid_json, path)}
    end
  end

  defp canonical_payload(bytes, value, path) do
    if canonical_json(value) == bytes, do: :ok, else: {:error, error(:noncanonical_json, path)}
  rescue
    FunctionClauseError -> {:error, error(:invalid_scalar, path)}
  end

  defp plain_json_tree(value, path), do: plain_json_tree(value, path, 0)

  defp plain_json_tree(value, path, depth) when is_map(value) do
    cond do
      not plain_record?(value) ->
        {:error, error(:invalid_type, path)}

      depth >= @max_depth ->
        {:error, error(:unbounded_value, path)}

      map_size(value) > @max_object_members ->
        {:error, error(:unbounded_value, path)}

      true ->
        value
        |> Enum.sort_by(fn {key, _child} -> key end)
        |> Enum.reduce_while(:ok, &plain_json_member(&1, &2, path, depth))
    end
  end

  defp plain_json_tree(value, path, depth) when is_list(value) do
    if depth >= @max_depth do
      {:error, error(:unbounded_value, path)}
    else
      case bounded_list(value, @max_array_items) do
        {:ok, _size} ->
          value
          |> Enum.with_index()
          |> Enum.reduce_while(:ok, &plain_json_array_item(&1, &2, path, depth))

        :too_many ->
          {:error, error(:unbounded_value, path)}

        :improper ->
          {:error, error(:invalid_type, path)}
      end
    end
  end

  defp plain_json_tree(value, path, _depth) when is_binary(value), do: bounded_string(value, path)

  defp plain_json_tree(value, path, _depth) when is_integer(value) do
    if value in -9_007_199_254_740_991..9_007_199_254_740_991,
      do: :ok,
      else: {:error, error(:invalid_scalar, path)}
  end

  defp plain_json_tree(value, _path, _depth) when is_boolean(value) or is_nil(value), do: :ok

  defp plain_json_tree(_value, path, _depth), do: {:error, error(:invalid_scalar, path)}

  defp plain_json_member({key, child}, :ok, path, depth) do
    child_path = path <> "." <> key

    with :ok <- bounded_string(key, path <> ".<key>"),
         :ok <- bounded_json_child(child, key, child_path, depth + 1) do
      {:cont, :ok}
    else
      {:error, _} = failure -> {:halt, failure}
    end
  end

  defp plain_json_array_item({child, index}, :ok, path, depth) do
    case plain_json_tree(child, path <> "[#{index}]", depth + 1) do
      :ok -> {:cont, :ok}
      {:error, _} = failure -> {:halt, failure}
    end
  end

  defp bounded_json_child(value, "payload", path, _depth) when is_binary(value),
    do: bounded_binary(value, @max_encoded_payload_bytes, path)

  defp bounded_json_child(value, _key, path, depth), do: plain_json_tree(value, path, depth)

  defp payload_schema_for_role(%{"schema" => @release_schema}, "release"), do: :ok
  defp payload_schema_for_role(%{"schema" => @catalog_schema}, "promotion"), do: :ok
  defp payload_schema_for_role(%{"schema" => @catalog_v2_schema}, "promotion"), do: :ok

  defp payload_schema_for_role(%{"schema" => _}, _),
    do: {:error, error(:schema_role_mismatch, "$.payload.schema")}

  defp payload_schema_for_role(_payload, _role),
    do: {:error, error(:incomplete_required_fields, "$.payload.schema")}

  defp normalize_key_records(records) when is_list(records) do
    case bounded_list(records, @max_key_records) do
      {:ok, _size} -> normalize_key_record_list(records)
      :too_many -> {:error, error(:unbounded_value, "$.keys")}
      :improper -> {:error, error(:invalid_key_record, "$.keys")}
    end
  end

  defp normalize_key_records(records) when is_map(records) do
    cond do
      Map.has_key?(records, "keyId") ->
        normalize_key_records([records])

      map_size(records) > @max_key_records ->
        {:error, error(:unbounded_value, "$.keys")}

      true ->
        records
        |> Enum.sort_by(fn {trust_key, _record} -> trust_key end)
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, []}, &normalize_key_record/2)
        |> case do
          {:ok, values} -> {:ok, Enum.reverse(values)}
          failure -> failure
        end
    end
  end

  defp normalize_key_records(_records), do: {:error, error(:invalid_key_record, "$.keys")}

  defp normalize_key_record({{trust_key, record}, index}, {:ok, acc}) do
    path = "$.keys[#{index}]"

    with :ok <- bounded_string(trust_key, path),
         {:ok, normalized} <- validate_key_record(record, path),
         true <- trust_key == normalized["keyId"] do
      {:cont, {:ok, [normalized | acc]}}
    else
      false ->
        {:halt, {:error, error(:invalid_key_record, path)}}

      {:error, %{path: failure_path}} ->
        {:halt, {:error, error(:invalid_key_record, failure_path)}}
    end
  end

  defp normalize_key_record_list(records) do
    records
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, MapSet.new(), []}, &normalize_key_record_list_item/2)
    |> case do
      {:ok, _ids, values} -> {:ok, Enum.reverse(values)}
      failure -> failure
    end
  end

  defp normalize_key_record_list_item({record, index}, {:ok, ids, acc}) do
    case validate_key_record(record, "$.keys[#{index}]") do
      {:ok, normalized} ->
        if MapSet.member?(ids, normalized["keyId"]) do
          {:halt, {:error, error(:duplicate_key, "$.keys[#{index}].keyId")}}
        else
          {:cont, {:ok, MapSet.put(ids, normalized["keyId"]), [normalized | acc]}}
        end

      {:error, _} = failure ->
        {:halt, failure}
    end
  end

  defp validate_key_record(record, path) when is_map(record) do
    fields = [
      "keyId",
      "algorithm",
      "publicKey",
      "allowedRoles",
      "validFrom",
      "validUntil",
      "revokedAt"
    ]

    with :ok <- exact_fields(record, fields, path),
         :ok <- bounded_string(Map.get(record, "keyId"), path <> ".keyId"),
         :ok <- key_id(Map.get(record, "keyId"), path <> ".keyId"),
         :ok <- exact_string(record, "algorithm", @algorithm, path <> ".algorithm"),
         {:ok, public_key} <-
           decode_base64url(Map.get(record, "publicKey"), path <> ".publicKey", 128),
         :ok <- exact_binary_size(public_key, 32, path <> ".publicKey"),
         {:ok, roles} <- key_roles(Map.get(record, "allowedRoles"), path <> ".allowedRoles"),
         {:ok, valid_from} <- parse_timestamp(Map.get(record, "validFrom"), path <> ".validFrom"),
         {:ok, valid_until} <-
           parse_timestamp(Map.get(record, "validUntil"), path <> ".validUntil"),
         :ok <- ordered_timestamps(valid_from, valid_until, path <> ".validUntil"),
         {:ok, revoked_at} <-
           optional_timestamp(Map.get(record, "revokedAt"), path <> ".revokedAt"),
         :ok <- valid_revocation(revoked_at, valid_from, path <> ".revokedAt") do
      {:ok,
       record
       |> Map.put("publicKeyBytes", public_key)
       |> Map.put("allowedRoles", roles)
       |> Map.put("validFromMs", valid_from)
       |> Map.put("validUntilMs", valid_until)
       |> Map.put("revokedAtMs", revoked_at)}
    else
      {:error, %{path: failure_path}} ->
        {:error, error(:invalid_key_record, failure_path)}
    end
  end

  defp validate_key_record(_record, path), do: {:error, error(:invalid_key_record, path)}

  defp find_key(keys, key_id) do
    case Enum.find(keys, &(&1["keyId"] == key_id)) do
      nil -> {:error, error(:unknown_key, "$.keyId")}
      key -> {:ok, key}
    end
  end

  defp key_allows_role(key, role),
    do:
      if(role in key["allowedRoles"],
        do: :ok,
        else: {:error, error(:role_not_allowed, "$.signingRole")}
      )

  defp key_lifecycle(key, now_ms) do
    cond do
      key["revokedAtMs"] != nil and now_ms >= key["revokedAtMs"] ->
        {:error, error(:revoked_key, "$.keyId")}

      now_ms < key["validFromMs"] ->
        {:error, error(:not_yet_valid_key, "$.keyId")}

      now_ms >= key["validUntilMs"] ->
        {:error, error(:expired_key, "$.keyId")}

      true ->
        :ok
    end
  end

  defp verify_signature(payload_bytes, signature, public_key) do
    if :crypto.verify(:eddsa, :none, payload_bytes, signature, [public_key, :ed25519]),
      do: :ok,
      else: {:error, error(:invalid_signature, "$.signature")}
  end

  defp exact_decoded_payload_size(value, path) when is_binary(value) do
    if byte_size(value) <= @max_payload_bytes,
      do: :ok,
      else: {:error, error(:unbounded_value, path)}
  end

  defp validate_release(value, path, origins) do
    with :ok <- exact_fields(value, @release_fields, path),
         :ok <-
           exact_constant(value, "schema", @release_schema, :unknown_schema, path <> ".schema"),
         :ok <- identity_version(Map.get(value, "application"), path <> ".application"),
         :ok <- identity_version(Map.get(value, "package"), path <> ".package"),
         :ok <- identity_version(Map.get(value, "surface"), path <> ".surface"),
         :ok <- release_id(Map.get(value, "releaseId"), path <> ".releaseId", value),
         :ok <-
           exact_constant(
             value,
             "transport",
             "module_federation",
             :invalid_value,
             path <> ".transport"
           ),
         :ok <- remote_name(Map.get(value, "remoteName"), path <> ".remoteName"),
         :ok <- exposed_module(Map.get(value, "exposedModule"), path <> ".exposedModule"),
         :ok <- validate_artifacts(Map.get(value, "manifest"), Map.get(value, "artifacts"), path),
         :ok <-
           validate_host_compatibility(
             Map.get(value, "hostCompatibility"),
             path <> ".hostCompatibility"
           ),
         :ok <- validate_provenance(Map.get(value, "provenance"), path <> ".provenance"),
         {:ok, _released_at} <-
           parse_timestamp(Map.get(value, "releasedAt"), path <> ".releasedAt"),
         :ok <-
           artifact_base_url(
             Map.get(value, "artifactBaseUrl"),
             value,
             origins,
             path <> ".artifactBaseUrl"
           ) do
      {:ok, value}
    end
  end

  defp release_id(value, path, release) when is_binary(value) do
    with :ok <- bounded_string(value, path),
         true <- Regex.match?(~r/^sha256:[0-9a-f]{64}$/, value) do
      logical = release |> Map.delete("releaseId") |> Map.delete("artifactBaseUrl")
      expected = "sha256:" <> digest_hex(canonical_json(logical))

      if value == expected, do: :ok, else: {:error, error(:release_id_mismatch, path)}
    else
      false -> {:error, error(:invalid_sha256, path)}
      {:error, _} = failure -> failure
    end
  end

  defp release_id(_value, path, _release), do: {:error, error(:invalid_sha256, path)}

  defp validate_artifacts(manifest, artifacts, path) when is_list(artifacts) do
    case bounded_list(artifacts, @max_artifacts) do
      {:ok, 0} ->
        {:error, error(:incomplete_required_fields, path <> ".artifacts")}

      {:ok, _size} ->
        with {:ok, manifest_entry} <- validate_artifact(manifest, path <> ".manifest"),
             {:ok, entries} <- validate_artifact_list(artifacts, path <> ".artifacts") do
          manifest_in_inventory(manifest_entry, entries, path <> ".manifest")
        end

      :too_many ->
        {:error, error(:unbounded_value, path <> ".artifacts")}

      :improper ->
        {:error, error(:invalid_type, path <> ".artifacts")}
    end
  end

  defp validate_artifacts(_manifest, _artifacts, path),
    do: {:error, error(:invalid_type, path <> ".artifacts")}

  defp validate_artifact_list(artifacts, path) do
    artifacts
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, nil, MapSet.new(), []}, fn {artifact, index},
                                                          {:ok, previous, paths, acc} ->
      item_path = path <> "[#{index}]"

      with {:ok, normalized} <- validate_artifact(artifact, item_path),
           :ok <- sorted_artifact(previous, normalized["path"], item_path <> ".path"),
           false <- MapSet.member?(paths, normalized["path"]) do
        {:cont,
         {:ok, normalized["path"], MapSet.put(paths, normalized["path"]), [normalized | acc]}}
      else
        true -> {:halt, {:error, error(:duplicate_artifact_path, item_path <> ".path")}}
        {:error, _} = failure -> {:halt, failure}
      end
    end)
    |> case do
      {:ok, _previous, _paths, entries} -> {:ok, Enum.reverse(entries)}
      failure -> failure
    end
  end

  defp sorted_artifact(nil, _path, _item_path), do: :ok
  defp sorted_artifact(previous, current, _item_path) when previous < current, do: :ok
  defp sorted_artifact(_previous, _current, path), do: {:error, error(:unsorted_artifacts, path)}

  defp validate_artifact(value, path) when is_map(value) do
    with :ok <- exact_fields(value, ["path", "sha256", "size", "mediaType"], path),
         :ok <- artifact_path(Map.get(value, "path"), path <> ".path"),
         :ok <- sha256(Map.get(value, "sha256"), path <> ".sha256"),
         :ok <- artifact_size(Map.get(value, "size"), path <> ".size"),
         :ok <- media_type(Map.get(value, "mediaType"), path <> ".mediaType") do
      {:ok, value}
    end
  end

  defp validate_artifact(_value, path), do: {:error, error(:invalid_type, path)}

  defp manifest_in_inventory(manifest, entries, path) do
    if Enum.any?(entries, &(&1 == manifest)),
      do: :ok,
      else: {:error, error(:incomplete_required_fields, path)}
  end

  defp validate_host_compatibility(value, path) when is_map(value) do
    with :ok <- exact_fields(value, ["hostContract", "compatibility", "vueRange"], path),
         :ok <-
           exact_constant(
             value,
             "hostContract",
             @host_contract,
             :invalid_value,
             path <> ".hostContract"
           ),
         :ok <-
           exact_fields(
             Map.get(value, "compatibility"),
             [
               "cadenceApplicationContract",
               "cadenceSurfaceContract",
               "cadenceFederatedRendererContract",
               "cadenceThemeContract"
             ],
             path <> ".compatibility"
           ),
         :ok <- exact_compatibility(Map.get(value, "compatibility"), path <> ".compatibility") do
      exact_constant(value, "vueRange", @vue_range, :invalid_value, path <> ".vueRange")
    end
  end

  defp validate_host_compatibility(_value, path), do: {:error, error(:invalid_type, path)}

  defp exact_compatibility(value, path) do
    [
      "cadenceApplicationContract",
      "cadenceSurfaceContract",
      "cadenceFederatedRendererContract",
      "cadenceThemeContract"
    ]
    |> Enum.reduce_while(:ok, fn key, :ok ->
      if Map.get(value, key) == 1,
        do: {:cont, :ok},
        else: {:halt, {:error, error(:invalid_value, path <> "." <> key)}}
    end)
  end

  defp validate_provenance(value, path) when is_map(value) do
    fields = ["sourceRepository", "sourceRevision", "buildId", "builder", "workflow", "builtAt"]

    with :ok <- exact_fields(value, fields, path),
         :ok <- https_url(Map.get(value, "sourceRepository"), path <> ".sourceRepository"),
         :ok <- source_revision(Map.get(value, "sourceRevision"), path <> ".sourceRevision"),
         :ok <- bounded_token(Map.get(value, "buildId"), path <> ".buildId"),
         :ok <- bounded_token(Map.get(value, "builder"), path <> ".builder"),
         :ok <- bounded_token(Map.get(value, "workflow"), path <> ".workflow"),
         {:ok, _built_at} <- parse_timestamp(Map.get(value, "builtAt"), path <> ".builtAt") do
      :ok
    end
  end

  defp validate_provenance(_value, path), do: {:error, error(:invalid_type, path)}

  defp artifact_base_url(value, release, origins, path) when is_binary(value) do
    with {:ok, origin, raw_path} <- strict_https_url(value, path),
         :ok <- allowed_origin(origin, origins, path),
         application <- Map.get(release, "application"),
         expected_path <-
           "/releases/" <> application["id"] <> "/" <> release["releaseId"] <> "/artifacts/",
         true <- raw_path == expected_path do
      :ok
    else
      false -> {:error, error(:invalid_base_url, path)}
      {:error, _} = failure -> failure
    end
  end

  defp artifact_base_url(_value, _release, _origins, path),
    do: {:error, error(:invalid_base_url, path)}

  defp allowed_origins(opts) do
    case Keyword.get(opts, :allowed_origins) do
      origins when is_list(origins) and origins != [] ->
        validate_allowed_origin_list(origins)

      _ ->
        {:error, error(:invalid_base_url, "$.allowedOrigins")}
    end
  end

  defp validate_allowed_origin_list(origins) do
    case bounded_list(origins, @max_key_records) do
      :too_many ->
        {:error, error(:unbounded_value, "$.allowedOrigins")}

      :improper ->
        {:error, error(:invalid_base_url, "$.allowedOrigins")}

      {:ok, _size} ->
        case Enum.with_index(origins)
             |> Enum.reduce_while({:ok, MapSet.new()}, &validate_allowed_origin/2) do
          {:ok, _} -> {:ok, origins}
          failure -> failure
        end
    end
  end

  defp validate_allowed_origin({origin, index}, {:ok, seen}) do
    path = "$.allowedOrigins[#{index}]"

    with {:ok, canonical, raw_path} <- strict_https_url(origin, path),
         true <- raw_path == "",
         true <- canonical == origin,
         false <- MapSet.member?(seen, origin) do
      {:cont, {:ok, MapSet.put(seen, origin)}}
    else
      true -> {:halt, {:error, error(:invalid_base_url, path)}}
      {:error, _} = failure -> {:halt, failure}
      _ -> {:halt, {:error, error(:invalid_base_url, path)}}
    end
  end

  defp allowed_origin(origin, origins, path),
    do: if(origin in origins, do: :ok, else: {:error, error(:invalid_base_url, path)})

  defp strict_https_url(value, path) when is_binary(value) do
    with :ok <- bounded_string(value, path),
         false <- Enum.any?(String.to_charlist(value), &(&1 <= 0x20)),
         false <- Enum.any?(["\\", "%", "?", "#"], &String.contains?(value, &1)),
         true <- String.starts_with?(value, "https://"),
         rest <- binary_part(value, 8, byte_size(value) - 8),
         {authority, raw_path} <- split_authority_path(rest),
         :ok <- valid_raw_authority(authority, path) do
      {:ok, "https://" <> authority, raw_path}
    else
      {:error, _} = failure -> failure
      _ -> {:error, error(:invalid_base_url, path)}
    end
  end

  defp strict_https_url(_value, path), do: {:error, error(:invalid_base_url, path)}

  defp split_authority_path(rest) do
    case :binary.match(rest, "/") do
      :nomatch ->
        {rest, ""}

      {index, 1} ->
        {binary_part(rest, 0, index), binary_part(rest, index, byte_size(rest) - index)}
    end
  end

  defp valid_raw_authority(authority, path) do
    case Regex.run(
           ~r/^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*)(?::([1-9][0-9]{0,4}))?$/,
           authority,
           capture: :all_but_first
         ) do
      [host] when host != "" ->
        :ok

      [host, nil] when host != "" ->
        :ok

      [host, port] when host != "" and is_binary(port) ->
        if String.to_integer(port) <= 65_535 and String.to_integer(port) != 443,
          do: :ok,
          else: {:error, error(:invalid_base_url, path)}

      _ ->
        {:error, error(:invalid_base_url, path)}
    end
  end

  defp https_url(value, path) do
    case strict_https_url(value, path) do
      {:ok, _origin, raw_path} ->
        if raw_path == "" or String.starts_with?(raw_path, "/"),
          do: :ok,
          else: {:error, error(:invalid_base_url, path)}

      failure ->
        failure
    end
  end

  defp validate_catalog(value, key_records, opts, origins) when is_map(value) do
    path = "$.payload"

    with :ok <- exact_fields(value, @catalog_fields, path),
         :ok <-
           exact_constant(value, "schema", @catalog_schema, :unknown_schema, path <> ".schema"),
         :ok <- sequence(Map.get(value, "sequence"), path <> ".sequence"),
         {:ok, published_at} <-
           parse_timestamp(Map.get(value, "publishedAt"), path <> ".publishedAt"),
         {:ok, expires_at} <- parse_timestamp(Map.get(value, "expiresAt"), path <> ".expiresAt"),
         :ok <- catalog_window(published_at, expires_at, path),
         {:ok, entries} <-
           catalog_entries(
             Map.get(value, "entries"),
             published_at,
             key_records,
             opts,
             origins,
             path <> ".entries"
           ) do
      {:ok,
       %{
         payload: value,
         sequence: Map.get(value, "sequence"),
         published_at: published_at,
         expires_at: expires_at,
         entries: entries
       }}
    end
  end

  defp validate_catalog_v2(value, key_records, opts, origins) when is_map(value) do
    path = "$.payload"

    with :ok <- exact_fields(value, @catalog_v2_fields, path),
         :ok <-
           exact_constant(value, "schema", @catalog_v2_schema, :unknown_schema, path <> ".schema"),
         {:ok, transition} <-
           catalog_transition(Map.get(value, "transition"), path <> ".transition"),
         :ok <- sequence(Map.get(value, "sequence"), path <> ".sequence"),
         {:ok, published_at} <-
           parse_timestamp(Map.get(value, "publishedAt"), path <> ".publishedAt"),
         {:ok, expires_at} <- parse_timestamp(Map.get(value, "expiresAt"), path <> ".expiresAt"),
         :ok <- catalog_window(published_at, expires_at, path),
         :ok <-
           bounded_integer(
             Map.get(value, "identityCount"),
             1,
             @max_catalog_entries,
             path <> ".identityCount"
           ),
         {:ok, entries} <-
           catalog_entries(
             Map.get(value, "entries"),
             published_at,
             key_records,
             opts,
             origins,
             path <> ".entries"
           ),
         identity_count = Map.get(value, "identityCount"),
         true <- identity_count == length(entries),
         :ok <- digest_value(Map.get(value, "snapshotDigest"), path <> ".snapshotDigest") do
      {:ok,
       %{
         payload: value,
         transition: transition,
         sequence: Map.get(value, "sequence"),
         published_at: published_at,
         expires_at: expires_at,
         identity_count: identity_count,
         snapshot_digest: Map.get(value, "snapshotDigest"),
         entries: add_v2_entry_envelopes(Map.get(value, "entries"), entries)
       }}
    else
      false -> {:error, error(:identity_count_mismatch, path <> ".identityCount")}
      {:error, _} = failure -> failure
    end
  end

  defp validate_catalog_v2(_value, _key_records, _opts, _origins),
    do: {:error, error(:invalid_type, "$.payload")}

  defp catalog_transition(value, _path)
       when value in ["initial", "legacy_successor", "promotion", "rollback"],
       do: {:ok, value}

  defp catalog_transition(_value, path), do: {:error, error(:invalid_value, path)}

  defp add_v2_entry_envelopes(raw_entries, entries) do
    Enum.zip(raw_entries, entries)
    |> Enum.map(fn {raw, entry} ->
      entry
      |> Map.put(:current_envelope, Map.fetch!(raw, "current"))
      |> Map.put(:fallback_envelope, Map.get(raw, "fallback"))
    end)
  end

  defp catalog_entries(entries, published_at, key_records, opts, origins, path) do
    case bounded_list(entries, @max_catalog_entries) do
      {:ok, 0} ->
        {:error, error(:incomplete_required_fields, path)}

      {:ok, _size} ->
        catalog_entries_bounded(entries, published_at, key_records, opts, origins, path)

      :too_many ->
        {:error, error(:unbounded_value, path)}

      :improper ->
        {:error, error(:invalid_type, path)}
    end
  end

  defp catalog_entries_bounded(entries, published_at, key_records, opts, origins, path) do
    Enum.with_index(entries)
    |> Enum.reduce_while({:ok, nil, MapSet.new(), MapSet.new(), %{}, %{}, []}, fn {entry, index},
                                                                                  {:ok,
                                                                                   previous_identity,
                                                                                   release_ids,
                                                                                   identities,
                                                                                   remotes,
                                                                                   exposed, acc} ->
      item_path = path <> "[#{index}]"

      with {:ok, verified} <-
             validate_catalog_entry(entry, key_records, opts, origins, published_at, item_path),
           :ok <- sorted_identity(previous_identity, verified.identity, item_path <> ".identity"),
           :ok <- unique_identity(identities, verified.identity, item_path <> ".identity"),
           {:ok, release_ids} <- unique_release_ids(release_ids, verified, item_path),
           {:ok, remotes} <-
             unique_named(
               remotes,
               verified.remote_name,
               verified.identity,
               item_path <> ".current.remoteName"
             ),
           {:ok, remotes} <-
             optional_unique_name(
               remotes,
               verified.fallback && verified.fallback["remoteName"],
               verified.identity,
               item_path <> ".fallback.remoteName"
             ),
           {:ok, exposed} <-
             unique_named(
               exposed,
               {verified.remote_name, verified.exposed_module},
               verified.identity,
               item_path <> ".current.exposedModule"
             ),
           {:ok, exposed} <-
             optional_unique_name(
               exposed,
               verified.fallback &&
                 {verified.fallback["remoteName"], verified.fallback["exposedModule"]},
               verified.identity,
               item_path <> ".fallback.exposedModule"
             ) do
        {:cont,
         {:ok, identity_key(verified.identity), release_ids,
          MapSet.put(identities, identity_key(verified.identity)), remotes, exposed,
          [verified | acc]}}
      else
        {:error, _} = failure -> {:halt, failure}
      end
    end)
    |> case do
      {:ok, _previous, _release_ids, _identities, _remotes, _exposed, values} ->
        {:ok, Enum.reverse(values)}

      failure ->
        failure
    end
  end

  defp validate_catalog_entry(entry, key_records, opts, origins, published_at, path)
       when is_map(entry) do
    with :ok <- exact_fields(entry, ["identity", "current"], path, ["fallback"]),
         {:ok, identity} <-
           validate_catalog_identity(Map.get(entry, "identity"), path <> ".identity"),
         {:ok, current} <-
           verify_nested_release(
             Map.get(entry, "current"),
             key_records,
             opts,
             origins,
             path <> ".current"
           ),
         {:ok, fallback} <-
           optional_nested_release(entry, key_records, opts, origins, path <> ".fallback"),
         :ok <- release_matches_identity(current.release, identity, path <> ".current"),
         :ok <- optional_release_matches_identity(fallback, identity, path <> ".fallback"),
         :ok <- release_published(current.release, published_at, path <> ".current.releasedAt"),
         :ok <- optional_release_published(fallback, published_at, path <> ".fallback.releasedAt"),
         :ok <- distinct_fallback(current.release, fallback, path <> ".fallback") do
      {:ok,
       %{
         identity: identity,
         current: current.release,
         fallback: fallback && fallback.release,
         remote_name: current.release["remoteName"],
         exposed_module: current.release["exposedModule"]
       }}
    end
  end

  defp validate_catalog_entry(_entry, _keys, _opts, _origins, _published_at, path),
    do: {:error, error(:invalid_type, path)}

  defp verify_nested_release(document, keys, opts, origins, path) do
    case verify_envelope(document, keys, opts, "release") do
      {:ok, verified} ->
        case validate_release(verified.payload, path <> ".payload", origins) do
          {:ok, release} -> {:ok, Map.put(verified, :release, release)}
          failure -> failure
        end

      {:error, failure} ->
        {:error, relocate(failure, path)}
    end
  end

  defp optional_nested_release(entry, keys, opts, origins, path) do
    case Map.fetch(entry, "fallback") do
      :error -> {:ok, nil}
      {:ok, nil} -> {:error, error(:invalid_type, path)}
      {:ok, value} -> verify_nested_release(value, keys, opts, origins, path)
    end
  end

  defp validate_catalog_identity(value, path) when is_map(value) do
    with :ok <- exact_fields(value, ["application", "package", "surface"], path),
         :ok <- identity_version(Map.get(value, "application"), path <> ".application"),
         :ok <- identity_version(Map.get(value, "package"), path <> ".package"),
         :ok <- identity_version(Map.get(value, "surface"), path <> ".surface") do
      {:ok, value}
    end
  end

  defp validate_catalog_identity(_value, path), do: {:error, error(:invalid_type, path)}

  defp release_matches_identity(release, identity, path),
    do:
      if(identity_key(release) == identity_key(identity),
        do: :ok,
        else: {:error, error(:identity_mismatch, path)}
      )

  defp optional_release_matches_identity(nil, _identity, _path), do: :ok

  defp optional_release_matches_identity(%{release: release}, identity, path),
    do: release_matches_identity(release, identity, path)

  defp release_published(release, published_at, path) do
    case parse_timestamp(release["releasedAt"], path) do
      {:ok, released_at} when released_at <= published_at -> :ok
      {:ok, _} -> {:error, error(:not_yet_published, path)}
      failure -> failure
    end
  end

  defp optional_release_published(nil, _published_at, _path), do: :ok

  defp optional_release_published(%{release: release}, published_at, path),
    do: release_published(release, published_at, path)

  defp distinct_fallback(_current, nil, _path), do: :ok

  defp distinct_fallback(current, %{release: fallback}, path),
    do:
      if(current["releaseId"] == fallback["releaseId"],
        do: {:error, error(:invalid_fallback, path)},
        else: :ok
      )

  defp distinct_fallback(current, fallback, path) when is_map(fallback),
    do:
      if(current["releaseId"] == fallback["releaseId"],
        do: {:error, error(:invalid_fallback, path)},
        else: :ok
      )

  defp unique_release_ids(ids, verified, path) do
    values = [
      verified.current["releaseId"]
      | if(verified.fallback, do: [verified.fallback["releaseId"]], else: [])
    ]

    if Enum.any?(values, &MapSet.member?(ids, &1)),
      do: {:error, error(:duplicate_release_id, path)},
      else: {:ok, Enum.reduce(values, ids, &MapSet.put(&2, &1))}
  end

  defp unique_named(names, name, identity, path) do
    identity_value = identity_key(identity)

    case Map.get(names, name) do
      nil -> {:ok, Map.put(names, name, identity_value)}
      ^identity_value -> {:ok, names}
      _ -> {:error, error(:duplicate_remote_or_exposed_module, path)}
    end
  end

  defp optional_unique_name(names, nil, _identity, _path), do: {:ok, names}

  defp optional_unique_name(names, name, identity, path),
    do: unique_named(names, name, identity, path)

  defp unique_identity(identities, identity, path),
    do:
      if(MapSet.member?(identities, identity_key(identity)),
        do: {:error, error(:duplicate_identity, path)},
        else: :ok
      )

  defp sorted_identity(nil, _current, _path), do: :ok

  defp sorted_identity(previous, current, path) do
    if previous < identity_key(current), do: :ok, else: {:error, error(:unsorted_entries, path)}
  end

  defp identity_key(%{"application" => app, "package" => package, "surface" => surface}),
    do:
      {app["id"], app["version"], package["id"], package["version"], surface["id"],
       surface["version"]}

  defp identity_key(%{application: app, package: package, surface: surface}),
    do:
      {app["id"], app["version"], package["id"], package["version"], surface["id"],
       surface["version"]}

  defp identity_key(_value), do: {}

  defp admit_catalog(_catalog, _digest_value, nil, _origins), do: {:ok, :new}

  defp admit_catalog(catalog, digest_value, state, origins) when is_map(state) do
    with :ok <- validate_state(state, origins),
         {:ok, state_published_at} <-
           parse_timestamp(state["publishedAt"], "$.acceptedState.publishedAt"),
         :ok <- state_digest(state),
         :ok <- state_identity_set(state, catalog.entries) do
      admit_catalog_state(catalog, digest_value, state, state_published_at)
    end
  end

  defp admit_catalog(_catalog, _digest_value, _state, _origins),
    do: {:error, error(:invalid_state, "$.acceptedState")}

  defp admit_catalog_state(catalog, digest_value, state, state_published_at) do
    cond do
      catalog.sequence < state["sequence"] ->
        {:error, error(:lower_sequence, "$.payload.sequence")}

      catalog.sequence == state["sequence"] and digest_value == state["digest"] ->
        if(catalog.published_at == state_published_at,
          do: {:ok, :identical},
          else: {:error, error(:same_sequence_fork, "$.payload.sequence")}
        )

      catalog.sequence == state["sequence"] ->
        {:error, error(:same_sequence_fork, "$.payload.sequence")}

      catalog.published_at <= state_published_at ->
        {:error, error(:non_monotonic_publication, "$.payload.publishedAt")}

      true ->
        admit_successor(catalog.entries, state["entries"])
    end
  end

  defp admit_successor(entries, previous_entries) do
    previous = Map.new(previous_entries, &{identity_key(&1["identity"]), &1})

    Enum.reduce_while(entries, {:ok, :new}, fn entry, {:ok, :new} ->
      prior = Map.get(previous, identity_key(entry.identity))

      cond do
        is_nil(prior) ->
          {:halt, {:error, error(:invalid_state_transition, "$.payload.entries")}}

        entry.current["releaseId"] == prior["current"]["releaseId"] ->
          {:halt, {:error, error(:invalid_state_transition, "$.payload.entries")}}

        entry.fallback == nil ->
          {:halt, {:error, error(:fallback_required, "$.payload.entries")}}

        not is_nil(prior["fallback"]) and
          entry.current["releaseId"] == prior["fallback"]["releaseId"] and
            entry.fallback["releaseId"] == prior["current"]["releaseId"] ->
          {:cont, {:ok, :new}}

        entry.fallback["releaseId"] == prior["current"]["releaseId"] ->
          {:cont, {:ok, :new}}

        true ->
          {:halt, {:error, error(:invalid_state_transition, "$.payload.entries")}}
      end
    end)
  end

  defp validate_state(state, origins) do
    fields = ["sequence", "publishedAt", "digest", "entries"]

    result =
      if Enum.sort(Map.keys(state)) == Enum.sort(fields) and is_integer(state["sequence"]) and
           state["sequence"] >= 1 and state["sequence"] <= @max_sequence and
           is_list(state["entries"]) do
        with {:ok, published_at} <-
               parse_timestamp(state["publishedAt"], "$.acceptedState.publishedAt"),
             :ok <- timestamp_in_bounds(published_at, "$.acceptedState.publishedAt"),
             :ok <- digest_value(state["digest"], "$.acceptedState.digest"),
             :ok <- state_entries_bound(state["entries"]) do
          validate_state_entries(state["entries"], origins, published_at)
        end
      else
        {:error, error(:invalid_state, "$.acceptedState")}
      end

    case result do
      :ok -> :ok
      {:error, %{path: path}} -> {:error, error(:invalid_state, path)}
    end
  end

  defp state_digest(state),
    do:
      if(is_binary(state["digest"]),
        do: :ok,
        else: {:error, error(:invalid_state, "$.acceptedState.digest")}
      )

  defp validate_state_entries(entries, origins, published_at) when entries != [] do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while(
      {:ok, nil, MapSet.new(), MapSet.new(), %{}, %{}},
      &validate_state_entry(&1, &2, origins, published_at)
    )
    |> case do
      {:ok, _previous_identity, _ids, _release_ids, _remotes, _exposures} -> :ok
      failure -> failure
    end
  end

  defp validate_state_entries(_entries, _origins, _published_at),
    do: {:error, error(:invalid_state, "$.acceptedState.entries")}

  defp state_entries_bound(entries) do
    case bounded_list(entries, @max_catalog_entries) do
      {:ok, _size} -> :ok
      _ -> {:error, error(:invalid_state, "$.acceptedState.entries")}
    end
  end

  defp validate_state_entry(
         {entry, index},
         {:ok, previous_identity, ids, release_ids, remotes, exposures},
         origins,
         published_at
       ) do
    with true <- is_map(entry),
         :ok <-
           exact_fields(
             entry,
             ["identity", "current"],
             "$.acceptedState.entries[#{index}]",
             ["fallback"]
           ),
         {:ok, identity} <-
           validate_catalog_identity(
             entry["identity"],
             "$.acceptedState.entries[#{index}].identity"
           ),
         {:ok, current} <-
           validate_release(
             entry["current"],
             "$.acceptedState.entries[#{index}].current",
             origins
           ),
         :ok <-
           sorted_identity(
             previous_identity,
             identity,
             "$.acceptedState.entries[#{index}].identity"
           ),
         :ok <-
           release_matches_identity(
             current,
             identity,
             "$.acceptedState.entries[#{index}].current"
           ),
         :ok <-
           release_published(
             current,
             published_at,
             "$.acceptedState.entries[#{index}].current.releasedAt"
           ),
         {:ok, fallback} <-
           validate_state_fallback(
             Map.fetch(entry, "fallback"),
             identity,
             origins,
             "$.acceptedState.entries[#{index}].fallback"
           ),
         :ok <-
           distinct_fallback(current, fallback, "$.acceptedState.entries[#{index}].fallback"),
         :ok <-
           optional_state_release_published(
             fallback,
             published_at,
             "$.acceptedState.entries[#{index}].fallback.releasedAt"
           ),
         false <- MapSet.member?(ids, identity_key(identity)) do
      with {:ok, release_ids} <-
             unique_state_release_ids(
               release_ids,
               current,
               fallback,
               "$.acceptedState.entries[#{index}]"
             ),
           {:ok, remotes} <-
             unique_named(
               remotes,
               current["remoteName"],
               identity,
               "$.acceptedState.entries[#{index}].current.remoteName"
             ),
           {:ok, remotes} <-
             optional_unique_name(
               remotes,
               fallback && fallback["remoteName"],
               identity,
               "$.acceptedState.entries[#{index}].fallback.remoteName"
             ),
           {:ok, exposures} <-
             unique_named(
               exposures,
               {current["remoteName"], current["exposedModule"]},
               identity,
               "$.acceptedState.entries[#{index}].current.exposedModule"
             ),
           {:ok, exposures} <-
             optional_unique_name(
               exposures,
               fallback && {fallback["remoteName"], fallback["exposedModule"]},
               identity,
               "$.acceptedState.entries[#{index}].fallback.exposedModule"
             ) do
        {:cont,
         {:ok, identity_key(identity), MapSet.put(ids, identity_key(identity)), release_ids,
          remotes, exposures}}
      else
        failure -> {:halt, failure}
      end
    else
      false -> {:halt, {:error, error(:invalid_state, "$.acceptedState.entries[#{index}]")}}
      {:error, _} = failure -> {:halt, failure}
      _ -> {:halt, {:error, error(:invalid_state, "$.acceptedState.entries[#{index}]")}}
    end
  end

  defp validate_state_fallback(:error, _identity, _origins, _path), do: {:ok, nil}

  defp validate_state_fallback({:ok, nil}, _identity, _origins, path),
    do: {:error, error(:invalid_state, path)}

  defp validate_state_fallback({:ok, value}, identity, origins, path) do
    with {:ok, fallback} <- validate_release(value, path, origins),
         :ok <- release_matches_identity(fallback, identity, path) do
      {:ok, fallback}
    end
  end

  defp optional_state_release_published(nil, _published_at, _path), do: :ok

  defp optional_state_release_published(release, published_at, path),
    do: release_published(release, published_at, path)

  defp unique_state_release_ids(ids, current, fallback, path) do
    values = [current["releaseId"] | if(fallback, do: [fallback["releaseId"]], else: [])]

    if Enum.any?(values, &MapSet.member?(ids, &1)),
      do: {:error, error(:duplicate_release_id, path)},
      else: {:ok, Enum.reduce(values, ids, &MapSet.put(&2, &1))}
  end

  defp state_identity_set(state, entries) do
    old = state["entries"] |> Enum.map(&identity_key(&1["identity"])) |> MapSet.new()
    current = entries |> Enum.map(&identity_key(&1.identity)) |> MapSet.new()

    if old == current,
      do: :ok,
      else: {:error, error(:invalid_state_transition, "$.payload.entries")}
  end

  defp state_entry(entry) do
    base = %{"identity" => entry.identity, "current" => entry.current}

    if entry.fallback,
      do: Map.put(base, "fallback", entry.fallback),
      else: base
  end

  defp catalog_window(published_at, expires_at, path) do
    cond do
      expires_at <= published_at ->
        {:error, error(:invalid_timestamp, path <> ".expiresAt")}

      expires_at - published_at > @max_catalog_lifetime_seconds * 1_000 ->
        {:error, error(:unbounded_value, path)}

      true ->
        :ok
    end
  end

  defp catalog_current(catalog, now_ms) do
    cond do
      now_ms < catalog.published_at ->
        {:error, error(:not_yet_published, "$.payload.publishedAt")}

      now_ms >= catalog.expires_at ->
        {:error, error(:expired_catalog, "$.payload.expiresAt")}

      true ->
        :ok
    end
  end

  defp sequence(value, _path) when is_integer(value) and value >= 1 and value <= @max_sequence,
    do: :ok

  defp sequence(_value, path), do: {:error, error(:invalid_sequence, path)}

  defp identity_version(value, path) when is_map(value) do
    with :ok <- exact_fields(value, ["id", "version"], path),
         :ok <- safe_identifier(Map.get(value, "id"), path <> ".id") do
      bounded_integer(Map.get(value, "version"), 1, @max_version, path <> ".version")
    end
  end

  defp identity_version(_value, path), do: {:error, error(:invalid_type, path)}
  defp remote_name(value, path), do: safe_identifier(value, path)

  defp exposed_module(value, path) when is_binary(value) do
    with :ok <- bounded_string(value, path),
         true <- Regex.match?(~r/^\.[\/][A-Za-z][A-Za-z0-9._-]{0,127}$/, value) do
      :ok
    else
      false -> {:error, error(:invalid_value, path)}
      {:error, _} = failure -> failure
    end
  end

  defp exposed_module(_value, path), do: {:error, error(:invalid_value, path)}

  defp safe_identifier(value, path) when is_binary(value) do
    with :ok <- bounded_binary(value, @max_identifier_bytes, path),
         :ok <- valid_utf8(value, path),
         true <- Regex.match?(~r/^[a-z][a-z0-9._-]{0,127}$/, value) do
      :ok
    else
      false -> {:error, error(:invalid_value, path)}
      {:error, _} = failure -> failure
    end
  end

  defp safe_identifier(_value, path), do: {:error, error(:invalid_value, path)}
  defp key_id(value, path), do: safe_identifier(value, path)

  defp artifact_path(value, path) when is_binary(value) do
    cond do
      byte_size(value) == 0 ->
        {:error, error(:invalid_value, path)}

      byte_size(value) > @max_artifact_path_bytes ->
        {:error, error(:unbounded_value, path)}

      not String.valid?(value) ->
        {:error, error(:invalid_utf8, path)}

      String.starts_with?(value, "/") ->
        {:error, error(:absolute_path, path)}

      String.contains?(value, "\\") ->
        {:error, error(:backslash_path, path)}

      Enum.any?(String.split(value, "/"), &(&1 in ["", ".", ".."])) ->
        {:error, error(:path_traversal, path)}

      true ->
        :ok
    end
  end

  defp artifact_path(_value, path), do: {:error, error(:invalid_value, path)}

  defp sha256(value, path) when is_binary(value),
    do:
      if(Regex.match?(~r/^[0-9a-f]{64}$/, value),
        do: :ok,
        else: {:error, error(:invalid_sha256, path)}
      )

  defp sha256(_value, path), do: {:error, error(:invalid_sha256, path)}

  defp digest_value(value, path) when is_binary(value) do
    if Regex.match?(~r/^sha256:[0-9a-f]{64}$/, value),
      do: :ok,
      else: {:error, error(:invalid_state, path)}
  end

  defp digest_value(_value, path), do: {:error, error(:invalid_state, path)}

  defp artifact_size(value, path), do: bounded_integer(value, 0, @max_artifact_size, path)

  defp media_type(value, path) when is_binary(value) do
    with :ok <- bounded_binary(value, @max_media_type_bytes, path),
         :ok <- valid_utf8(value, path),
         true <-
           Regex.match?(
             ~r/^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}\/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}$/,
             value
           ) do
      :ok
    else
      false -> {:error, error(:invalid_value, path)}
      {:error, _} = failure -> failure
    end
  end

  defp media_type(_value, path), do: {:error, error(:invalid_value, path)}

  defp source_revision(value, path) when is_binary(value),
    do:
      if(Regex.match?(~r/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/, value),
        do: :ok,
        else: {:error, error(:invalid_value, path)}
      )

  defp source_revision(_value, path), do: {:error, error(:invalid_value, path)}
  defp bounded_token(value, path), do: bounded_string(value, path)

  defp bounded_integer(value, min, max, _path)
       when is_integer(value) and value >= min and value <= max, do: :ok

  defp bounded_integer(_value, _min, _max, path), do: {:error, error(:invalid_value, path)}

  defp role(value, _path) when value in ["release", "promotion"], do: {:ok, value}
  defp role(_value, path), do: {:error, error(:invalid_role, path)}

  defp key_roles(value, path) when is_list(value) do
    case bounded_list(value, 2) do
      {:ok, 0} ->
        {:error, error(:invalid_value, path)}

      {:ok, _size} ->
        cond do
          value != Enum.uniq(value) -> {:error, error(:duplicate_role, path)}
          value != Enum.sort(value) -> {:error, error(:unsorted_array, path)}
          Enum.all?(value, &(&1 in ["release", "promotion"])) -> {:ok, value}
          true -> {:error, error(:invalid_role, path)}
        end

      :too_many ->
        {:error, error(:invalid_value, path)}

      :improper ->
        {:error, error(:invalid_type, path)}
    end
  end

  defp key_roles(_value, path), do: {:error, error(:invalid_type, path)}

  defp exact_string(map, key, expected, path) do
    case Map.get(map, key) do
      ^expected -> :ok
      value when is_binary(value) -> {:error, error(:invalid_value, path)}
      nil -> {:error, error(:incomplete_required_fields, path)}
      _ -> {:error, error(:invalid_type, path)}
    end
  end

  defp exact_constant(map, key, expected, code, path) do
    case Map.fetch(map, key) do
      {:ok, ^expected} -> :ok
      {:ok, value} when is_binary(value) -> {:error, error(code, path)}
      {:ok, _value} -> {:error, error(:invalid_type, path)}
      :error -> {:error, error(:incomplete_required_fields, path)}
    end
  end

  defp exact_fields(map, required, path, optional \\ [])

  defp exact_fields(map, required, path, optional) when is_map(map) do
    keys = Map.keys(map)

    cond do
      not Enum.all?(keys, &is_binary/1) ->
        {:error, error(:invalid_type, path)}

      Enum.any?(keys, &(&1 not in required and &1 not in optional)) ->
        {:error, error(:unknown_fields, path)}

      Enum.any?(required, &(not Map.has_key?(map, &1))) ->
        {:error, error(:incomplete_required_fields, path)}

      true ->
        :ok
    end
  end

  defp exact_fields(_map, _required, path, _optional), do: {:error, error(:invalid_type, path)}

  defp plain_record?(value) when is_map(value),
    do: not is_struct(value) and Enum.all?(Map.keys(value), &is_binary/1)

  defp plain_record?(_value), do: false

  defp bounded_string(value, path) when is_binary(value) do
    with :ok <- valid_utf8(value, path) do
      bounded_binary(value, @max_string_bytes, path)
    end
  end

  defp bounded_string(_value, path), do: {:error, error(:invalid_type, path)}

  defp bounded_binary(value, max, path) when is_binary(value),
    do: if(byte_size(value) <= max, do: :ok, else: {:error, error(:unbounded_value, path)})

  defp bounded_list(value, max), do: bounded_list(value, max, 0)

  defp bounded_list([], _max, size), do: {:ok, size}

  defp bounded_list([_head | _tail], max, size) when size >= max,
    do: :too_many

  defp bounded_list([_head | tail], max, size), do: bounded_list(tail, max, size + 1)
  defp bounded_list(_value, _max, _size), do: :improper

  defp valid_utf8(value, path) when is_binary(value),
    do: if(String.valid?(value), do: :ok, else: {:error, error(:invalid_utf8, path)})

  defp decode_base64url(value, path, max_encoded) when is_binary(value) do
    cond do
      value == "" or byte_size(value) > max_encoded ->
        {:error, error(:invalid_base64, path)}

      not Regex.match?(~r/^[A-Za-z0-9_-]+$/, value) ->
        {:error, error(:invalid_base64, path)}

      rem(byte_size(value), 4) == 1 ->
        {:error, error(:invalid_base64, path)}

      true ->
        case Base.url_decode64(value, padding: false) do
          {:ok, bytes} ->
            valid_decoded_base64(bytes, value, path)

          _ ->
            {:error, error(:invalid_base64, path)}
        end
    end
  end

  defp decode_base64url(_value, path, _max_encoded), do: {:error, error(:invalid_base64, path)}

  defp valid_decoded_base64(bytes, value, path) do
    if Base.url_encode64(bytes, padding: false) == value,
      do: {:ok, bytes},
      else: {:error, error(:invalid_base64, path)}
  end

  defp exact_binary_size(value, size, path) when is_binary(value),
    do: if(byte_size(value) == size, do: :ok, else: {:error, error(:invalid_value, path)})

  defp verification_time(opts) do
    case Keyword.get(opts, :now, System.system_time(:millisecond)) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      %DateTime{} = value -> {:ok, DateTime.to_unix(value, :millisecond)}
      value when is_binary(value) -> parse_timestamp(value, "$.now")
      _ -> {:error, error(:invalid_timestamp, "$.now")}
    end
  end

  defp parse_timestamp(value, path) when is_binary(value) do
    with :ok <- bounded_string(value, path),
         true <- Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/, value),
         {:ok, datetime, 0} <- DateTime.from_iso8601(value),
         true <- datetime.year >= 1970 and datetime.year <= 9999 do
      {:ok, DateTime.to_unix(datetime, :millisecond)}
    else
      _ -> {:error, error(:invalid_timestamp, path)}
    end
  end

  defp parse_timestamp(_value, path), do: {:error, error(:invalid_timestamp, path)}
  defp optional_timestamp(nil, _path), do: {:ok, nil}
  defp optional_timestamp(value, path), do: parse_timestamp(value, path)
  defp ordered_timestamps(from, until, _path) when until > from, do: :ok
  defp ordered_timestamps(_from, _until, path), do: {:error, error(:invalid_timestamp, path)}
  defp valid_revocation(nil, _from, _path), do: :ok
  defp valid_revocation(revoked, from, _path) when revoked >= from, do: :ok
  defp valid_revocation(_revoked, _from, path), do: {:error, error(:invalid_timestamp, path)}
  defp timestamp_in_bounds(value, _path) when is_integer(value) and value >= 0, do: :ok
  defp timestamp_in_bounds(_value, path), do: {:error, error(:invalid_timestamp, path)}

  @doc "Return the lowercase SHA-256 digest used by persisted signed records."
  @spec digest(binary()) :: binary()
  def digest(bytes) when is_binary(bytes), do: "sha256:" <> digest_hex(bytes)
  defp digest_hex(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp error(code, path), do: %{code: code, path: path}
  defp relocate(%{code: code, path: "$"}, prefix), do: %{code: code, path: prefix}

  defp relocate(%{code: code, path: "$" <> suffix}, prefix),
    do: %{code: code, path: prefix <> suffix}

  defp preflight_json(bytes, path) do
    with {:ok, index} <- scan_value(bytes, skip_whitespace(bytes, 0), 0, path),
         index <- skip_whitespace(bytes, index),
         true <- index == byte_size(bytes) do
      :ok
    else
      {:error, _} = failure -> failure
      false -> {:error, error(:invalid_json, path)}
    end
  end

  defp scan_value(_bytes, index, _depth, path) when index < 0,
    do: {:error, error(:invalid_json, path)}

  defp scan_value(bytes, index, _depth, path) when index >= byte_size(bytes),
    do: {:error, error(:invalid_json, path)}

  defp scan_value(bytes, index, depth, path),
    do: scan_value_byte(:binary.at(bytes, index), bytes, index, depth, path)

  defp scan_value_byte(?{, bytes, index, depth, path),
    do: scan_object(bytes, index + 1, depth, path)

  defp scan_value_byte(?[, bytes, index, depth, path),
    do: scan_array(bytes, index + 1, depth, path)

  defp scan_value_byte(?", bytes, index, _depth, path), do: scan_string(bytes, index, path)

  defp scan_value_byte(?t, bytes, index, _depth, path),
    do: scan_literal(bytes, index, "true", path)

  defp scan_value_byte(?f, bytes, index, _depth, path),
    do: scan_literal(bytes, index, "false", path)

  defp scan_value_byte(?n, bytes, index, _depth, path),
    do: scan_literal(bytes, index, "null", path)

  defp scan_value_byte(?-, bytes, index, _depth, path), do: scan_number(bytes, index, path)

  defp scan_value_byte(digit, bytes, index, _depth, path) when digit in ?0..?9,
    do: scan_number(bytes, index, path)

  defp scan_value_byte(_byte, _bytes, _index, _depth, path),
    do: {:error, error(:invalid_json, path)}

  defp scan_object(_bytes, _index, depth, path) when depth >= @max_depth,
    do: {:error, error(:unbounded_value, path)}

  defp scan_object(bytes, index, depth, path),
    do:
      scan_object_members(bytes, skip_whitespace(bytes, index), depth + 1, path, MapSet.new(), 0)

  defp scan_object_members(bytes, index, depth, path, keys, count) do
    cond do
      index >= byte_size(bytes) ->
        {:error, error(:invalid_json, path)}

      :binary.at(bytes, index) == ?} ->
        {:ok, index + 1}

      count >= @max_object_members ->
        {:error, error(:unbounded_value, path)}

      :binary.at(bytes, index) != ?" ->
        {:error, error(:invalid_json, path)}

      true ->
        scan_object_member(bytes, index, depth, path, keys, count)
    end
  end

  defp scan_object_member(bytes, index, depth, path, keys, count) do
    with {:ok, key_end} <- scan_string(bytes, index, path),
         key_raw = binary_part(bytes, index, key_end - index),
         :ok <- bounded_binary(key_raw, @max_string_bytes + 2, path),
         {:ok, key} <- Jason.decode(key_raw) do
      case MapSet.member?(keys, key) do
        true -> {:error, error(:duplicate_json_key, path <> "." <> key)}
        false -> scan_object_member_value(bytes, key_end, depth, path, keys, count, key)
      end
    else
      {:error, _} = failure -> failure
      _ -> {:error, error(:invalid_json, path)}
    end
  end

  defp scan_object_member_value(bytes, key_end, depth, path, keys, count, key) do
    with colon <- skip_whitespace(bytes, key_end),
         true <- colon < byte_size(bytes) and :binary.at(bytes, colon) == ?:,
         {:ok, value_end} <-
           scan_value(bytes, skip_whitespace(bytes, colon + 1), depth, path <> "." <> key),
         next <- skip_whitespace(bytes, value_end) do
      scan_object_member_tail(bytes, next, depth, path, keys, count, key)
    else
      {:error, _} = failure -> failure
      _ -> {:error, error(:invalid_json, path)}
    end
  end

  defp scan_object_member_tail(bytes, next, depth, path, keys, count, key) do
    cond do
      next < byte_size(bytes) and :binary.at(bytes, next) == ?, ->
        scan_object_members(
          bytes,
          skip_whitespace(bytes, next + 1),
          depth,
          path,
          MapSet.put(keys, key),
          count + 1
        )

      next < byte_size(bytes) and :binary.at(bytes, next) == ?} ->
        {:ok, next + 1}

      true ->
        {:error, error(:invalid_json, path)}
    end
  end

  defp scan_array(_bytes, _index, depth, path) when depth >= @max_depth,
    do: {:error, error(:unbounded_value, path)}

  defp scan_array(bytes, index, depth, path),
    do: scan_array_items(bytes, skip_whitespace(bytes, index), depth + 1, path, 0)

  defp scan_array_items(bytes, index, depth, path, count) do
    cond do
      index >= byte_size(bytes) -> {:error, error(:invalid_json, path)}
      :binary.at(bytes, index) == ?] -> {:ok, index + 1}
      count >= @max_array_items -> {:error, error(:unbounded_value, path)}
      true -> scan_array_item(bytes, index, depth, path, count)
    end
  end

  defp scan_array_item(bytes, index, depth, path, count) do
    with {:ok, value_end} <- scan_value(bytes, index, depth, path <> "[#{count}]"),
         next <- skip_whitespace(bytes, value_end) do
      cond do
        next < byte_size(bytes) and :binary.at(bytes, next) == ?, ->
          scan_array_items(bytes, skip_whitespace(bytes, next + 1), depth, path, count + 1)

        next < byte_size(bytes) and :binary.at(bytes, next) == ?] ->
          {:ok, next + 1}

        true ->
          {:error, error(:invalid_json, path)}
      end
    else
      failure -> failure
    end
  end

  defp scan_string(bytes, index, path) when index < byte_size(bytes) do
    max_bytes =
      if String.ends_with?(path, ".payload"),
        do: @max_encoded_payload_bytes + 2,
        else: @max_string_bytes + 2

    if :binary.at(bytes, index) == ?",
      do: scan_string_bytes(bytes, index + 1, index, path, max_bytes),
      else: {:error, error(:invalid_json, path)}
  end

  defp scan_string(_bytes, _index, path), do: {:error, error(:invalid_json, path)}

  defp scan_string_bytes(bytes, index, _start, path, _max_bytes) when index >= byte_size(bytes),
    do: {:error, error(:invalid_json, path)}

  defp scan_string_bytes(bytes, index, start, path, max_bytes) do
    case :binary.at(bytes, index) do
      ?" ->
        if(index - start <= max_bytes - 1,
          do: {:ok, index + 1},
          else: {:error, error(:unbounded_value, path)}
        )

      ?\\ ->
        if(index + 1 >= byte_size(bytes),
          do: {:error, error(:invalid_json, path)},
          else: scan_string_bytes(bytes, index + 2, start, path, max_bytes)
        )

      byte when byte < 0x20 ->
        {:error, error(:invalid_json, path)}

      _byte ->
        scan_string_bytes(bytes, index + 1, start, path, max_bytes)
    end
  end

  defp scan_literal(bytes, index, literal, path) do
    size = byte_size(literal)

    if index + size <= byte_size(bytes) and binary_part(bytes, index, size) == literal,
      do: {:ok, index + size},
      else: {:error, error(:invalid_json, path)}
  end

  defp scan_number(bytes, index, path) do
    {next, invalid_integer} = scan_number_bytes(bytes, index, index, false)

    cond do
      invalid_integer ->
        {:error, error(:invalid_scalar, path)}

      next == index ->
        {:error, error(:invalid_json, path)}

      next < byte_size(bytes) and :binary.at(bytes, next) not in [32, 9, 10, 13, ?,, ?], ?}] ->
        {:error, error(:invalid_json, path)}

      true ->
        {:ok, next}
    end
  end

  defp scan_number_bytes(bytes, index, _start, invalid) when index >= byte_size(bytes),
    do: {index, invalid}

  defp scan_number_bytes(bytes, index, start, invalid) do
    byte = :binary.at(bytes, index)

    cond do
      byte in [?., ?e, ?E] ->
        scan_number_bytes(bytes, index + 1, start, true)

      byte in ?0..?9 or (index == start and byte == ?-) ->
        scan_number_bytes(bytes, index + 1, start, invalid)

      true ->
        {index, invalid}
    end
  end

  defp skip_whitespace(bytes, index) when index < byte_size(bytes) do
    if :binary.at(bytes, index) in [32, 9, 10, 13],
      do: skip_whitespace(bytes, index + 1),
      else: index
  end

  defp skip_whitespace(_bytes, index), do: index

  @doc "Canonical JSON used by all signed frontend documents and snapshots."
  @spec canonical_json(term()) :: binary()
  def canonical_json(value) when is_map(value) do
    value
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map_join(",", fn key ->
      Jason.encode!(key) <> ":" <> canonical_json(Map.get(value, key))
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
end
