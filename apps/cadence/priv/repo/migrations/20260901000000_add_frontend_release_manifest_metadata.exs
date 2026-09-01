defmodule Cadence.Repo.Migrations.AddFrontendReleaseManifestMetadata do
  use Ecto.Migration

  @release_table :frontend_release_publications
  @max_manifest_size 100_000_000

  def up do
    alter table(@release_table) do
      add(:manifest_path, :string, null: true)
      add(:manifest_sha256, :string, null: true)
      add(:manifest_size, :bigint, null: true)
      add(:manifest_media_type, :string, null: true)
    end

    execute(
      "ALTER TABLE frontend_release_publications DISABLE TRIGGER frontend_release_publications_append_only"
    )

    execute(&backfill_manifest_metadata/0)

    execute(
      "ALTER TABLE frontend_release_publications ENABLE TRIGGER frontend_release_publications_append_only"
    )

    alter table(@release_table) do
      modify(:manifest_path, :string, null: false)
      modify(:manifest_sha256, :string, null: false)
      modify(:manifest_size, :bigint, null: false)
      modify(:manifest_media_type, :string, null: false)
    end

    create(
      constraint(
        @release_table,
        :frontend_release_publications_manifest_path_check,
        check:
          "octet_length(manifest_path) > 0 AND octet_length(manifest_path) <= 256 AND position('\\\\' in manifest_path) = 0 AND manifest_path !~ '(^/|//|(^|/)\\.{1,2}(/|$))'"
      )
    )

    create(
      constraint(
        @release_table,
        :frontend_release_publications_manifest_sha256_check,
        check: "manifest_sha256 ~ '^[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(
        @release_table,
        :frontend_release_publications_manifest_size_check,
        check: "manifest_size >= 0 AND manifest_size <= #{@max_manifest_size}"
      )
    )

    create(
      constraint(
        @release_table,
        :frontend_release_publications_manifest_media_type_check,
        check:
          "octet_length(manifest_media_type) > 0 AND octet_length(manifest_media_type) <= 128 AND manifest_media_type ~ '^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}$'"
      )
    )
  end

  def down do
    refuse_if_phase_a_state_remains()

    drop(
      constraint(
        @release_table,
        :frontend_release_publications_manifest_media_type_check
      )
    )

    drop(constraint(@release_table, :frontend_release_publications_manifest_size_check))
    drop(constraint(@release_table, :frontend_release_publications_manifest_sha256_check))
    drop(constraint(@release_table, :frontend_release_publications_manifest_path_check))

    alter table(@release_table) do
      remove(:manifest_media_type)
      remove(:manifest_size)
      remove(:manifest_sha256)
      remove(:manifest_path)
    end
  end

  defp backfill_manifest_metadata do
    migration_repo = repo()

    migration_repo.query!("""
    SELECT publication_id, release_id, payload_bytes, payload_digest
    FROM frontend_release_publications
    ORDER BY publication_id
    """).rows
    |> Enum.each(fn row -> backfill_row!(migration_repo, row) end)
  end

  defp backfill_row!(migration_repo, [publication_id, release_id, payload_bytes, payload_digest]) do
    release = decode_canonical_release!(payload_bytes, payload_digest, publication_id)
    manifest = Map.get(release, "manifest")

    unless is_map(manifest) and
             exact_keys?(manifest, ["path", "sha256", "size", "mediaType"]) and
             is_binary(manifest["path"]) and is_binary(manifest["sha256"]) and
             is_integer(manifest["size"]) and is_binary(manifest["mediaType"]) and
             valid_manifest_path?(manifest["path"]) and
             Regex.match?(~r/^[0-9a-f]{64}$/, manifest["sha256"]) and
             manifest["size"] >= 0 and manifest["size"] <= @max_manifest_size and
             valid_media_type?(manifest["mediaType"]) do
      migration_failure!(publication_id, :malformed_manifest)
    end

    rows =
      migration_repo.query!(
        """
        SELECT artifact.path, artifact.sha256, artifact.size, artifact.media_type,
               artifact.object_key, object.sha256, object.size
        FROM frontend_release_artifacts AS artifact
        JOIN frontend_release_objects AS object ON object.sha256 = artifact.sha256
        WHERE artifact.release_publication_id = $1
          AND artifact.release_id = $2
          AND artifact.path = $3
          AND artifact.sha256 = $4
          AND artifact.size = $5
          AND artifact.media_type = $6
          AND artifact.object_key = 'sha256:' || artifact.sha256
          AND object.sha256 = artifact.sha256
          AND object.size = artifact.size
        """,
        [
          publication_id,
          release_id,
          manifest["path"],
          manifest["sha256"],
          manifest["size"],
          manifest["mediaType"]
        ]
      ).rows

    case rows do
      [[path, sha256, size, media_type, object_key, object_sha256, object_size]] ->
        if path == manifest["path"] and sha256 == manifest["sha256"] and
             size == manifest["size"] and media_type == manifest["mediaType"] and
             object_key == "sha256:" <> manifest["sha256"] and
             object_sha256 == manifest["sha256"] and object_size == manifest["size"] do
          migration_repo.query!(
            """
            UPDATE frontend_release_publications
            SET manifest_path = $2,
                manifest_sha256 = $3,
                manifest_size = $4,
                manifest_media_type = $5
            WHERE publication_id = $1
            """,
            [publication_id, path, sha256, size, media_type]
          )
        else
          migration_failure!(publication_id, :manifest_artifact_object_mismatch)
        end

      _ ->
        migration_failure!(publication_id, :manifest_artifact_object_mismatch)
    end
  end

  defp decode_canonical_release!(payload_bytes, payload_digest, publication_id)
       when is_binary(payload_bytes) and is_binary(payload_digest) do
    with {:ok, release} <- Jason.decode(payload_bytes),
         true <- is_map(release),
         true <- canonical_payload?(release, payload_bytes),
         true <- digest(payload_bytes) == payload_digest,
         true <- Map.get(release, "schema") == "cadence.first-party-frontend-release.v1" do
      release
    else
      _ -> migration_failure!(publication_id, :noncanonical_release_payload)
    end
  end

  defp decode_canonical_release!(_payload_bytes, _payload_digest, publication_id),
    do: migration_failure!(publication_id, :invalid_release_payload)

  defp refuse_if_phase_a_state_remains do
    migration_repo = repo()

    case migration_repo.query!("SELECT to_regclass('frontend_release_activation_controls')").rows do
      [[nil]] -> :ok
      _ -> migration_failure!(:phase_a, :activation_state_must_be_reversed_first)
    end
  end

  defp valid_manifest_path?(value) do
    byte_size(value) > 0 and byte_size(value) <= 256 and String.valid?(value) and
      not String.starts_with?(value, "/") and not String.contains?(value, "\\") and
      Enum.all?(String.split(value, "/"), &(&1 not in ["", ".", ".."]))
  end

  defp valid_media_type?(value) do
    byte_size(value) > 0 and byte_size(value) <= 128 and String.valid?(value) and
      Regex.match?(
        ~r/^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}\/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}$/,
        value
      )
  end

  defp exact_keys?(map, keys), do: Map.keys(map) |> Enum.sort() == Enum.sort(keys)

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

  defp digest(bytes), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp canonical_payload?(value, bytes) do
    canonical_json(value) == bytes
  rescue
    FunctionClauseError -> false
  end

  defp migration_failure!(identity, reason) do
    raise Ecto.MigrationError,
          "cannot backfill frontend release manifest metadata for #{inspect(identity)}: #{reason}"
  end
end
