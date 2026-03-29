defmodule Cadence.DevProfile do
  @moduledoc """
  Loads named developer tooling profiles from `dev/profiles`.

  Profiles are YAML maps that may contain sibling `bootstrap`, `simulator`,
  and `profiler` sections. The simulator CLI already understands `simulator:`
  roots directly, so the same file can drive both bootstrap tooling and the
  standalone simulator runtime.
  """

  @default_profiles_dir Path.expand("../../../../dev/profiles", __DIR__)

  defstruct [:name, :path, root: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          path: String.t(),
          root: map()
        }

  @spec load(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load(identifier) when is_binary(identifier) and identifier != "" do
    with {:ok, path} <- resolve_path(identifier),
         {:ok, yaml_content} <- File.read(path),
         {:ok, parsed} <- YamlElixir.read_from_string(yaml_content),
         {:ok, root} <- normalize_root(parsed) do
      {:ok,
       %__MODULE__{
         name: profile_name(path, root),
         path: path,
         root: Map.put(root, "__profile_path__", path)
       }}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "failed to load dev profile #{inspect(identifier)}: #{inspect(reason)}"}
    end
  end

  @spec load!(String.t()) :: t()
  def load!(identifier) when is_binary(identifier) and identifier != "" do
    case load(identifier) do
      {:ok, profile} -> profile
      {:error, message} -> raise ArgumentError, message
    end
  end

  @spec simulator_config_path(t()) :: String.t()
  def simulator_config_path(%__MODULE__{path: path}), do: path

  @spec resolve_runtime_opts(t(), keyword()) :: keyword()
  def resolve_runtime_opts(%__MODULE__{} = profile, opts) when is_list(opts) do
    opts
    |> resolve_opt_path(profile, :definitions_path)
    |> resolve_opt_path(profile, :scenario_path)
  end

  @spec bootstrap_config(t()) :: map()
  def bootstrap_config(%__MODULE__{} = profile) do
    bootstrap = section(profile, "bootstrap")
    simulator = section(profile, "simulator")
    simulator_cadence = nested_map(simulator, "cadence")

    bootstrap
    |> maybe_put_string("profile_name", profile.name)
    |> maybe_put_string(
      "definitions_path",
      fetch_string(simulator, ["definitions", "definitions_path"])
    )
    |> maybe_put_string(
      "base_url",
      fetch_string(bootstrap, ["base_url", "cadence_url"]) ||
        fetch_string(simulator, ["cadence_url"]) ||
        fetch_string(simulator_cadence, ["url", "cadence_url"])
    )
    |> maybe_put_string(
      "organization_id",
      fetch_string(simulator, ["organization_id"]) ||
        fetch_string(simulator_cadence, ["organization_id"])
    )
    |> maybe_put_string(
      "mission_id",
      fetch_string(simulator, ["mission_id"]) ||
        fetch_string(simulator_cadence, ["mission_id"])
    )
    |> maybe_put_string(
      "api_token",
      fetch_string(simulator, ["api_token"]) ||
        fetch_string(simulator_cadence, ["api_token"])
    )
    |> resolve_map_path(profile, "definitions_path")
  end

  @spec profiler_defaults(t()) :: %{node: String.t() | nil, mission_id: String.t() | nil}
  def profiler_defaults(%__MODULE__{} = profile) do
    profiler = section(profile, "profiler")
    bootstrap = bootstrap_config(profile)

    %{
      node: fetch_string(profiler, ["node"]),
      mission_id:
        fetch_string(profiler, ["mission_id"]) || fetch_string(bootstrap, ["mission_id"])
    }
  end

  @spec section(t(), String.t()) :: map()
  def section(%__MODULE__{root: root}, key) when is_binary(key) do
    nested_map(root, key)
  end

  @spec resolve_path(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def resolve_path(identifier) when is_binary(identifier) and identifier != "" do
    cond do
      File.regular?(identifier) ->
        {:ok, Path.expand(identifier)}

      File.regular?(identifier <> ".yaml") ->
        {:ok, Path.expand(identifier <> ".yaml")}

      true ->
        named_path = Path.join(@default_profiles_dir, identifier <> ".yaml")

        if File.regular?(named_path) do
          {:ok, named_path}
        else
          {:error,
           "could not find dev profile #{inspect(identifier)}. " <>
             "Expected #{inspect(named_path)} or an explicit YAML path."}
        end
    end
  end

  defp normalize_root(%{} = parsed), do: {:ok, parsed}
  defp normalize_root(_parsed), do: {:error, "dev profile must be a YAML map"}

  defp profile_name(path, root) do
    fetch_string(root, ["profile_name"]) ||
      path
      |> Path.basename(".yaml")
      |> Path.basename(".yml")
  end

  defp nested_map(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      %{} = nested -> nested
      _other -> %{}
    end
  end

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, _key, ""), do: map

  defp maybe_put_string(map, key, value) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      nil -> Map.put(map, key, value)
      "" -> Map.put(map, key, value)
      _other -> map
    end
  end

  defp fetch_string(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        value when is_binary(value) and value != "" -> value
        _other -> nil
      end
    end)
  end

  defp resolve_opt_path(opts, _profile, _key) when not is_list(opts), do: opts

  defp resolve_opt_path(opts, profile, key) when is_atom(key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_binary(value) and value != "" ->
        Keyword.put(opts, key, resolve_path_value(profile, value))

      _other ->
        opts
    end
  end

  defp resolve_map_path(map, _profile, _key) when not is_map(map), do: map

  defp resolve_map_path(map, profile, key) when is_binary(key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" ->
        Map.put(map, key, resolve_path_value(profile, value))

      _other ->
        map
    end
  end

  defp resolve_path_value(%__MODULE__{path: profile_path}, value) when is_binary(value) do
    if Path.type(value) == :relative do
      Path.expand(value, Path.dirname(profile_path))
    else
      value
    end
  end
end
