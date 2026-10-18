defmodule CadenceWeb.FrontendReleaseSignedActivationFixtures do
  @moduledoc false

  @node_env "CADENCE_FRONTEND_RELEASE_NODE"
  @corepack_env "CADENCE_FRONTEND_RELEASE_COREPACK"
  @node_version "v24.16.0"
  @pnpm_version "11.22.0"
  @package_manager "pnpm@11.22.0"
  @release_seed "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
  @origin "https://cdn.example.com"
  @application "@cadence/telemetry-decom-plugin"
  @source_revision_n_minus_1 "0123456789abcdef0123456789abcdef01234567"
  @source_revision_n "89abcdef0123456789abcdef0123456789abcdef"
  @built_at "2026-09-01T16:00:00Z"
  @released_at_n_minus_1 "2026-09-01T17:00:00Z"
  @released_at_n "2026-09-01T18:00:00Z"

  @repo_root Path.expand("../../../../", __DIR__)
  @frontend_root Path.join(@repo_root, "frontend")
  @package_tool Path.join(@frontend_root, "tools/frontend-release-package.mjs")

  @tracked_inputs [
    "frontend/apps/telemetry-decom",
    "frontend/packages",
    "frontend/vite.config.ts",
    "frontend/tools/frontend-release-package.mjs",
    "frontend/tools/frontend-release-output-check.mjs",
    "frontend/package.json",
    "frontend/pnpm-lock.yaml",
    "frontend/pnpm-workspace.yaml"
  ]

  @metadata_fields [
    :application,
    :package,
    :surface,
    :query,
    :actions,
    :remote,
    :module,
    :host_compatibility,
    :provenance,
    :released_at
  ]

  @spec prepare!() :: map()
  def prepare! do
    temp_root = temporary_root!()

    try do
      status_before = git_status!()
      source_before = tracked_input_state!()
      toolchain = toolchain!()
      build_output = Path.join(temp_root, "telemetry-release-build")

      run_pnpm!(
        toolchain,
        [
          "--filter",
          @application,
          "run",
          "build:release"
        ],
        [{"CADENCE_RELEASE_OUTPUT_DIR", build_output}]
      )

      run_pnpm!(toolchain, ["--filter", @application, "run", "check:release"], [
        {"CADENCE_RELEASE_OUTPUT_DIR", build_output}
      ])

      built_files = read_tree!(build_output)
      metadata_n_minus_1 = metadata(:n_minus_1)
      metadata_n = metadata(:n)
      metadata_path_n_minus_1 = write_metadata!(temp_root, "n-minus-1", metadata_n_minus_1)
      metadata_path_n = write_metadata!(temp_root, "n", metadata_n)
      metadata_before = metadata_state!(metadata_path_n_minus_1, metadata_path_n)
      package_n_minus_1_output = Path.join(temp_root, "package-n-minus-1")
      package_n_output = Path.join(temp_root, "package-n")

      package_n_minus_1 =
        package!(
          toolchain,
          build_output,
          metadata_path_n_minus_1,
          package_n_minus_1_output
        )

      assert_equal!(
        built_files,
        read_tree!(build_output),
        "release build changed during packaging"
      )

      package_n = package!(toolchain, build_output, metadata_path_n, package_n_output)

      assert_equal!(
        built_files,
        read_tree!(build_output),
        "release build changed during packaging"
      )

      assert_equal!(
        metadata_before,
        metadata_state!(metadata_path_n_minus_1, metadata_path_n),
        "package metadata input changed during packaging"
      )

      assert_equal!(source_before, tracked_input_state!(), "frontend input files changed")

      assert_equal!(
        status_before,
        git_status!(),
        "repository status changed during fixture setup"
      )

      %{
        temp_root: temp_root,
        build_output: build_output,
        packages: %{n_minus_1: package_n_minus_1, n: package_n},
        metadata: %{n_minus_1: metadata_n_minus_1, n: metadata_n},
        toolchain: toolchain,
        origin: @origin,
        release_seed: @release_seed,
        source_files: source_before,
        build_files: built_files
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
      {:ok, _removed} -> :ok
      {:error, reason, _path} -> raise "could not clean release fixture: #{inspect(reason)}"
    end
  end

  defp metadata(:n_minus_1) do
    metadata(
      @source_revision_n_minus_1,
      "phase-d-signed-activation-n-minus-1",
      @released_at_n_minus_1
    )
  end

  defp metadata(:n) do
    metadata(@source_revision_n, "phase-d-signed-activation-n", @released_at_n)
  end

  defp metadata(source_revision, build_id, released_at) do
    %{
      "application" => %{"id" => "telemetry_decom", "version" => 1},
      "package" => %{"id" => "cadence.telemetry-applications", "version" => 1},
      "surface" => %{"id" => "packet_bindings", "version" => 1},
      "query" => %{"id" => "cadence.packet_bindings.manage", "version" => 1},
      "actions" => ["save_packet_bindings"],
      "remote" => %{"name" => "cadence_telemetry_decom"},
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
        "sourceRevision" => source_revision,
        "buildId" => build_id,
        "builder" => "github-actions",
        "workflow" => "frontend-release",
        "builtAt" => @built_at
      },
      "releasedAt" => released_at
    }
  end

  defp temporary_root! do
    root =
      Path.join(
        System.tmp_dir!(),
        ".cadence-phase-d-signed-activation-#{System.unique_integer([:positive])}"
      )

    case File.mkdir(root) do
      :ok -> root
      {:error, reason} -> raise "could not create release fixture directory: #{inspect(reason)}"
    end
  end

  defp toolchain! do
    node = configured_executable!(@node_env, "node")
    corepack = configured_executable!(@corepack_env, "corepack")
    node_output = command!(node, ["--version"], @repo_root, tool_env(node))

    unless String.trim(node_output) == @node_version do
      raise "release fixture requires Node #{@node_version}, got #{String.trim(node_output)}"
    end

    pnpm_output =
      command!(
        corepack,
        [@package_manager, "--version"],
        @frontend_root,
        tool_env(node)
      )

    unless String.trim(pnpm_output) == @pnpm_version do
      raise "release fixture requires Corepack pnpm #{@pnpm_version}, got #{String.trim(pnpm_output)}"
    end

    %{node: node, corepack: corepack, path: Path.dirname(node)}
  end

  defp configured_executable!(environment_name, fallback_name) do
    path = System.get_env(environment_name) || System.find_executable(fallback_name)

    cond do
      is_nil(path) ->
        raise "#{environment_name} or #{fallback_name} is required for signed release proof"

      Path.type(path) != :absolute ->
        raise "#{environment_name} must be an absolute executable path"

      not File.regular?(path) ->
        raise "#{environment_name} does not name a regular executable"

      true ->
        path
    end
  end

  defp tool_env(node) do
    [{"PATH", Path.dirname(node) <> ":" <> System.get_env("PATH", "")}]
  end

  defp run_pnpm!(toolchain, args, extra_env) do
    command!(
      toolchain.corepack,
      [@package_manager | args],
      @frontend_root,
      tool_env(toolchain.node) ++ extra_env
    )
  end

  defp package!(toolchain, input_directory, metadata_path, output_directory) do
    command!(
      toolchain.node,
      [
        @package_tool,
        "--input-dir",
        input_directory,
        "--metadata",
        metadata_path,
        "--artifact-origin",
        @origin,
        "--key-id",
        "fixture-release-key",
        "--output-dir",
        output_directory
      ],
      @repo_root,
      tool_env(toolchain.node) ++ [{"CADENCE_RELEASE_PRIVATE_KEY", "hex:" <> @release_seed}]
    )

    read_package!(output_directory)
  end

  defp command!(executable, args, cwd, env) do
    case System.cmd(executable, args, cd: cwd, env: env, stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, status} ->
        raise "release fixture command failed (#{status}): #{executable} #{Enum.join(args, " ")}\n#{output}"
    end
  end

  defp write_metadata!(temp_root, label, metadata) do
    path = Path.join(temp_root, "metadata-#{label}.json")
    File.write!(path, Jason.encode!(metadata))
    path
  end

  defp read_package!(output_directory) do
    files = read_tree!(output_directory)
    document_bytes = Map.fetch!(files, "release.json")
    envelope = Jason.decode!(document_bytes)
    payload_bytes = Base.url_decode64!(envelope["payload"], padding: false)
    release = Jason.decode!(payload_bytes)

    artifacts =
      files
      |> Enum.filter(fn {path, _bytes} -> String.starts_with?(path, "artifacts/") end)
      |> Enum.map(fn {path, bytes} ->
        artifact_path = String.replace_prefix(path, "artifacts/", "")
        declaration = Enum.find(release["artifacts"], &(&1["path"] == artifact_path))

        if is_nil(declaration) do
          raise "package contains an undeclared artifact: #{artifact_path}"
        end

        %{
          path: artifact_path,
          bytes: bytes,
          sha256: "sha256:" <> digest_hex(bytes),
          size: byte_size(bytes),
          media_type: declaration["mediaType"]
        }
      end)
      |> Enum.sort_by(& &1.path)

    declared_paths = release["artifacts"] |> Enum.map(& &1["path"]) |> Enum.sort()

    if Enum.map(artifacts, & &1.path) != declared_paths do
      raise "package artifact inventory does not match release.json"
    end

    %{
      output_directory: output_directory,
      document_path: Path.join(output_directory, "release.json"),
      document_bytes: document_bytes,
      envelope: envelope,
      payload_bytes: payload_bytes,
      release: release,
      artifacts: artifacts,
      metadata_fields: @metadata_fields
    }
  end

  defp metadata_state!(n_minus_1_path, n_path) do
    %{
      n_minus_1: {File.stat!(n_minus_1_path).size, File.read!(n_minus_1_path)},
      n: {File.stat!(n_path).size, File.read!(n_path)}
    }
  end

  defp read_tree!(root) do
    unless File.dir?(root), do: raise("release fixture directory is not a directory: #{root}")
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
        %{type: :symlink} -> raise "release fixture output contains a symlink: #{relative_path}"
        %{type: :directory} -> read_tree!(root, path, acc)
        %{type: :regular} -> Map.put(acc, relative_path, File.read!(path))
        _other -> raise "release fixture output contains a non-file: #{relative_path}"
      end
    end)
  end

  defp tracked_input_state! do
    paths =
      @tracked_inputs
      |> git_ls_files!()
      |> Enum.sort()

    Map.new(paths, fn path ->
      state =
        case File.read(Path.join(@repo_root, path)) do
          {:ok, bytes} -> {byte_size(bytes), digest_hex(bytes)}
          {:error, :enoent} -> :deleted
          {:error, reason} -> raise File.Error, reason: reason, action: "read", path: path
        end

      {path, state}
    end)
  end

  defp git_ls_files!(paths) do
    case System.cmd(
           "git",
           ["ls-files", "--cached", "--others", "--exclude-standard", "-z", "--" | paths],
           cd: @repo_root
         ) do
      {output, 0} -> String.split(output, <<0>>, trim: true)
      {output, status} -> raise "git ls-files failed (#{status}): #{output}"
    end
  end

  defp git_status! do
    case System.cmd("git", ["status", "--porcelain=v1", "--untracked-files=all"], cd: @repo_root) do
      {output, 0} -> output
      {output, status} -> raise "git status failed (#{status}): #{output}"
    end
  end

  defp assert_equal!(expected, actual, message) do
    unless expected == actual, do: raise("#{message}: immutable evidence changed")
    :ok
  end

  defp digest_hex(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
