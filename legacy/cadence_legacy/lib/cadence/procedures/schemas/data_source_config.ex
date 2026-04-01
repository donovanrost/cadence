defmodule Cadence.Procedures.DataSourceConfig do
  @moduledoc """
  Configuration for a data source at the mission level.

  Data source configs define how procedures access telemetry and other data.
  Multiple sources can be configured per mission, with priority and pattern
  matching to determine which source handles each item path.

  ## Source Types

  - `:cvt` - Current Value Table (real-time spacecraft telemetry)
  - `:tsdb` - Time Series Database (historical data)
  - `:api` - External HTTP API
  - `:manual` - Manual operator entry
  - `:computed` - Derived/computed values

  ## Priority and Pattern Matching

  When a procedure block requests data, sources are matched by:

  1. Path patterns - glob-style matching (e.g., "GROUND.*")
  2. Priority - higher priority sources checked first
  3. Default flag - used when no patterns match

  ## Configuration Examples

  CVT source:
      %{
        "stale_threshold_ms" => 30_000
      }

  TSDB source:
      %{
        "connection_string" => "postgresql://...",
        "database" => "telemetry"
      }

  API source:
      %{
        "base_url" => "https://ground-equipment.local",
        "auth" => %{
          "type" => "bearer",
          "token_env" => "GROUND_API_TOKEN"
        },
        "timeout_ms" => 5000
      }

  ## Path Patterns

  Patterns use glob-style matching:
  - `*` - matches any characters except `.`
  - `**` - matches any characters including `.`

  Examples:
  - `GROUND.*` - matches `GROUND.power`, `GROUND.temp`
  - `*.EPS.*` - matches `SC-001.EPS.voltage`, `SC-002.EPS.current`
  - `*` - matches all paths (default)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Missions.Mission

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types [:cvt, :tsdb, :api, :manual, :computed]

  schema "procedure_data_source_configs" do
    field :source_type, Ecto.Enum, values: @source_types
    field :name, :string
    field :is_default, :boolean, default: false
    field :priority, :integer, default: 0
    field :config, :map, default: %{}
    field :path_patterns, {:array, :string}, default: ["*"]

    belongs_to :mission, Mission

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:mission_id, :source_type, :name]
  @optional_fields [:is_default, :priority, :config, :path_patterns]

  @doc """
  Creates a changeset for a data source config.
  """
  def changeset(config, attrs) do
    config
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 100)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> validate_path_patterns()
    |> validate_config_for_type()
    |> foreign_key_constraint(:mission_id)
  end

  defp validate_path_patterns(changeset) do
    case get_field(changeset, :path_patterns) do
      nil ->
        changeset

      patterns when is_list(patterns) ->
        if Enum.all?(patterns, &valid_pattern?/1) do
          changeset
        else
          add_error(changeset, :path_patterns, "contains invalid patterns")
        end

      _ ->
        add_error(changeset, :path_patterns, "must be a list of strings")
    end
  end

  defp valid_pattern?(pattern) when is_binary(pattern) do
    byte_size(pattern) > 0 and byte_size(pattern) <= 200
  end

  defp valid_pattern?(_), do: false

  defp validate_config_for_type(changeset) do
    source_type = get_field(changeset, :source_type)
    config = get_field(changeset, :config)

    case validate_type_config(source_type, config) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :config, message)
    end
  end

  defp validate_type_config(nil, _), do: :ok
  defp validate_type_config(_, nil), do: :ok

  defp validate_type_config(:api, config) do
    if Map.has_key?(config, "base_url") or Map.has_key?(config, :base_url) do
      :ok
    else
      {:error, "API source requires 'base_url' in config"}
    end
  end

  defp validate_type_config(:tsdb, config) do
    has_connection =
      Map.has_key?(config, "connection_string") or Map.has_key?(config, :connection_string)

    if has_connection do
      :ok
    else
      {:error, "TSDB source requires 'connection_string' in config"}
    end
  end

  # CVT, manual, computed don't require specific config
  defp validate_type_config(_, _), do: :ok

  @doc """
  Returns true if this config matches the given item path.
  """
  def matches_path?(%__MODULE__{path_patterns: patterns}, item_path) do
    Enum.any?(patterns, &pattern_matches?(&1, item_path))
  end

  defp pattern_matches?("*", _path), do: true
  defp pattern_matches?("**", _path), do: true

  defp pattern_matches?(pattern, path) do
    # Convert glob pattern to regex
    regex_pattern =
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("**", ".+")
      |> String.replace("*", "[^.]+")

    case Regex.compile("^#{regex_pattern}$") do
      {:ok, regex} -> Regex.match?(regex, path)
      {:error, _} -> false
    end
  end

  @doc """
  Finds the best matching config for an item path from a list of configs.

  Returns the highest priority config whose patterns match, or the default
  config if no patterns match.
  """
  def find_matching(configs, item_path) when is_list(configs) do
    # Sort by priority descending
    sorted = Enum.sort_by(configs, & &1.priority, :desc)

    # Find first matching
    case Enum.find(sorted, &matches_path?(&1, item_path)) do
      nil -> Enum.find(sorted, & &1.is_default)
      config -> config
    end
  end

  def source_types, do: @source_types
end
