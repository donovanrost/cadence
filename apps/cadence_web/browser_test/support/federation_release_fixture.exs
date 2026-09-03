defmodule CadenceWeb.Assets.FederationReleaseFixture do
  @moduledoc false

  import ExUnit.Assertions

  alias CadenceWeb.ApplicationReleaseRegistry
  alias CadenceWeb.FrontendReleaseActivation
  alias CadenceWeb.FrontendReleaseCatalog
  alias CadenceWeb.FrontendReleasePublication

  @artifact_origin "https://cdn.example.com"
  @release_seed "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  @promotion_seed "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
  @source_revision "bb9990ef6ec667999842f4605404c4489f184f88"
  @built_at "2026-09-01T16:00:00Z"
  @released_at "2026-09-01T18:00:00Z"
  @published_at "2026-09-01T19:00:00Z"
  @expires_at "2026-09-30T00:00:00Z"
  @activation_now "2026-09-02T00:00:00Z"
  @activation_idempotency_key "federation-browser-active-generation-r1"
  @publisher_identity "federation-browser-active-generation-r1"

  @repo_root Path.expand("../../../../", __DIR__)
  @package_tool Path.join(@repo_root, "frontend/tools/frontend-release-package.mjs")
  @fixture Path.join(@repo_root, "test/fixtures/frontend_release_catalog_v1.json")

  @spec publication_config() :: keyword()
  def publication_config do
    corpus = @fixture |> File.read!() |> Jason.decode!()
    [trust_records: corpus["keys"], allowed_origins: [@artifact_origin]]
  end

  @spec prepare_and_activate!(binary()) :: map()
  def prepare_and_activate!(app_root) when is_binary(app_root) do
    temp_root = temporary_root!()

    try do
      node = configured_node!()

      packages = [
        package!(
          node,
          "comms-overview",
          "@cadence/comms-overview-plugin",
          Path.join(app_root, "priv/static/assets/application-host/comms-overview"),
          comms_metadata(),
          temp_root
        ),
        package!(
          node,
          "telemetry-decom",
          "@cadence/telemetry-decom-plugin",
          Path.join(app_root, "priv/static/assets/application-host/telemetry-decom"),
          telemetry_metadata(),
          temp_root
        )
      ]

      admitted = Enum.map(packages, &admit_release!/1)
      catalog_document = catalog_document!(admitted)

      assert {:ok, response} =
               FrontendReleaseActivation.activate_catalog(
                 catalog_document,
                 @activation_idempotency_key,
                 publication_config: publication_config(),
                 publisher_identity: @publisher_identity,
                 now: @activation_now
               )

      assert response.status == 201
      assert response.outcome == "initial"
      assert response.replay? == false

      assert %{
               "data" => %{
                 "identityCount" => 2,
                 "outcome" => "initial",
                 "sequence" => 1,
                 "status" => "activated"
               }
             } = Jason.decode!(response.body)

      assert {:ok, %{source: :database, entries: entries}} = ApplicationReleaseRegistry.snapshot()
      assert length(entries) == 2
      assert_registry_paths!(entries, admitted)

      %{
        temp_root: temp_root,
        packages: packages,
        admitted: admitted,
        catalog_document: catalog_document,
        activation_response: response,
        registry_source: :database,
        release_ids: Enum.map(admitted, & &1.package.release["releaseId"])
      }
    rescue
      exception ->
        cleanup!(%{temp_root: temp_root})
        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        cleanup!(%{temp_root: temp_root})
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @spec cleanup!(map()) :: :ok
  def cleanup!(%{temp_root: temp_root}) when is_binary(temp_root) do
    case File.rm_rf(temp_root) do
      {:ok, _removed} ->
        :ok

      {:error, reason, _path} ->
        raise "could not clean federation release fixture: #{inspect(reason)}"
    end
  end

  defp configured_node! do
    node = System.find_executable("node") || raise "node executable is required"

    assert {version, 0} = System.cmd(node, ["--version"], stderr_to_stdout: true)
    assert String.trim(version) == "v24.16.0"
    node
  end

  defp package!(node, label, package_name, publication_directory, metadata, temp_root) do
    assert File.dir?(publication_directory),
           "real federation publication output is missing: #{publication_directory}"

    release_output_directory = Path.join(temp_root, "release-output-#{label}")
    build_release!(package_name, release_output_directory)

    package_input_directory = release_output_directory
    output_directory = Path.join(temp_root, "package-#{label}")

    assert File.regular?(Path.join(package_input_directory, "mf-manifest.json"))
    assert File.regular?(Path.join(package_input_directory, "remoteEntry.js"))

    metadata_path = Path.join(temp_root, "metadata-#{label}.json")
    File.write!(metadata_path, Jason.encode!(metadata))

    args = [
      @package_tool,
      "--input-dir",
      package_input_directory,
      "--metadata",
      metadata_path,
      "--artifact-origin",
      @artifact_origin,
      "--key-id",
      "fixture-release-key",
      "--output-dir",
      output_directory
    ]

    assert {_output, 0} =
             System.cmd(node, args,
               cd: @repo_root,
               env: [
                 {"CADENCE_RELEASE_PRIVATE_KEY", "hex:" <> @release_seed},
                 {"PATH", System.get_env("PATH", "")}
               ],
               stderr_to_stdout: true
             )

    read_package!(output_directory)
  end

  defp build_release!(package_name, output_directory) do
    corepack = System.find_executable("corepack") || raise "corepack executable is required"

    env = [
      {"CADENCE_RELEASE_OUTPUT_DIR", output_directory},
      {"PATH", System.get_env("PATH", "")}
    ]

    assert {_output, 0} =
             System.cmd(corepack, ["pnpm", "--filter", package_name, "build:release"],
               cd: Path.join(@repo_root, "frontend"),
               env: env,
               stderr_to_stdout: true
             )

    assert {_output, 0} =
             System.cmd(corepack, ["pnpm", "--filter", package_name, "check:release"],
               cd: Path.join(@repo_root, "frontend"),
               env: env,
               stderr_to_stdout: true
             )
  end

  defp read_package!(output_directory) do
    files = read_tree!(output_directory)
    document_bytes = Map.fetch!(files, "release.json")
    envelope = Jason.decode!(document_bytes)
    payload_bytes = Base.url_decode64!(envelope["payload"], padding: false)
    release = Jason.decode!(payload_bytes)

    assert document_bytes == FrontendReleaseCatalog.canonical_json(envelope)
    assert payload_bytes == FrontendReleaseCatalog.canonical_json(release)

    artifacts =
      release["artifacts"]
      |> Enum.map(fn declaration ->
        path = declaration["path"]
        bytes = Map.fetch!(files, "artifacts/" <> path)

        assert byte_size(bytes) == declaration["size"]
        assert FrontendReleaseCatalog.digest(bytes) == "sha256:" <> declaration["sha256"]

        %{path: path, sha256: "sha256:" <> declaration["sha256"], size: declaration["size"]}
      end)

    assert Enum.map(artifacts, & &1.path) == Enum.sort(Enum.map(artifacts, & &1.path))
    assert Enum.any?(artifacts, &(&1.path == "mf-manifest.json"))
    assert Enum.any?(artifacts, &(&1.path == "remoteEntry.js"))

    %{
      output_directory: output_directory,
      document_bytes: document_bytes,
      envelope: envelope,
      release: release,
      artifacts: artifacts
    }
  end

  defp admit_release!(package) do
    staged =
      Enum.map(package.artifacts, fn artifact ->
        file_path = artifact_file(package.output_directory, artifact.path)

        assert {:ok, %{digest: digest, size: size}} =
                 FrontendReleasePublication.stage_artifact(artifact.sha256, file_path)

        assert digest == artifact.sha256
        assert size == artifact.size
        %{"path" => artifact.path, "sha256" => digest, "size" => size}
      end)

    assert {:ok, publication, :created} =
             FrontendReleasePublication.admit_release(
               package.document_bytes,
               staged,
               publication_config: publication_config(),
               publisher_identity: @publisher_identity,
               now: @activation_now,
               return_outcome: true
             )

    assert publication.acceptance_state == "accepted"
    assert publication.release_id == package.release["releaseId"]
    assert publication.artifact_count == length(package.artifacts)
    %{package: package, publication: publication}
  end

  defp catalog_document!(admitted) do
    entries =
      admitted
      |> Enum.sort_by(&identity_sort_key(&1.package.release))
      |> Enum.map(fn %{package: package} ->
        %{
          "identity" => identity(package.release),
          "current" => package.envelope
        }
      end)

    snapshot = %{
      "schema" => "cadence.first-party-frontend-release-persisted-snapshot.v1",
      "sequence" => 1,
      "publishedAt" => normalize_timestamp(@published_at),
      "expiresAt" => normalize_timestamp(@expires_at),
      "transition" => "initial",
      "identityCount" => length(entries),
      "entries" =>
        admitted
        |> Enum.sort_by(&identity_sort_key(&1.package.release))
        |> Enum.map(fn %{package: package, publication: publication} ->
          %{
            "identity" => identity(package.release),
            "current" => snapshot_release(publication),
            "previous" => nil
          }
        end)
    }

    payload = %{
      "entries" => entries,
      "expiresAt" => @expires_at,
      "identityCount" => length(entries),
      "publishedAt" => @published_at,
      "schema" => FrontendReleaseCatalog.catalog_v2_schema(),
      "sequence" => 1,
      "snapshotDigest" =>
        FrontendReleaseCatalog.digest(FrontendReleaseCatalog.canonical_json(snapshot)),
      "transition" => "initial"
    }

    payload_bytes = FrontendReleaseCatalog.canonical_json(payload)
    sign_document(payload_bytes, "fixture-promotion-key", "promotion", @promotion_seed)
  end

  defp assert_registry_paths!(entries, admitted) do
    expected =
      admitted
      |> Enum.map(fn %{package: package} ->
        release = package.release
        {release["application"]["id"], release["releaseId"]}
      end)
      |> MapSet.new()

    actual =
      entries
      |> Enum.map(fn {{application_id, _application_version, _surface_id, _surface_version},
                      release} ->
        assert release.federation == :module_federation

        assert release.manifest_path ==
                 "/releases/#{application_id}/#{release.release_id}/artifacts/mf-manifest.json"

        {application_id, release.release_id}
      end)
      |> MapSet.new()

    assert actual == expected
  end

  defp identity(release), do: Map.take(release, ["application", "package", "surface"])

  defp identity_sort_key(release) do
    application = release["application"]
    package = release["package"]
    surface = release["surface"]

    {application["id"], application["version"], package["id"], package["version"], surface["id"],
     surface["version"]}
  end

  defp snapshot_release(publication) do
    %{
      "releaseId" => publication.release_id,
      "payloadDigest" => publication.payload_digest,
      "signedDocumentDigest" => publication.signed_document_digest,
      "identity" => %{
        "application" => %{
          "id" => publication.application_id,
          "version" => publication.application_version
        },
        "package" => %{"id" => publication.package_id, "version" => publication.package_version},
        "surface" => %{"id" => publication.surface_id, "version" => publication.surface_version}
      },
      "remoteName" => publication.remote_name,
      "exposedModule" => publication.exposed_module,
      "artifactBaseUrl" => publication.artifact_base_url,
      "manifest" => %{
        "path" => publication.manifest_path,
        "sha256" => publication.manifest_sha256,
        "size" => publication.manifest_size,
        "mediaType" => publication.manifest_media_type
      },
      "signingKeyId" => publication.signing_key_id,
      "signingRole" => publication.signing_role,
      "releasedAt" => normalize_datetime(publication.released_at),
      "artifactCount" => publication.artifact_count,
      "provenance" => publication.provenance
    }
  end

  defp sign_document(payload, key_id, role, seed_hex) do
    private_key = Base.decode16!(seed_hex, case: :lower)
    signature = :crypto.sign(:eddsa, :none, payload, [private_key, :ed25519])

    FrontendReleaseCatalog.canonical_json(%{
      "schema" => FrontendReleaseCatalog.envelope_schema(),
      "keyId" => key_id,
      "algorithm" => "ed25519",
      "signingRole" => role,
      "payloadEncoding" => "base64url-json",
      "payload" => Base.url_encode64(payload, padding: false),
      "signature" => Base.url_encode64(signature, padding: false)
    })
  end

  defp normalize_datetime(%DateTime{} = value) do
    value = DateTime.from_unix!(DateTime.to_unix(value, :microsecond), :microsecond)
    Calendar.strftime(value, "%Y-%m-%dT%H:%M:%S.%fZ")
  end

  defp normalize_timestamp(value) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    normalize_datetime(datetime)
  end

  defp comms_metadata do
    metadata(
      "comms_overview",
      "cadence.comms_overview",
      "overview",
      "cadence.comms.overview",
      [],
      "cadence_comms_overview",
      "federation-browser-comms-overview"
    )
  end

  defp telemetry_metadata do
    metadata(
      "telemetry_decom",
      "cadence.telemetry-applications",
      "packet_bindings",
      "cadence.packet_bindings.manage",
      ["save_packet_bindings"],
      "cadence_telemetry_decom",
      "federation-browser-telemetry-decom"
    )
  end

  defp metadata(application_id, package_id, surface_id, query_id, actions, remote_name, build_id) do
    %{
      "application" => %{"id" => application_id, "version" => 1},
      "package" => %{"id" => package_id, "version" => 1},
      "surface" => %{"id" => surface_id, "version" => 1},
      "query" => %{"id" => query_id, "version" => 1},
      "actions" => actions,
      "remote" => %{"name" => remote_name},
      "module" => %{"exposedModule" => "./Application"},
      "hostCompatibility" => %{
        "hostContract" => "cadence.application-host.v1",
        "compatibility" => %{
          "cadenceApplicationContract" => 1,
          "cadenceSurfaceContract" => 1,
          "cadenceFederatedRendererContract" => 1,
          "cadenceThemeContract" => 1
        },
        "vueRange" => "^3.5.40"
      },
      "provenance" => %{
        "sourceRepository" => "https://github.com/cadence/cadence",
        "sourceRevision" => @source_revision,
        "buildId" => build_id,
        "builder" => "github-actions",
        "workflow" => "frontend-release",
        "builtAt" => @built_at
      },
      "releasedAt" => @released_at
    }
  end

  defp artifact_file(output_directory, path),
    do: Path.join([output_directory, "artifacts" | String.split(path, "/")])

  defp temporary_root! do
    root =
      Path.join(
        System.tmp_dir!(),
        ".cadence-federation-browser-active-generation-r1-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)
    root
  end

  defp read_tree!(root) do
    assert File.dir?(root)
    read_tree!(root, root, %{})
  end

  defp read_tree!(root, directory, files) do
    directory
    |> File.ls!()
    |> Enum.sort()
    |> Enum.reduce(files, fn name, acc ->
      path = Path.join(directory, name)
      relative_path = Path.relative_to(path, root)

      case File.lstat!(path) do
        %{type: :symlink} -> flunk("release package contains a symlink: #{relative_path}")
        %{type: :directory} -> read_tree!(root, path, acc)
        %{type: :regular} -> Map.put(acc, relative_path, File.read!(path))
        _other -> flunk("release package contains a non-file: #{relative_path}")
      end
    end)
  end
end
