defmodule CadenceWeb.ApplicationReleaseRegistry do
  @moduledoc "Generic lookup of release metadata contributed by application owners."

  alias Cadence.Applications.{ReleaseContribution, ReleaseRegistry}
  alias Cadence.Repo
  alias CadenceWeb.FrontendReleaseCatalog

  @publication_config_key {CadenceWeb.FrontendReleasePublication, :publication_config}

  @type federation :: :module_federation | :native_federation

  @type release :: %{
          federation: federation(),
          release_id: binary(),
          remote_name: binary(),
          manifest_path: binary(),
          exposed_module: binary()
        }

  @type key :: {binary(), pos_integer(), binary(), pos_integer()}

  @type snapshot :: %{
          source: :static | :database,
          entries: [{key(), release()}]
        }

  @type error_reason ::
          :no_history
          | {:database_unavailable, term()}
          | {:integrity_failure, term()}

  @spec snapshot() :: {:ok, snapshot()} | {:error, error_reason()}
  def snapshot do
    with {:ok, rows} <- read_catalog_rows() do
      build_snapshot(rows)
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, {:database_unavailable, error}}

    error ->
      {:error, {:integrity_failure, error}}
  end

  @spec all() :: [{key(), release()}] | {:error, error_reason()}
  def all do
    case snapshot() do
      {:ok, %{entries: entries}} -> entries
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch(binary(), pos_integer(), binary(), pos_integer()) ::
          {:ok, release()} | {:error, :unknown_application_release | error_reason()}
  def fetch(application_key, application_version, surface_id, surface_version)
      when is_binary(application_key) and is_integer(application_version) and
             is_binary(surface_id) and is_integer(surface_version) do
    case snapshot() do
      {:ok, snapshot} ->
        fetch_from_snapshot(
          snapshot,
          application_key,
          application_version,
          surface_id,
          surface_version
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch(_application_key, _application_version, _surface_id, _surface_version),
    do: {:error, :unknown_application_release}

  @spec fetch_from_snapshot(snapshot(), binary(), pos_integer(), binary(), pos_integer()) ::
          {:ok, release()} | {:error, :unknown_application_release | :no_history}
  def fetch_from_snapshot(
        %{source: source, entries: entries},
        application_key,
        application_version,
        surface_id,
        surface_version
      )
      when is_list(entries) and is_binary(application_key) and is_integer(application_version) and
             is_binary(surface_id) and is_integer(surface_version) do
    key = {application_key, application_version, surface_id, surface_version}

    case Enum.find(entries, fn {entry_key, _release} -> entry_key == key end) do
      {_key, release} ->
        {:ok, release}

      nil ->
        case source do
          :database -> {:error, :no_history}
          :static -> {:error, :unknown_application_release}
        end
    end
  end

  def fetch_from_snapshot(
        _snapshot,
        _application_key,
        _application_version,
        _surface_id,
        _surface_version
      ),
      do: {:error, :unknown_application_release}

  defp read_catalog_rows do
    case Repo.query(catalog_query()) do
      {:ok, %{rows: rows}} when rows != [] ->
        {:ok, Enum.map(rows, &decode_row/1)}

      {:ok, %{rows: []}} ->
        {:error, {:integrity_failure, :activation_control_missing}}

      {:error, error} ->
        {:error, {:database_unavailable, error}}
    end
  end

  defp build_snapshot([first | rows]) do
    with :ok <- consistent_control(first, rows) do
      case first.control_epoch do
        0 -> build_static_snapshot(first)
        1 -> build_database_snapshot(first, rows)
        _other -> {:error, {:integrity_failure, :invalid_cutover_epoch}}
      end
    end
  end

  defp build_snapshot(_rows),
    do: {:error, {:integrity_failure, :activation_control_missing}}

  defp build_static_snapshot(row) do
    if row.cutover_at != nil or row.legacy_catalog_publication_id != nil do
      {:error, {:integrity_failure, :invalid_pre_cutover_control}}
    else
      {:ok, %{source: :static, entries: static_entries()}}
    end
  end

  defp build_database_snapshot(row, rows) do
    cond do
      not is_binary(row.cutover_at) ->
        {:error, {:integrity_failure, :cutover_timestamp_missing}}

      row.generation_id == nil ->
        {:error, {:integrity_failure, :active_generation_missing}}

      true ->
        validate_database_snapshot(row, rows)
    end
  end

  defp validate_database_snapshot(row, rows) do
    bindings = Enum.reject([row | rows], &is_nil(&1.binding_generation_id))

    with :ok <- validate_generation(row, bindings),
         {:ok, catalog} <- validate_catalog(row),
         {:ok, entries} <- validate_bindings(bindings, catalog.entries),
         :ok <- validate_snapshot_digest(row, entries) do
      {:ok, %{source: :database, entries: Enum.map(entries, &entry_pair/1)}}
    end
  end

  defp validate_generation(row, bindings) do
    with :ok <- validate_generation_identity(row),
         :ok <- validate_generation_bindings(row, bindings) do
      validate_generation_predecessor(row)
    end
  end

  defp validate_generation_identity(row) do
    if row.generation_catalog_publication_id != row.catalog_publication_id,
      do: integrity(:generation_catalog_mismatch),
      else: :ok
  end

  defp validate_generation_bindings(row, bindings) do
    cond do
      duplicate_binding_identity?(bindings) ->
        integrity(:duplicate_binding_identity)

      duplicate_host_identity?(bindings) ->
        integrity(:duplicate_application_surface_identity)

      row.generation_sequence != row.catalog_sequence ->
        integrity(:generation_sequence_mismatch)

      row.generation_identity_count != row.catalog_identity_count ->
        integrity(:generation_identity_count_mismatch)

      not is_binary(row.generation_inserted_at) ->
        integrity(:generation_timestamp_missing)

      length(bindings) != row.generation_identity_count or bindings == [] ->
        integrity(:generation_bindings_incomplete)

      true ->
        :ok
    end
  end

  defp validate_generation_predecessor(row) do
    if valid_predecessor?(row) and valid_control_predecessor?(row) do
      :ok
    else
      integrity(:invalid_generation_predecessor)
    end
  end

  defp validate_catalog(row) do
    result =
      with true <- row.catalog_acceptance_state == "accepted",
           true <- valid_digest?(row.catalog_digest),
           true <- valid_digest?(row.catalog_signed_document_digest),
           true <- is_binary(row.catalog_signing_key_id),
           true <- row.catalog_signing_role == "promotion",
           true <- valid_catalog_transition?(row.catalog_transition),
           true <- valid_positive_integer?(row.catalog_sequence),
           true <- valid_identity_count?(row.catalog_identity_count),
           true <- valid_digest?(row.catalog_snapshot_digest),
           true <- catalog_window_valid?(row),
           {:ok, entries} <- accepted_catalog_entries(row),
           {:ok, entries} <- validate_release_references(row.catalog_release_references, entries) do
        {:ok, %{entries: entries}}
      else
        false -> integrity(:catalog_metadata_mismatch)
        {:error, _reason} -> integrity(:catalog_metadata_mismatch)
        _other -> integrity(:catalog_metadata_mismatch)
      end

    result
  end

  defp accepted_catalog_entries(row) do
    state = row.catalog_accepted_state

    with true <- is_map(state),
         true <- exact_map_keys?(state, ["sequence", "publishedAt", "digest", "entries"]),
         true <- state["sequence"] == row.catalog_sequence,
         true <- state["digest"] == row.catalog_digest,
         true <- timestamp_string_matches?(state["publishedAt"], row.catalog_published_at),
         entries when is_list(entries) <- state["entries"],
         true <- length(entries) == row.catalog_identity_count,
         {:ok, entries} <- validate_catalog_entries(entries) do
      {:ok, entries}
    else
      _ -> {:error, :invalid_accepted_catalog_state}
    end
  end

  defp validate_catalog_entries(entries) do
    Enum.reduce_while(
      entries,
      {:ok, MapSet.new(), MapSet.new(), MapSet.new(), MapSet.new(), []},
      fn
        entry, {:ok, identities, release_ids, remote_names, exposures, acc} ->
          with {:ok, normalized} <- normalize_catalog_entry(entry),
               identity_key <- identity_key(normalized.identity),
               release_values <- release_values(normalized),
               remote_values <- remote_values(normalized),
               exposure_values <- exposure_values(normalized),
               false <- MapSet.member?(identities, identity_key),
               false <- Enum.any?(release_values, &MapSet.member?(release_ids, &1)),
               false <- Enum.any?(remote_values, &MapSet.member?(remote_names, &1)),
               false <- Enum.any?(exposure_values, &MapSet.member?(exposures, &1)) do
            {:cont,
             {:ok, MapSet.put(identities, identity_key),
              Enum.reduce(release_values, release_ids, &MapSet.put(&2, &1)),
              Enum.reduce(remote_values, remote_names, &MapSet.put(&2, &1)),
              Enum.reduce(exposure_values, exposures, &MapSet.put(&2, &1)), [normalized | acc]}}
          else
            _ -> {:halt, {:error, :invalid_accepted_catalog_entry}}
          end
      end
    )
    |> case do
      {:ok, _identities, _release_ids, _remote_names, _exposures, entries} ->
        {:ok, Enum.sort_by(entries, &identity_key(&1.identity))}

      failure ->
        failure
    end
  end

  defp normalize_catalog_entry(entry) when is_map(entry) do
    keys = Map.keys(entry) |> Enum.sort()
    required_keys = ["current", "identity"]
    fallback_keys = ["current", "fallback", "identity"]

    case keys do
      keys when keys in [required_keys, fallback_keys] ->
        if valid_catalog_entry_data?(entry) do
          {:ok,
           %{
             identity: Map.get(entry, "identity"),
             current: Map.get(entry, "current"),
             fallback: Map.get(entry, "fallback")
           }}
        else
          {:error, :invalid_accepted_catalog_entry}
        end

      _other ->
        {:error, :invalid_accepted_catalog_entry}
    end
  end

  defp normalize_catalog_entry(_entry), do: {:error, :invalid_accepted_catalog_entry}

  defp valid_catalog_entry_data?(entry) do
    identity = Map.get(entry, "identity")
    current = Map.get(entry, "current")
    fallback = Map.get(entry, "fallback")

    valid_catalog_identity?(identity) and valid_release_state?(current) and
      release_matches_identity?(current, identity) and
      valid_fallback_release?(fallback, current, identity)
  end

  defp valid_fallback_release?(nil, _current, _identity), do: true

  defp valid_fallback_release?(fallback, current, identity) do
    valid_release_state?(fallback) and release_matches_identity?(fallback, identity) and
      fallback["releaseId"] != current["releaseId"]
  end

  defp validate_release_references(references, entries) when is_map(references) do
    with true <- exact_map_keys?(references, ["entries"]),
         reference_entries when is_list(reference_entries) <- references["entries"],
         true <- length(reference_entries) == length(entries),
         {:ok, normalized} <- normalize_release_references(reference_entries),
         true <- unique_reference_identities?(normalized) do
      normalized
      |> Map.new(&{identity_key(&1.identity), &1})
      |> match_release_references(entries)
    else
      _ -> {:error, :invalid_release_references}
    end
  end

  defp validate_release_references(_references, _entries),
    do: {:error, :invalid_release_references}

  defp match_release_references(references_by_identity, entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      reference = Map.get(references_by_identity, identity_key(entry.identity))

      if (reference && reference.current_release_id == entry.current["releaseId"]) and
           reference.fallback_release_id == release_id(entry.fallback) do
        {:cont,
         {:ok,
          [
            Map.merge(entry, %{
              current_payload_digest: reference.current_payload_digest,
              current_signed_document_digest: reference.current_signed_document_digest,
              fallback_payload_digest: reference.fallback_payload_digest,
              fallback_signed_document_digest: reference.fallback_signed_document_digest
            })
            | acc
          ]}}
      else
        {:halt, {:error, :release_reference_mismatch}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      failure -> failure
    end
  end

  defp normalize_release_references(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      with true <- is_map(entry),
           keys = Map.keys(entry) |> Enum.sort(),
           true <-
             keys in [
               ["currentDigest", "currentReleaseId", "currentSignedDocumentDigest", "identity"],
               [
                 "currentDigest",
                 "currentReleaseId",
                 "currentSignedDocumentDigest",
                 "fallbackDigest",
                 "fallbackReleaseId",
                 "fallbackSignedDocumentDigest",
                 "identity"
               ]
             ],
           true <- valid_catalog_identity?(entry["identity"]),
           true <- valid_release_id?(entry["currentReleaseId"], nil),
           true <- valid_digest?(entry["currentDigest"]),
           true <- valid_digest?(entry["currentSignedDocumentDigest"]),
           true <- valid_fallback_reference?(entry) do
        {:cont,
         {:ok,
          [
            %{
              identity: entry["identity"],
              current_release_id: entry["currentReleaseId"],
              current_payload_digest: entry["currentDigest"],
              current_signed_document_digest: entry["currentSignedDocumentDigest"],
              fallback_release_id: entry["fallbackReleaseId"],
              fallback_payload_digest: entry["fallbackDigest"],
              fallback_signed_document_digest: entry["fallbackSignedDocumentDigest"]
            }
            | acc
          ]}}
      else
        _ -> {:halt, {:error, :invalid_release_reference}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      failure -> failure
    end
  end

  defp valid_fallback_reference?(entry) do
    fallback_values =
      [entry["fallbackReleaseId"], entry["fallbackDigest"], entry["fallbackSignedDocumentDigest"]]

    case fallback_values do
      [release_id, digest, signed_digest] ->
        (is_nil(release_id) and is_nil(digest) and is_nil(signed_digest)) or
          (valid_release_id?(release_id, nil) and valid_digest?(digest) and
             valid_digest?(signed_digest))
    end
  end

  defp unique_reference_identities?(references) do
    identities = Enum.map(references, &identity_key(&1.identity))
    length(identities) == length(Enum.uniq(identities))
  end

  defp release_values(%{current: current, fallback: fallback}),
    do: [current["releaseId"] | if(fallback, do: [fallback["releaseId"]], else: [])]

  defp remote_values(%{current: current, fallback: fallback}),
    do: [current["remoteName"] | if(fallback, do: [fallback["remoteName"]], else: [])]

  defp exposure_values(%{current: current, fallback: fallback}),
    do: [
      {current["remoteName"], current["exposedModule"]}
      | if(fallback,
          do: [{fallback["remoteName"], fallback["exposedModule"]}],
          else: []
        )
    ]

  defp valid_release_state?(release) when is_map(release) do
    valid_release_shape?(release) and
      valid_release_identity?(release) and
      valid_release_delivery?(release) and
      valid_release_provenance?(release)
  end

  defp valid_release_state?(_release), do: false

  defp valid_release_shape?(release) do
    exact_map_keys?(release, [
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
    ]) and release["schema"] == "cadence.first-party-frontend-release.v1"
  end

  defp valid_release_identity?(release) do
    valid_identity?(release["application"]) and
      valid_identity?(release["package"]) and
      valid_identity?(release["surface"]) and
      valid_release_id?(release["releaseId"], release)
  end

  defp valid_release_delivery?(release) do
    release["transport"] == "module_federation" and
      valid_identifier?(release["remoteName"]) and
      valid_exposed_module?(release["exposedModule"]) and
      valid_artifact_base_url?(release["artifactBaseUrl"], release) and
      valid_artifact_state?(release["manifest"], release["artifacts"])
  end

  defp valid_release_provenance?(release) do
    valid_host_compatibility?(release["hostCompatibility"]) and
      valid_provenance?(release["provenance"]) and
      valid_timestamp_string?(release["releasedAt"])
  end

  defp valid_identity?(identity) when is_map(identity) do
    exact_map_keys?(identity, ["id", "version"]) and
      valid_identifier?(identity["id"]) and valid_positive_integer?(identity["version"])
  end

  defp valid_identity?(_identity), do: false

  defp valid_catalog_identity?(identity) when is_map(identity) do
    exact_map_keys?(identity, ["application", "package", "surface"]) and
      valid_identity?(identity["application"]) and
      valid_identity?(identity["package"]) and
      valid_identity?(identity["surface"])
  end

  defp valid_catalog_identity?(_identity), do: false

  defp release_matches_identity?(release, identity) do
    release["application"] == identity["application"] and
      release["package"] == identity["package"] and
      release["surface"] == identity["surface"]
  end

  defp valid_release_id?(value, release) when is_binary(value) do
    Regex.match?(~r/^sha256:[0-9a-f]{64}$/, value) and
      (is_nil(release) or
         value ==
           FrontendReleaseCatalog.digest(
             release
             |> Map.delete("releaseId")
             |> Map.delete("artifactBaseUrl")
             |> then(&FrontendReleaseCatalog.canonical_json/1)
           ))
  end

  defp valid_release_id?(_value, _release), do: false

  defp valid_artifact_state?(manifest, artifacts) when is_map(manifest) and is_list(artifacts) do
    exact_map_keys?(manifest, ["path", "sha256", "size", "mediaType"]) and
      artifacts != [] and length(artifacts) <= 2_048 and
      Enum.all?(artifacts, &valid_artifact_state?/1) and
      Enum.map(artifacts, & &1["path"]) ==
        Enum.sort_by(artifacts, & &1["path"]) |> Enum.map(& &1["path"]) and
      length(Enum.map(artifacts, & &1["path"])) ==
        length(Enum.uniq(Enum.map(artifacts, & &1["path"]))) and
      Enum.any?(artifacts, &(&1 == manifest))
  end

  defp valid_artifact_state?(_manifest, _artifacts), do: false

  defp valid_artifact_state?(artifact) when is_map(artifact) do
    exact_map_keys?(artifact, ["path", "sha256", "size", "mediaType"]) and
      valid_artifact_path?(artifact["path"]) and
      valid_hex_sha256?(artifact["sha256"]) and
      is_integer(artifact["size"]) and artifact["size"] >= 0 and artifact["size"] <= 100_000_000 and
      valid_media_type?(artifact["mediaType"])
  end

  defp valid_artifact_state?(_artifact), do: false

  defp valid_artifact_path?(value) when is_binary(value) do
    byte_size(value) > 0 and byte_size(value) <= 256 and String.valid?(value) and
      not String.starts_with?(value, "/") and not String.contains?(value, "\\") and
      Enum.all?(String.split(value, "/"), &(&1 not in ["", ".", ".."]))
  end

  defp valid_artifact_path?(_value), do: false

  defp valid_media_type?(value) when is_binary(value) do
    byte_size(value) <= 128 and String.valid?(value) and
      Regex.match?(
        ~r/^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}\/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}$/,
        value
      )
  end

  defp valid_media_type?(_value), do: false

  defp valid_host_compatibility?(compatibility) when is_map(compatibility) do
    exact_map_keys?(compatibility, ["hostContract", "compatibility", "vueRange"]) and
      compatibility["hostContract"] == "cadence.application-host.v1" and
      compatibility["vueRange"] == "^3.5.40" and
      exact_map_keys?(compatibility["compatibility"], [
        "cadenceApplicationContract",
        "cadenceSurfaceContract",
        "cadenceFederatedRendererContract",
        "cadenceThemeContract"
      ]) and
      Enum.all?(Map.values(compatibility["compatibility"]), &(&1 == 1))
  end

  defp valid_host_compatibility?(_compatibility), do: false

  defp valid_provenance?(provenance) when is_map(provenance) do
    exact_map_keys?(provenance, [
      "sourceRepository",
      "sourceRevision",
      "buildId",
      "builder",
      "workflow",
      "builtAt"
    ]) and
      valid_https_url?(provenance["sourceRepository"]) and
      valid_source_revision?(provenance["sourceRevision"]) and
      valid_token?(provenance["buildId"]) and
      valid_token?(provenance["builder"]) and
      valid_token?(provenance["workflow"]) and
      valid_timestamp_string?(provenance["builtAt"])
  end

  defp valid_provenance?(_provenance), do: false

  defp valid_artifact_base_url?(value, release) when is_binary(value) and is_map(release) do
    application_id = release["application"]["id"]
    release_id = release["releaseId"]
    expected_path = "/releases/" <> application_id <> "/" <> release_id <> "/artifacts/"

    case URI.parse(value) do
      %URI{
        scheme: "https",
        host: host,
        path: ^expected_path,
        query: nil,
        fragment: nil,
        userinfo: nil,
        port: port
      }
      when is_binary(host) ->
        origin =
          "https://" <> host <> if(is_integer(port) and port != 443, do: ":#{port}", else: "")

        origin in allowed_origins() and value == origin <> expected_path

      _ ->
        false
    end
  end

  defp valid_artifact_base_url?(_value, _release), do: false

  defp valid_token?(value) when is_binary(value),
    do: byte_size(value) > 0 and byte_size(value) <= 512 and String.valid?(value)

  defp valid_token?(_value), do: false

  defp valid_identifier?(value) when is_binary(value) do
    byte_size(value) <= 128 and String.valid?(value) and
      Regex.match?(~r/^[a-z][a-z0-9._-]{0,127}$/, value)
  end

  defp valid_identifier?(_value), do: false

  defp valid_exposed_module?(value) when is_binary(value) do
    byte_size(value) <= 512 and String.valid?(value) and
      Regex.match?(~r/^\.[\/][A-Za-z][A-Za-z0-9._-]{0,127}$/, value)
  end

  defp valid_exposed_module?(_value), do: false

  defp valid_source_revision?(value) when is_binary(value),
    do: Regex.match?(~r/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/, value)

  defp valid_source_revision?(_value), do: false

  defp valid_https_url?(value) when is_binary(value) do
    byte_size(value) <= 512 and String.valid?(value) and
      not Enum.any?(String.to_charlist(value), &(&1 <= 0x20)) and
      not Enum.any?(["\\", "%", "?", "#"], &String.contains?(value, &1)) and
      String.starts_with?(value, "https://") and
      case split_authority_path(binary_part(value, 8, byte_size(value) - 8)) do
        {authority, path} ->
          valid_raw_authority?(authority) and (path == "" or String.starts_with?(path, "/"))
      end
  end

  defp valid_https_url?(_value), do: false

  defp split_authority_path(rest) do
    case :binary.match(rest, "/") do
      :nomatch ->
        {rest, ""}

      {index, 1} ->
        {binary_part(rest, 0, index), binary_part(rest, index, byte_size(rest) - index)}
    end
  end

  defp valid_raw_authority?(authority) do
    case Regex.run(
           ~r/^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*)(?::([1-9][0-9]{0,4}))?$/,
           authority,
           capture: :all_but_first
         ) do
      [host] when host != "" ->
        true

      [host, nil] when host != "" ->
        true

      [host, port] when host != "" and is_binary(port) ->
        String.to_integer(port) <= 65_535 and String.to_integer(port) != 443

      _ ->
        false
    end
  end

  defp valid_timestamp_string?(value) when is_binary(value) do
    byte_size(value) <= 512 and String.valid?(value) and
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/, value) and
      case DateTime.from_iso8601(value) do
        {:ok, datetime, 0} -> datetime.year >= 1970 and datetime.year <= 9999
        _ -> false
      end
  end

  defp valid_timestamp_string?(_value), do: false

  defp valid_digest?(value) when is_binary(value),
    do: Regex.match?(~r/^sha256:[0-9a-f]{64}$/, value)

  defp valid_digest?(_value), do: false

  defp valid_hex_sha256?(value) when is_binary(value),
    do: Regex.match?(~r/^[0-9a-f]{64}$/, value)

  defp valid_hex_sha256?(_value), do: false

  defp valid_positive_integer?(value), do: is_integer(value) and value > 0

  defp valid_identity_count?(value), do: is_integer(value) and value > 0 and value <= 512

  defp valid_catalog_transition?(value),
    do: value in ["initial", "legacy_successor", "promotion", "rollback"]

  defp catalog_window_valid?(row) do
    with {:ok, published_at} <- timestamp_milliseconds(row.catalog_published_at),
         {:ok, expires_at} <- timestamp_milliseconds(row.catalog_expires_at),
         true <- expires_at > published_at,
         true <- expires_at - published_at <= 31 * 24 * 60 * 60 * 1_000 do
      true
    else
      _ -> false
    end
  end

  defp timestamp_milliseconds(value) when is_binary(value) do
    case parse_utc_timestamp(value) do
      {:ok, datetime} -> {:ok, DateTime.to_unix(datetime, :millisecond)}
      _ -> :error
    end
  end

  defp timestamp_milliseconds(_value), do: :error

  defp validate_bindings(bindings, expected_entries) do
    if length(bindings) == length(expected_entries) do
      validate_binding_rows(bindings, expected_entries)
    else
      integrity(:catalog_binding_count_mismatch)
    end
  end

  defp validate_binding_rows(bindings, expected_entries) do
    bindings
    |> Enum.zip(expected_entries)
    |> Enum.reduce_while({:ok, []}, fn {binding_row, expected_entry}, {:ok, acc} ->
      case validate_binding(binding_row, expected_entry) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, _reason} = failure -> {:halt, failure}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      failure -> failure
    end
  end

  defp validate_binding(row, expected_entry) do
    expected_identity = expected_entry.identity
    expected_current = expected_entry.current
    expected_previous = expected_entry.fallback

    with true <- row.binding_generation_id == row.generation_id,
         true <- binding_identity(row) == expected_identity,
         true <- row.binding_current_release_id == expected_current["releaseId"],
         true <-
           row.binding_current_publication_id == field(row.current_publication, "publication_id"),
         true <- row.binding_previous_release_id == release_id(expected_previous),
         true <-
           row.binding_previous_publication_id == previous_publication_id(row, expected_previous),
         {:ok, current} <- validate_release(row, :current, expected_current, expected_entry),
         {:ok, previous} <- validate_optional_release(row, expected_previous, expected_entry),
         true <- previous_release_pair?(row, expected_previous, previous) do
      {:ok, %{identity: expected_identity, current: current, previous: previous}}
    else
      false -> integrity(:catalog_binding_mismatch)
      {:error, _reason} -> integrity(:release_publication_integrity_failure)
    end
  end

  defp validate_release(row, :current, expected_release, expected_entry) do
    validate_release_publication(
      row.current_publication,
      row.current_artifacts,
      expected_release,
      expected_entry.current_payload_digest,
      expected_entry.current_signed_document_digest
    )
  end

  defp validate_optional_release(_row, nil, _expected_entry), do: {:ok, nil}

  defp validate_optional_release(row, expected_release, expected_entry) do
    validate_release_publication(
      row.previous_publication,
      row.previous_artifacts,
      expected_release,
      expected_entry.fallback_payload_digest,
      expected_entry.fallback_signed_document_digest
    )
  end

  defp validate_release_publication(
         publication,
         artifacts,
         expected_release,
         expected_payload_digest,
         expected_signed_document_digest
       )
       when is_map(publication) and is_list(artifacts) and is_map(expected_release) do
    with true <- publication["payload_digest"] == expected_payload_digest,
         true <- publication["signed_document_digest"] == expected_signed_document_digest,
         true <- publication["acceptance_state"] == "accepted",
         true <- release_metadata_matches?(publication, expected_release),
         true <- validate_release_artifacts(artifacts, expected_release["artifacts"], publication) do
      {:ok, %{publication: publication, release: expected_release}}
    else
      false -> {:error, :invalid_release_publication}
      _other -> {:error, :invalid_release_publication}
    end
  end

  defp validate_release_publication(
         _publication,
         _artifacts,
         _expected,
         _expected_payload_digest,
         _expected_signed_document_digest
       ),
       do: {:error, :invalid_release_publication}

  defp release_metadata_matches?(publication, release) do
    release_identity_metadata_matches?(publication, release) and
      release_delivery_metadata_matches?(publication, release) and
      release_security_metadata_matches?(publication, release)
  end

  defp release_identity_metadata_matches?(publication, release) do
    application = release["application"]
    package = release["package"]
    surface = release["surface"]

    publication["publication_id"] != nil and
      publication["release_id"] == release["releaseId"] and
      publication["application_id"] == application["id"] and
      publication["application_version"] == application["version"] and
      publication["package_id"] == package["id"] and
      publication["package_version"] == package["version"] and
      publication["surface_id"] == surface["id"] and
      publication["surface_version"] == surface["version"]
  end

  defp release_delivery_metadata_matches?(publication, release) do
    manifest = release["manifest"]

    publication["remote_name"] == release["remoteName"] and
      publication["exposed_module"] == release["exposedModule"] and
      publication["artifact_base_url"] == release["artifactBaseUrl"] and
      publication["manifest_path"] == manifest["path"] and
      publication["manifest_sha256"] == manifest["sha256"] and
      publication["manifest_size"] == manifest["size"] and
      publication["manifest_media_type"] == manifest["mediaType"] and
      publication["artifact_count"] == length(release["artifacts"])
  end

  defp release_security_metadata_matches?(publication, release) do
    valid_token?(publication["signing_key_id"]) and
      publication["signing_role"] == "release" and
      publication["provenance"] == release["provenance"] and
      timestamp_string_matches?(publication["released_at"], release["releasedAt"])
  end

  defp validate_release_artifacts(actual, expected, publication) when is_list(expected) do
    actual_metadata = Enum.map(actual, &Map.take(&1, ["path", "sha256", "size", "media_type"]))

    expected_metadata =
      Enum.map(expected, fn artifact ->
        artifact
        |> Map.delete("mediaType")
        |> Map.put("media_type", artifact["mediaType"])
      end)

    length(actual) == publication["artifact_count"] and
      actual_metadata == expected_metadata and
      Enum.all?(actual, fn artifact ->
        artifact["object_key"] == "sha256:" <> artifact["sha256"] and
          artifact["object_sha256"] == artifact["sha256"] and
          artifact["object_size"] == artifact["size"]
      end)
  end

  defp validate_release_artifacts(_actual, _expected, _publication),
    do: false

  defp validate_snapshot_digest(row, entries) do
    snapshot = %{
      "schema" => "cadence.first-party-frontend-release-persisted-snapshot.v1",
      "sequence" => row.catalog_sequence,
      "publishedAt" => format_db_timestamp(row.catalog_published_at),
      "expiresAt" => format_db_timestamp(row.catalog_expires_at),
      "transition" => row.catalog_transition,
      "identityCount" => row.catalog_identity_count,
      "entries" =>
        Enum.map(entries, fn entry ->
          %{
            "identity" => entry.identity,
            "current" => snapshot_release(entry.current.publication),
            "previous" =>
              if(entry.previous, do: snapshot_release(entry.previous.publication), else: nil)
          }
        end)
    }

    actual_digest = FrontendReleaseCatalog.digest(FrontendReleaseCatalog.canonical_json(snapshot))

    if actual_digest == row.catalog_snapshot_digest do
      :ok
    else
      integrity(:snapshot_digest_mismatch)
    end
  end

  defp snapshot_release(publication) do
    %{
      "releaseId" => publication["release_id"],
      "payloadDigest" => publication["payload_digest"],
      "signedDocumentDigest" => publication["signed_document_digest"],
      "identity" => %{
        "application" => %{
          "id" => publication["application_id"],
          "version" => publication["application_version"]
        },
        "package" => %{
          "id" => publication["package_id"],
          "version" => publication["package_version"]
        },
        "surface" => %{
          "id" => publication["surface_id"],
          "version" => publication["surface_version"]
        }
      },
      "remoteName" => publication["remote_name"],
      "exposedModule" => publication["exposed_module"],
      "artifactBaseUrl" => publication["artifact_base_url"],
      "manifest" => %{
        "path" => publication["manifest_path"],
        "sha256" => publication["manifest_sha256"],
        "size" => publication["manifest_size"],
        "mediaType" => publication["manifest_media_type"]
      },
      "signingKeyId" => publication["signing_key_id"],
      "signingRole" => publication["signing_role"],
      "releasedAt" => format_db_timestamp(publication["released_at"]),
      "artifactCount" => publication["artifact_count"],
      "provenance" => publication["provenance"]
    }
  end

  defp entry_pair(entry) do
    release = entry.current.release
    identity = entry.identity
    package = release["package"]

    {{identity["application"]["id"], identity["application"]["version"],
      identity["surface"]["id"], identity["surface"]["version"]},
     %{
       federation: :module_federation,
       package_id: package["id"],
       package_version: package["version"],
       release_id: release["releaseId"],
       remote_name: release["remoteName"],
       manifest_path:
         "/releases/" <>
           release["application"]["id"] <>
           "/" <>
           release["releaseId"] <>
           "/artifacts/" <> release["manifest"]["path"],
       exposed_module: release["exposedModule"]
     }}
  end

  defp consistent_control(first, rows) do
    fields = [:control_id, :control_epoch, :cutover_at, :legacy_catalog_publication_id]

    if first.control_count == 1 and first.control_id == 1 and
         Enum.all?(rows, fn row ->
           Enum.all?(fields, &(Map.get(row, &1) == Map.get(first, &1)))
         end) do
      :ok
    else
      integrity(:activation_control_inconsistent)
    end
  end

  defp valid_predecessor?(row) do
    case row.catalog_transition do
      "initial" ->
        row.generation_predecessor_kind == "none" and
          is_nil(row.generation_predecessor_catalog_publication_id)

      "legacy_successor" ->
        row.generation_predecessor_kind == "legacy" and
          is_binary(row.generation_predecessor_catalog_publication_id)

      transition when transition in ["promotion", "rollback"] ->
        row.generation_predecessor_kind == "generation" and
          is_binary(row.generation_predecessor_catalog_publication_id)

      _other ->
        false
    end
  end

  defp valid_control_predecessor?(row) do
    case row.catalog_transition do
      "initial" ->
        valid_initial_control_predecessor?(row)

      "legacy_successor" ->
        valid_legacy_control_predecessor?(row)

      transition when transition in ["promotion", "rollback"] ->
        valid_generation_control_predecessor?(row)

      _other ->
        false
    end
  end

  defp valid_initial_control_predecessor?(row) do
    is_nil(row.legacy_catalog_publication_id) and row.generation_predecessor_kind == "none"
  end

  defp valid_legacy_control_predecessor?(row) do
    row.generation_predecessor_kind == "legacy" and
      is_binary(row.legacy_catalog_publication_id) and
      row.legacy_catalog_publication_id == row.generation_predecessor_catalog_publication_id
  end

  defp valid_generation_control_predecessor?(row) do
    row.generation_predecessor_kind == "generation" and
      (is_nil(row.legacy_catalog_publication_id) or
         is_binary(row.legacy_catalog_publication_id))
  end

  defp duplicate_binding_identity?(bindings) do
    identities = Enum.map(bindings, &binding_identity_key/1)
    length(identities) != length(Enum.uniq(identities))
  end

  defp duplicate_host_identity?(bindings) do
    identities = Enum.map(bindings, &host_identity_key/1)
    length(identities) != length(Enum.uniq(identities))
  end

  defp binding_identity_key(row),
    do:
      {row.binding_application_id, row.binding_application_version, row.binding_package_id,
       row.binding_package_version, row.binding_surface_id, row.binding_surface_version}

  defp host_identity_key(row),
    do:
      {row.binding_application_id, row.binding_application_version, row.binding_surface_id,
       row.binding_surface_version}

  defp binding_identity(row) do
    %{
      "application" => %{
        "id" => row.binding_application_id,
        "version" => row.binding_application_version
      },
      "package" => %{
        "id" => row.binding_package_id,
        "version" => row.binding_package_version
      },
      "surface" => %{
        "id" => row.binding_surface_id,
        "version" => row.binding_surface_version
      }
    }
  end

  defp previous_release_pair?(row, nil, nil),
    do: is_nil(row.binding_previous_publication_id) and is_nil(row.binding_previous_release_id)

  defp previous_release_pair?(row, expected, %{publication: publication}) when is_map(expected),
    do:
      row.binding_previous_publication_id == publication["publication_id"] and
        row.binding_previous_release_id == publication["release_id"] and
        row.binding_current_publication_id != row.binding_previous_publication_id and
        row.binding_current_release_id != row.binding_previous_release_id

  defp previous_release_pair?(_row, _expected, _previous), do: false

  defp release_id(nil), do: nil
  defp release_id(release), do: release["releaseId"]

  defp previous_publication_id(_row, nil), do: nil
  defp previous_publication_id(row, _release), do: row.binding_previous_publication_id

  defp identity_key(%{"application" => app, "package" => package, "surface" => surface}),
    do:
      {app["id"], app["version"], package["id"], package["version"], surface["id"],
       surface["version"]}

  defp exact_map_keys?(map, required_keys) when is_map(map) do
    Map.keys(map) |> Enum.sort() == Enum.sort(required_keys)
  end

  defp exact_map_keys?(_map, _required_keys), do: false

  defp timestamp_string_matches?(value, expected) when is_binary(value) and is_binary(expected) do
    case {parse_utc_timestamp(value), parse_utc_timestamp(expected)} do
      {{:ok, left}, {:ok, right}} ->
        DateTime.to_unix(left, :microsecond) == DateTime.to_unix(right, :microsecond)

      _ ->
        false
    end
  end

  defp timestamp_string_matches?(_value, _expected), do: false

  defp parse_utc_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, :missing_offset} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive_datetime} -> {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp format_db_timestamp(value) when is_binary(value) do
    case parse_utc_timestamp(value) do
      {:ok, datetime} ->
        normalized =
          datetime
          |> DateTime.to_unix(:microsecond)
          |> DateTime.from_unix!(:microsecond)

        microseconds =
          normalized.microsecond |> elem(0) |> Integer.to_string() |> String.pad_leading(6, "0")

        Calendar.strftime(normalized, "%Y-%m-%dT%H:%M:%S.") <> microseconds <> "Z"

      _ ->
        value
    end
  end

  defp format_db_timestamp(value), do: value

  defp integrity(reason), do: {:error, {:integrity_failure, reason}}

  defp static_entries do
    ReleaseRegistry.all()
    |> Enum.map(fn contribution ->
      {ReleaseContribution.key(contribution), ReleaseContribution.release(contribution)}
    end)
  end

  defp allowed_origins, do: Keyword.get(publication_config(), :allowed_origins, [])

  defp publication_config do
    case Process.get(@publication_config_key, :not_configured) do
      config when is_list(config) ->
        config

      _ ->
        case Application.get_env(:cadence_web, :frontend_release_publication, []) do
          config when is_list(config) -> config
          _ -> []
        end
    end
  end

  defp decode_row([
         control,
         control_count,
         has_any_catalog,
         has_any_generation,
         generation,
         catalog,
         binding,
         current_publication,
         current_artifacts,
         previous_publication,
         previous_artifacts
       ]) do
    %{
      control_id: field(control, "control_id"),
      control_epoch: field(control, "cutover_epoch"),
      cutover_at: field(control, "cutover_at"),
      legacy_catalog_publication_id: field(control, "legacy_catalog_publication_id"),
      control_count: control_count,
      has_any_catalog: has_any_catalog,
      has_any_generation: has_any_generation,
      generation_id: field(generation, "generation_id"),
      generation_catalog_publication_id: field(generation, "catalog_publication_id"),
      generation_sequence: field(generation, "sequence"),
      generation_identity_count: field(generation, "identity_count"),
      generation_predecessor_kind: field(generation, "predecessor_kind"),
      generation_predecessor_catalog_publication_id:
        field(generation, "predecessor_catalog_publication_id"),
      generation_inserted_at: field(generation, "inserted_at"),
      catalog_publication_id: field(catalog, "publication_id"),
      catalog_sequence: field(catalog, "sequence"),
      catalog_digest: field(catalog, "catalog_digest"),
      catalog_signed_document_digest: field(catalog, "signed_document_digest"),
      catalog_signing_key_id: field(catalog, "signing_key_id"),
      catalog_signing_role: field(catalog, "signing_role"),
      catalog_published_at: field(catalog, "published_at"),
      catalog_expires_at: field(catalog, "expires_at"),
      catalog_acceptance_state: field(catalog, "acceptance_state"),
      catalog_transition: field(catalog, "transition"),
      catalog_identity_count: field(catalog, "identity_count"),
      catalog_snapshot_digest: field(catalog, "snapshot_digest"),
      catalog_accepted_state: field(catalog, "accepted_state"),
      catalog_release_references: field(catalog, "release_references"),
      binding_generation_id: field(binding, "generation_id"),
      binding_application_id: field(binding, "application_id"),
      binding_application_version: field(binding, "application_version"),
      binding_package_id: field(binding, "package_id"),
      binding_package_version: field(binding, "package_version"),
      binding_surface_id: field(binding, "surface_id"),
      binding_surface_version: field(binding, "surface_version"),
      binding_current_publication_id: field(binding, "current_publication_id"),
      binding_current_release_id: field(binding, "current_release_id"),
      binding_previous_publication_id: field(binding, "previous_publication_id"),
      binding_previous_release_id: field(binding, "previous_release_id"),
      current_publication: current_publication,
      current_artifacts: current_artifacts || [],
      previous_publication: previous_publication,
      previous_artifacts: previous_artifacts || []
    }
  end

  defp decode_row(_row), do: %{}

  defp field(nil, _key), do: nil
  defp field(map, key), do: Map.get(map, key)

  defp catalog_query do
    """
    WITH latest_generation AS (
    SELECT generation_id, catalog_publication_id, sequence, identity_count,
           predecessor_kind, predecessor_catalog_publication_id, inserted_at
    FROM frontend_release_catalog_generations
    ORDER BY sequence DESC
    LIMIT 1
    ),
    database_state AS (
    SELECT EXISTS (SELECT 1 FROM frontend_release_catalog_publications) AS has_any_catalog,
           EXISTS (SELECT 1 FROM frontend_release_catalog_generations) AS has_any_generation,
           (SELECT COUNT(*) FROM frontend_release_activation_controls) AS control_count
    ),
    artifact_inventory AS (
    SELECT artifact.release_publication_id,
           jsonb_agg(
             jsonb_build_object(
               'path', artifact.path,
               'sha256', artifact.sha256,
               'size', artifact.size,
               'media_type', artifact.media_type,
               'object_key', artifact.object_key,
               'object_sha256', object.sha256,
               'object_size', object.size
             ) ORDER BY artifact.path
           ) AS artifacts
    FROM frontend_release_artifacts AS artifact
    LEFT JOIN frontend_release_objects AS object ON object.sha256 = artifact.sha256
    GROUP BY artifact.release_publication_id
    )
    SELECT
    to_jsonb(control) AS control,
    database_state.control_count,
    database_state.has_any_catalog,
    database_state.has_any_generation,
    to_jsonb(generation) AS generation,
    CASE WHEN catalog.publication_id IS NULL THEN NULL
         ELSE jsonb_build_object(
           'publication_id', catalog.publication_id,
           'sequence', catalog.sequence,
           'catalog_digest', catalog.catalog_digest,
           'signed_document_digest', catalog.signed_document_digest,
           'signing_key_id', catalog.signing_key_id,
           'signing_role', catalog.signing_role,
           'published_at', catalog.published_at,
           'expires_at', catalog.expires_at,
           'acceptance_state', catalog.acceptance_state,
           'transition', catalog.transition,
           'identity_count', catalog.identity_count,
           'snapshot_digest', catalog.snapshot_digest,
           'accepted_state', catalog.accepted_state,
           'release_references', catalog.release_references,
           'metadata', catalog.metadata,
           'accepted_at', catalog.accepted_at
         )
    END AS catalog,
    to_jsonb(binding) AS binding,
    CASE WHEN current_publication.publication_id IS NULL THEN NULL
         ELSE jsonb_build_object(
           'publication_id', current_publication.publication_id,
           'release_id', current_publication.release_id,
           'application_id', current_publication.application_id,
           'application_version', current_publication.application_version,
           'package_id', current_publication.package_id,
           'package_version', current_publication.package_version,
           'surface_id', current_publication.surface_id,
           'surface_version', current_publication.surface_version,
           'remote_name', current_publication.remote_name,
           'exposed_module', current_publication.exposed_module,
           'artifact_base_url', current_publication.artifact_base_url,
           'manifest_path', current_publication.manifest_path,
           'manifest_sha256', current_publication.manifest_sha256,
           'manifest_size', current_publication.manifest_size,
           'manifest_media_type', current_publication.manifest_media_type,
           'payload_digest', current_publication.payload_digest,
           'signed_document_digest', current_publication.signed_document_digest,
           'signing_key_id', current_publication.signing_key_id,
           'signing_role', current_publication.signing_role,
           'provenance', current_publication.provenance,
           'released_at', current_publication.released_at,
           'artifact_count', current_publication.artifact_count,
           'acceptance_state', current_publication.acceptance_state,
           'accepted_at', current_publication.accepted_at,
           'metadata', current_publication.metadata
         )
    END AS current_publication,
    COALESCE(current_inventory.artifacts, '[]'::jsonb) AS current_artifacts,
    CASE WHEN previous_publication.publication_id IS NULL THEN NULL
         ELSE jsonb_build_object(
           'publication_id', previous_publication.publication_id,
           'release_id', previous_publication.release_id,
           'application_id', previous_publication.application_id,
           'application_version', previous_publication.application_version,
           'package_id', previous_publication.package_id,
           'package_version', previous_publication.package_version,
           'surface_id', previous_publication.surface_id,
           'surface_version', previous_publication.surface_version,
           'remote_name', previous_publication.remote_name,
           'exposed_module', previous_publication.exposed_module,
           'artifact_base_url', previous_publication.artifact_base_url,
           'manifest_path', previous_publication.manifest_path,
           'manifest_sha256', previous_publication.manifest_sha256,
           'manifest_size', previous_publication.manifest_size,
           'manifest_media_type', previous_publication.manifest_media_type,
           'payload_digest', previous_publication.payload_digest,
           'signed_document_digest', previous_publication.signed_document_digest,
           'signing_key_id', previous_publication.signing_key_id,
           'signing_role', previous_publication.signing_role,
           'provenance', previous_publication.provenance,
           'released_at', previous_publication.released_at,
           'artifact_count', previous_publication.artifact_count,
           'acceptance_state', previous_publication.acceptance_state,
           'accepted_at', previous_publication.accepted_at,
           'metadata', previous_publication.metadata
         )
    END AS previous_publication,
    COALESCE(previous_inventory.artifacts, '[]'::jsonb) AS previous_artifacts
    FROM frontend_release_activation_controls AS control
    CROSS JOIN database_state
    LEFT JOIN latest_generation AS generation
    ON control.cutover_epoch > 0
    LEFT JOIN frontend_release_catalog_publications AS catalog
    ON catalog.publication_id = generation.catalog_publication_id
    LEFT JOIN frontend_release_catalog_bindings AS binding
    ON binding.generation_id = generation.generation_id
    LEFT JOIN frontend_release_publications AS current_publication
    ON current_publication.publication_id = binding.current_publication_id
    AND current_publication.release_id = binding.current_release_id
    LEFT JOIN artifact_inventory AS current_inventory
    ON current_inventory.release_publication_id = current_publication.publication_id
    LEFT JOIN frontend_release_publications AS previous_publication
    ON previous_publication.publication_id = binding.previous_publication_id
    AND previous_publication.release_id = binding.previous_release_id
    LEFT JOIN artifact_inventory AS previous_inventory
    ON previous_inventory.release_publication_id = previous_publication.publication_id
    WHERE control.control_id = 1
    ORDER BY generation.sequence DESC NULLS LAST,
           binding.application_id,
           binding.application_version,
           binding.package_id,
           binding.package_version,
           binding.surface_id,
           binding.surface_version
    """
  end
end
