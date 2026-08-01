defmodule CadenceSimulator.IngressBenchmark.LocalSafety do
  @moduledoc """
  Preflight validation for non-qualifying laptop ingress benchmark runs.

  This module only evaluates a manifest and the container's Linux mount table.
  It does not create files, start traffic, or mutate mounts.
  """

  alias CadenceSimulator.IngressBenchmark.MountInfo

  @type report :: %{
          deployment_kind: binary(),
          storage_profile: binary(),
          planned_source_bytes: non_neg_integer(),
          planned_wall_clock_seconds: non_neg_integer(),
          max_source_bytes: pos_integer(),
          max_wall_clock_seconds: pos_integer(),
          max_artifact_bytes: pos_integer(),
          storage_max_bytes: pos_integer(),
          docker_memory_budget_bytes: pos_integer(),
          docker_overhead_bytes: pos_integer(),
          process_headroom_bytes: pos_integer(),
          container_memory_total_bytes: pos_integer(),
          component: binary() | nil,
          component_memory_limit_bytes: pos_integer() | nil,
          tmpfs_mounts: [map()],
          qualification: :local_safety_only
        }

  @spec validate(map(), keyword()) :: {:ok, report()} | {:error, [binary()]}
  def validate(manifest, opts \\ [])

  def validate(manifest, opts) when is_map(manifest) and is_list(opts) do
    phases = value_at(manifest, [:traffic, :phases])
    {planned_source_bytes, planned_wall_clock_seconds, phase_errors} = traffic_plan(phases)

    deployment_kind = value_at(manifest, [:deployment, :kind])
    storage_profile = value_at(manifest, [:storage, :profile])
    storage_max_bytes = value_at(manifest, [:storage, :max_bytes])
    max_source_bytes = value_at(manifest, [:safety, :max_source_bytes])
    max_wall_clock_seconds = value_at(manifest, [:safety, :max_wall_clock_seconds])
    max_artifact_bytes = value_at(manifest, [:safety, :max_artifact_bytes])
    docker_memory_budget_bytes = value_at(manifest, [:safety, :docker_memory_budget_bytes])
    docker_overhead_bytes = value_at(manifest, [:safety, :docker_overhead_bytes])
    process_headroom_bytes = value_at(manifest, [:safety, :process_headroom_bytes])
    containers = value_at(manifest, [:deployment, :containers])
    component = Keyword.get(opts, :component)
    container_memory_limits = container_memory_limits(containers)
    component_memory_limit_bytes = component_memory_limit(containers, component)
    all_tmpfs_declarations = value_at(manifest, [:storage, :tmpfs_mounts])

    {tmpfs_declarations, component_mount_errors} =
      component_tmpfs_declarations(
        all_tmpfs_declarations,
        value_at(manifest, [:storage, :component_tmpfs_paths]),
        component
      )

    {tmpfs_mounts, mount_errors} = validate_tmpfs_mounts(tmpfs_declarations, opts)

    errors =
      phase_errors ++
        required_profile_errors(manifest, deployment_kind, storage_profile) ++
        positive_limit_errors([
          {:storage_max_bytes, storage_max_bytes},
          {:max_source_bytes, max_source_bytes},
          {:max_wall_clock_seconds, max_wall_clock_seconds},
          {:max_artifact_bytes, max_artifact_bytes},
          {:docker_memory_budget_bytes, docker_memory_budget_bytes},
          {:docker_overhead_bytes, docker_overhead_bytes},
          {:process_headroom_bytes, process_headroom_bytes}
        ]) ++
        container_limit_errors(containers, container_memory_limits, component) ++
        budget_errors(
          planned_source_bytes,
          planned_wall_clock_seconds,
          max_source_bytes,
          max_wall_clock_seconds
        ) ++
        mount_budget_errors(all_tmpfs_declarations, storage_max_bytes) ++
        memory_budget_errors(
          tmpfs_mounts,
          storage_max_bytes,
          container_memory_limits,
          component_memory_limit_bytes,
          docker_memory_budget_bytes,
          docker_overhead_bytes,
          process_headroom_bytes
        ) ++ component_mount_errors ++ mount_errors

    case errors do
      [] ->
        {:ok,
         %{
           deployment_kind: deployment_kind,
           storage_profile: storage_profile,
           planned_source_bytes: planned_source_bytes,
           planned_wall_clock_seconds: planned_wall_clock_seconds,
           max_source_bytes: max_source_bytes,
           max_wall_clock_seconds: max_wall_clock_seconds,
           max_artifact_bytes: max_artifact_bytes,
           storage_max_bytes: storage_max_bytes,
           docker_memory_budget_bytes: docker_memory_budget_bytes,
           docker_overhead_bytes: docker_overhead_bytes,
           process_headroom_bytes: process_headroom_bytes,
           container_memory_total_bytes: Enum.sum(container_memory_limits),
           component: component,
           component_memory_limit_bytes: component_memory_limit_bytes,
           tmpfs_mounts: tmpfs_mounts,
           qualification: :local_safety_only
         }}

      _errors ->
        {:error, Enum.uniq(errors)}
    end
  end

  def validate(_manifest, _opts), do: {:error, ["manifest must be a map"]}

  defp required_profile_errors(manifest, deployment_kind, storage_profile) do
    []
    |> maybe_error(
      value_at(manifest, [:schema_version]) != 1,
      "schema_version must be 1"
    )
    |> maybe_error(
      deployment_kind != "compose",
      "laptop preflight requires deployment.kind=compose"
    )
    |> maybe_error(
      storage_profile != "laptop_tmpfs",
      "laptop preflight requires storage.profile=laptop_tmpfs"
    )
  end

  defp positive_limit_errors(limits) do
    Enum.flat_map(limits, fn {name, value} ->
      if positive_integer?(value), do: [], else: ["#{name} must be a positive integer"]
    end)
  end

  defp budget_errors(planned_bytes, planned_seconds, max_bytes, max_seconds) do
    []
    |> maybe_error(
      positive_integer?(max_bytes) and planned_bytes > max_bytes,
      "traffic schedule exceeds safety.max_source_bytes"
    )
    |> maybe_error(
      positive_integer?(max_seconds) and planned_seconds > max_seconds,
      "traffic schedule exceeds safety.max_wall_clock_seconds"
    )
  end

  defp mount_budget_errors(declarations, storage_max_bytes) when is_list(declarations) do
    configured_bytes =
      Enum.reduce(declarations, 0, fn declaration, total ->
        case field(declaration, :max_bytes) do
          bytes when is_integer(bytes) and bytes > 0 -> total + bytes
          _invalid -> total
        end
      end)

    if positive_integer?(storage_max_bytes) and configured_bytes > storage_max_bytes do
      ["declared tmpfs mount limits exceed storage.max_bytes"]
    else
      []
    end
  end

  defp mount_budget_errors(_declarations, _storage_max_bytes), do: []

  defp component_tmpfs_declarations(declarations, scopes, component)
       when is_list(declarations) and is_map(scopes) and is_binary(component) do
    case Map.fetch(scopes, component) do
      {:ok, paths} when is_list(paths) and paths != [] ->
        declarations_by_path = Map.new(declarations, &{field(&1, :path), &1})
        missing_paths = Enum.reject(paths, &Map.has_key?(declarations_by_path, &1))

        errors =
          if missing_paths == [] do
            []
          else
            [
              "storage.component_tmpfs_paths.#{component} references undeclared paths: #{Enum.join(missing_paths, ", ")}"
            ]
          end

        {Enum.flat_map(paths, &List.wrap(Map.get(declarations_by_path, &1))), errors}

      {:ok, _invalid} ->
        {[], ["storage.component_tmpfs_paths.#{component} must be a non-empty path list"]}

      :error ->
        {declarations, []}
    end
  end

  defp component_tmpfs_declarations(declarations, _scopes, _component),
    do: {declarations, []}

  defp container_limit_errors(containers, limits, component) do
    []
    |> maybe_error(
      not is_map(containers) or map_size(containers) == 0,
      "deployment.containers must declare memory_limit_bytes for every laptop container"
    )
    |> maybe_error(
      is_map(containers) and length(limits) != map_size(containers),
      "every deployment container requires a positive memory_limit_bytes"
    )
    |> maybe_error(
      is_binary(component) and is_nil(component_memory_limit(containers, component)),
      "selected component #{component} has no declared memory limit"
    )
  end

  defp memory_budget_errors(
         mounts,
         storage_max_bytes,
         container_limits,
         component_memory_limit_bytes,
         docker_memory_budget_bytes,
         docker_overhead_bytes,
         process_headroom_bytes
       ) do
    component_memory_errors(
      mounts,
      component_memory_limit_bytes,
      process_headroom_bytes
    ) ++
      docker_memory_errors(
        storage_max_bytes,
        container_limits,
        docker_memory_budget_bytes,
        docker_overhead_bytes,
        process_headroom_bytes
      )
  end

  defp component_memory_errors(mounts, component_memory_limit_bytes, process_headroom_bytes) do
    configured_mount_bytes = Enum.reduce(mounts, 0, &(&1.configured_max_bytes + &2))

    []
    |> maybe_error(
      positive_integer?(component_memory_limit_bytes) and
        positive_integer?(process_headroom_bytes) and
        configured_mount_bytes + process_headroom_bytes > component_memory_limit_bytes,
      "declared tmpfs mounts plus process headroom exceed the selected container memory limit"
    )
  end

  defp docker_memory_errors(
         storage_max_bytes,
         container_limits,
         docker_memory_budget_bytes,
         docker_overhead_bytes,
         process_headroom_bytes
       ) do
    []
    |> maybe_error(
      positive_integer?(docker_memory_budget_bytes) and
        positive_integer?(docker_overhead_bytes) and
        container_limits != [] and
        Enum.sum(container_limits) + docker_overhead_bytes > docker_memory_budget_bytes,
      "container memory limits plus Docker overhead exceed the Docker memory budget"
    )
    |> maybe_error(
      positive_integer?(storage_max_bytes) and positive_integer?(process_headroom_bytes) and
        positive_integer?(docker_overhead_bytes) and positive_integer?(docker_memory_budget_bytes) and
        storage_max_bytes + process_headroom_bytes + docker_overhead_bytes >
          docker_memory_budget_bytes,
      "storage, process headroom, and Docker overhead exceed the Docker memory budget"
    )
  end

  defp container_memory_limits(containers) when is_map(containers) do
    Enum.flat_map(containers, fn {_name, config} ->
      case field(config, :memory_limit_bytes) do
        value when is_integer(value) and value > 0 -> [value]
        _invalid -> []
      end
    end)
  end

  defp container_memory_limits(_containers), do: []

  defp component_memory_limit(_containers, nil), do: nil

  defp component_memory_limit(containers, component)
       when is_map(containers) and is_binary(component) do
    containers
    |> Enum.find_value(fn {name, config} ->
      if to_string(name) == component, do: field(config, :memory_limit_bytes)
    end)
  end

  defp component_memory_limit(_containers, _component), do: nil

  defp traffic_plan(phases) when is_list(phases) and phases != [] do
    Enum.reduce(phases, {0, 0, []}, fn phase, {bytes, seconds, errors} ->
      duration_seconds = field(phase, :duration_seconds)
      target_bps = field(phase, :target_bps)

      if positive_integer?(duration_seconds) and non_negative_integer?(target_bps) do
        phase_bytes = div(target_bps * duration_seconds + 7, 8)
        {bytes + phase_bytes, seconds + duration_seconds, errors}
      else
        {bytes, seconds,
         [
           "every traffic phase requires positive duration_seconds and non-negative target_bps"
           | errors
         ]}
      end
    end)
  end

  defp traffic_plan(_phases), do: {0, 0, ["traffic.phases must be a non-empty list"]}

  defp validate_tmpfs_mounts(declarations, opts)
       when is_list(declarations) and declarations != [] do
    case mountinfo(opts) do
      {:ok, mountinfo} ->
        mounts = MountInfo.parse(mountinfo)

        declarations
        |> Enum.map(&validate_tmpfs_mount(&1, mounts))
        |> Enum.reduce({[], []}, fn
          {:ok, mount}, {valid, errors} -> {[mount | valid], errors}
          {:error, error}, {valid, errors} -> {valid, [error | errors]}
        end)
        |> then(fn {valid, errors} -> {Enum.reverse(valid), Enum.reverse(errors)} end)

      {:error, reason} ->
        {[], [reason]}
    end
  end

  defp validate_tmpfs_mounts(_declarations, _opts) do
    {[], ["storage.tmpfs_mounts must declare at least one bounded path"]}
  end

  defp validate_tmpfs_mount(declaration, mounts) when is_map(declaration) do
    path = field(declaration, :path)
    configured_max_bytes = field(declaration, :max_bytes)

    cond do
      not is_binary(path) or not String.starts_with?(path, "/") ->
        {:error, "every tmpfs declaration requires an absolute path"}

      not positive_integer?(configured_max_bytes) ->
        {:error, "tmpfs mount #{path} requires a positive max_bytes"}

      true ->
        validate_resolved_mount(path, configured_max_bytes, mounts)
    end
  end

  defp validate_tmpfs_mount(_declaration, _mounts) do
    {:error, "every storage.tmpfs_mounts entry must be a map"}
  end

  defp validate_resolved_mount(path, configured_max_bytes, mounts) do
    case MountInfo.resolve(path, mounts) do
      nil ->
        {:error, "high-volume path #{path} does not resolve to a mounted filesystem"}

      %{filesystem: filesystem} when filesystem != "tmpfs" ->
        {:error, "high-volume path #{path} resolves to #{filesystem}, not tmpfs"}

      %{size_bytes: nil} ->
        {:error, "tmpfs path #{path} does not report an explicit size limit"}

      %{size_bytes: observed_max_bytes} when observed_max_bytes > configured_max_bytes ->
        {:error, "tmpfs path #{path} is larger than its declared max_bytes"}

      %{mount_point: mount_point, size_bytes: observed_max_bytes} ->
        {:ok,
         %{
           path: path,
           mount_point: mount_point,
           configured_max_bytes: configured_max_bytes,
           observed_max_bytes: observed_max_bytes
         }}
    end
  end

  defp mountinfo(opts) do
    case Keyword.fetch(opts, :mountinfo) do
      {:ok, contents} when is_binary(contents) ->
        {:ok, contents}

      {:ok, _invalid} ->
        {:error, "mountinfo must be a string"}

      :error ->
        case File.read("/proc/self/mountinfo") do
          {:ok, contents} ->
            {:ok, contents}

          {:error, _reason} ->
            {:error, "Linux /proc/self/mountinfo is unavailable; run preflight in the container"}
        end
    end
  end

  defp value_at(map, path) do
    Enum.reduce_while(path, map, fn key, value ->
      case field(value, key) do
        nil -> {:halt, nil}
        nested -> {:cont, nested}
      end
    end)
  end

  defp field(map, key) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp field(_value, _key), do: nil

  defp maybe_error(errors, true, message), do: errors ++ [message]
  defp maybe_error(errors, false, _message), do: errors

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0
end
