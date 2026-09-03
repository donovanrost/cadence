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
  @n_minus_1_released_at "2026-09-01T17:00:00Z"
  @n_released_at "2026-09-01T18:00:00Z"
  @published_at "2026-09-01T19:00:00Z"
  @promotion_published_at "2026-09-02T00:01:00Z"
  @rollback_published_at "2026-09-02T00:02:00Z"
  @stale_published_at "2026-09-01T18:00:00Z"
  @stale_expires_at "2026-09-01T18:59:59Z"
  @expires_at "2026-09-30T00:00:00Z"
  @activation_now "2026-09-02T00:03:00Z"
  @activation_idempotency_key "federation-browser-active-generation-r1"
  @stale_activation_idempotency_key "federation-browser-stale-generation-r1"
  @promotion_idempotency_key "federation-browser-promotion-generation-r1"
  @rollback_idempotency_key "federation-browser-rollback-generation-r1"
  @publisher_identity "federation-browser-active-generation-r1"

  @repo_root Path.expand("../../../../", __DIR__)
  @package_tool Path.join(@repo_root, "frontend/tools/frontend-release-package.mjs")
  @fixture Path.join(@repo_root, "test/fixtures/frontend_release_catalog_v1.json")

  @spec publication_config() :: keyword()
  def publication_config do
    corpus = @fixture |> File.read!() |> Jason.decode!()
    [trust_records: corpus["keys"], allowed_origins: [@artifact_origin]]
  end

  @spec prepare_and_activate!(binary(), keyword()) :: map()
  def prepare_and_activate!(app_root, opts \\ []) when is_binary(app_root) do
    sandbox_owner = Keyword.fetch!(opts, :sandbox_owner)
    temp_root = temporary_root!()

    try do
      node = configured_node!()

      comms_build =
        build_release!(
          node,
          "@cadence/comms-overview-plugin",
          Path.join(app_root, "priv/static/assets/application-host/comms-overview"),
          Path.join(temp_root, "release-build-comms-overview")
        )

      telemetry_build =
        build_release!(
          node,
          "@cadence/telemetry-decom-plugin",
          Path.join(app_root, "priv/static/assets/application-host/telemetry-decom"),
          Path.join(temp_root, "release-build-telemetry-decom")
        )

      packages = %{
        n_minus_1: [
          package!(
            node,
            "comms-overview-n-minus-1",
            comms_build,
            comms_metadata(:n_minus_1),
            temp_root
          ),
          package!(
            node,
            "telemetry-decom-n-minus-1",
            telemetry_build,
            telemetry_metadata(:n_minus_1),
            temp_root
          )
        ],
        n: [
          package!(node, "comms-overview-n", comms_build, comms_metadata(:n), temp_root),
          package!(node, "telemetry-decom-n", telemetry_build, telemetry_metadata(:n), temp_root)
        ]
      }

      admitted =
        Map.new(packages, fn {slot, slot_packages} ->
          {slot, Enum.map(slot_packages, &admit_release!/1)}
        end)

      catalog_document = catalog_document!("initial", 1, @published_at, admitted.n_minus_1, nil)

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

      assert {:ok, %{source: :database, entries: entries}} =
               ApplicationReleaseRegistry.snapshot(now: @activation_now)

      assert length(entries) == 2
      assert_registry_paths!(entries, admitted.n_minus_1)

      accepted_snapshot = ApplicationReleaseRegistry.snapshot(now: @activation_now)

      stale_catalog =
        catalog_document!("initial", 1, @stale_published_at, admitted.n_minus_1, nil,
          expires_at: @stale_expires_at
        )

      assert {:ok, stale_response} =
               FrontendReleaseActivation.activate_catalog(
                 stale_catalog,
                 @stale_activation_idempotency_key,
                 publication_config: publication_config(),
                 publisher_identity: @publisher_identity,
                 now: @activation_now
               )

      assert stale_response.status == 422
      assert stale_response.outcome == "rejected"
      assert stale_response.code == :expired_catalog
      assert ApplicationReleaseRegistry.snapshot(now: @activation_now) == accepted_snapshot

      lifecycle = start_lifecycle!(sandbox_owner, admitted)

      %{
        temp_root: temp_root,
        packages: packages,
        admitted: admitted,
        catalog_documents: %{initial: catalog_document},
        activation_response: response,
        registry_source: :database,
        release_ids: %{
          n_minus_1: release_ids(admitted.n_minus_1),
          n: release_ids(admitted.n)
        },
        lifecycle: lifecycle
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
  def cleanup!(%{temp_root: temp_root} = fixture) when is_binary(temp_root) do
    stop_lifecycle!(Map.get(fixture, :lifecycle))

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

  defp package!(node, label, package_input_directory, metadata, temp_root) do
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
                 {"PATH", Path.dirname(node) <> ":" <> System.get_env("PATH", "")}
               ],
               stderr_to_stdout: true
             )

    read_package!(output_directory)
  end

  defp build_release!(node, package_name, publication_directory, output_directory) do
    assert File.dir?(publication_directory),
           "real federation publication output is missing: #{publication_directory}"

    corepack = System.find_executable("corepack") || raise "corepack executable is required"

    env = [{"CADENCE_RELEASE_OUTPUT_DIR", output_directory}]

    assert {_output, 0} =
             System.cmd(corepack, ["pnpm", "--filter", package_name, "build:release"],
               cd: Path.join(@repo_root, "frontend"),
               env: [{"PATH", Path.dirname(node) <> ":" <> System.get_env("PATH", "")} | env],
               stderr_to_stdout: true
             )

    assert {_output, 0} =
             System.cmd(corepack, ["pnpm", "--filter", package_name, "check:release"],
               cd: Path.join(@repo_root, "frontend"),
               env: [{"PATH", Path.dirname(node) <> ":" <> System.get_env("PATH", "")} | env],
               stderr_to_stdout: true
             )

    output_directory
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

  defp catalog_document!(transition, sequence, published_at, current, fallback, opts \\ []) do
    expires_at = Keyword.get(opts, :expires_at, @expires_at)

    entries =
      current
      |> Enum.sort_by(&identity_sort_key(&1.package.release))
      |> Enum.map(fn %{package: package} = admitted_release ->
        entry = %{"identity" => identity(package.release), "current" => package.envelope}

        case previous_for(admitted_release, fallback) do
          nil -> entry
          previous -> Map.put(entry, "fallback", previous.package.envelope)
        end
      end)

    snapshot = %{
      "schema" => "cadence.first-party-frontend-release-persisted-snapshot.v1",
      "sequence" => sequence,
      "publishedAt" => normalize_timestamp(published_at),
      "expiresAt" => normalize_timestamp(expires_at),
      "transition" => transition,
      "identityCount" => length(entries),
      "entries" =>
        current
        |> Enum.sort_by(&identity_sort_key(&1.package.release))
        |> Enum.map(fn %{package: package, publication: publication} = admitted_release ->
          %{
            "identity" => identity(package.release),
            "current" => snapshot_release(publication),
            "previous" => previous_snapshot(admitted_release, fallback)
          }
        end)
    }

    payload = %{
      "entries" => entries,
      "expiresAt" => expires_at,
      "identityCount" => length(entries),
      "publishedAt" => published_at,
      "schema" => FrontendReleaseCatalog.catalog_v2_schema(),
      "sequence" => sequence,
      "snapshotDigest" =>
        FrontendReleaseCatalog.digest(FrontendReleaseCatalog.canonical_json(snapshot)),
      "transition" => transition
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

  defp comms_metadata(slot) do
    metadata(
      "comms_overview",
      "cadence.comms_overview",
      "overview",
      "cadence.comms.overview",
      [],
      "cadence_comms_overview",
      "federation-browser-comms-overview-#{slot_name(slot)}",
      released_at(slot)
    )
  end

  defp telemetry_metadata(slot) do
    metadata(
      "telemetry_decom",
      "cadence.telemetry-applications",
      "packet_bindings",
      "cadence.packet_bindings.manage",
      ["save_packet_bindings"],
      "cadence_telemetry_decom",
      "federation-browser-telemetry-decom-#{slot_name(slot)}",
      released_at(slot)
    )
  end

  defp metadata(
         application_id,
         package_id,
         surface_id,
         query_id,
         actions,
         remote_name,
         build_id,
         released_at
       ) do
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
      "releasedAt" => released_at
    }
  end

  defp released_at(:n_minus_1), do: @n_minus_1_released_at
  defp released_at(:n), do: @n_released_at

  defp slot_name(:n_minus_1), do: "n-minus-1"
  defp slot_name(:n), do: "n"

  defp previous_for(%{package: package}, fallback) when is_list(fallback) do
    Enum.find(fallback, fn %{package: previous} ->
      identity(previous.release) == identity(package.release)
    end)
  end

  defp previous_for(_current, _fallback), do: nil

  defp previous_snapshot(current, fallback) do
    case previous_for(current, fallback) do
      nil -> nil
      %{publication: publication} -> snapshot_release(publication)
    end
  end

  defp release_ids(admitted) do
    admitted
    |> Map.new(fn %{package: package} ->
      {package.release["application"]["id"], package.release["releaseId"]}
    end)
  end

  defp start_lifecycle!(sandbox_owner, admitted) do
    {:ok, socket} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_address, port}} = :inet.sockname(socket)
    pid = spawn(fn -> lifecycle_loop(socket, admitted) end)
    :ok = Ecto.Adapters.SQL.Sandbox.allow(Cadence.Repo, sandbox_owner, pid)

    %{pid: pid, socket: socket, url: "http://127.0.0.1:#{port}"}
  end

  defp stop_lifecycle!(nil), do: :ok

  defp stop_lifecycle!(%{pid: pid, socket: socket}) do
    _ = :gen_tcp.close(socket)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      1_000 ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        after
          1_000 -> raise "federation lifecycle coordinator did not stop"
        end
    end
  end

  defp lifecycle_loop(socket, admitted) do
    case :gen_tcp.accept(socket) do
      {:ok, connection} ->
        lifecycle_connection(connection, admitted)
        lifecycle_loop(socket, admitted)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        lifecycle_loop(socket, admitted)
    end
  end

  defp lifecycle_connection(connection, admitted) do
    try do
      request = receive_request!(connection)
      response = lifecycle_response!(request, admitted)
      send_json_response(connection, 200, response)
    rescue
      exception ->
        send_json_response(connection, 500, %{"error" => Exception.message(exception)})
    after
      :gen_tcp.close(connection)
    end
  end

  defp receive_request!(connection, buffer \\ <<>>) do
    if :binary.match(buffer, "\r\n\r\n") != :nomatch do
      buffer
    else
      case :gen_tcp.recv(connection, 0, 10_000) do
        {:ok, chunk} when byte_size(buffer) + byte_size(chunk) <= 64 * 1024 ->
          receive_request!(connection, buffer <> chunk)

        {:ok, _chunk} ->
          raise "federation lifecycle request is too large"

        {:error, reason} ->
          raise "federation lifecycle request failed: #{inspect(reason)}"
      end
    end
  end

  defp lifecycle_response!(request, admitted) do
    request_line = request |> String.split("\r\n", parts: 2) |> hd()

    case String.split(request_line, " ") do
      ["POST", "/promote", "HTTP/1.1"] ->
        activate_transition!(
          "promotion",
          2,
          @promotion_published_at,
          admitted.n,
          admitted.n_minus_1,
          @promotion_idempotency_key
        )

        %{
          "status" => "promoted",
          "transition" => "promotion",
          "sequence" => 2,
          "releaseIds" => release_ids(admitted.n)
        }

      ["POST", "/rollback", "HTTP/1.1"] ->
        activate_transition!(
          "rollback",
          3,
          @rollback_published_at,
          admitted.n_minus_1,
          admitted.n,
          @rollback_idempotency_key
        )

        %{
          "status" => "rolled_back",
          "transition" => "rollback",
          "sequence" => 3,
          "releaseIds" => release_ids(admitted.n_minus_1)
        }

      _ ->
        raise "unknown federation lifecycle operation"
    end
  end

  defp activate_transition!(
         transition,
         sequence,
         published_at,
         current,
         fallback,
         idempotency_key
       ) do
    document = catalog_document!(transition, sequence, published_at, current, fallback)

    assert {:ok, response} =
             FrontendReleaseActivation.activate_catalog(
               document,
               idempotency_key,
               publication_config: publication_config(),
               publisher_identity: @publisher_identity,
               now: @activation_now
             )

    assert response.status == 201, response.body
    assert response.outcome == transition

    assert {:ok, %{source: :database, entries: entries}} =
             ApplicationReleaseRegistry.snapshot(now: @activation_now)

    assert length(entries) == 2
    :ok
  end

  defp send_json_response(connection, status, body) do
    encoded = Jason.encode!(body)
    reason = if status == 200, do: "OK", else: "Internal Server Error"

    :gen_tcp.send(
      connection,
      [
        "HTTP/1.1 ",
        Integer.to_string(status),
        " ",
        reason,
        "\r\ncontent-type: application/json\r\ncache-control: no-store\r\ncontent-length: ",
        Integer.to_string(byte_size(encoded)),
        "\r\nconnection: close\r\n\r\n",
        encoded
      ]
    )
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
