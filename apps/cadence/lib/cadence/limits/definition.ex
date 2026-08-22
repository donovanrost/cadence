defmodule Cadence.Limits.Definition do
  @moduledoc """
  Mission-scoped governed limit definition for one telemetry point.
  """

  alias Cadence.Ids

  @threshold_keys ["red_low", "yellow_low", "yellow_high", "red_high"]

  @type t :: %__MODULE__{
          limit_definition_id: binary(),
          mission_id: binary(),
          point_id: binary(),
          version: pos_integer(),
          limit_set_name: binary(),
          thresholds: map(),
          metadata: map()
        }

  defstruct [
    :limit_definition_id,
    :mission_id,
    :point_id,
    :version,
    :limit_set_name,
    thresholds: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      limit_definition_id: Map.get(attrs, :limit_definition_id, Ids.new("limit_definition")),
      mission_id: Map.fetch!(attrs, :mission_id),
      point_id: Map.fetch!(attrs, :point_id),
      version: Map.get(attrs, :version, 1),
      limit_set_name: Map.get(attrs, :limit_set_name, "DEFAULT"),
      thresholds: normalize_thresholds(Map.get(attrs, :thresholds, %{})),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = definition) do
    cond do
      definition.mission_id in [nil, ""] ->
        {:error, :missing_mission_id}

      definition.point_id in [nil, ""] ->
        {:error, :missing_point_id}

      not is_map(definition.thresholds) ->
        {:error, :invalid_thresholds}

      Enum.any?(Map.keys(definition.thresholds), &(&1 not in @threshold_keys)) ->
        {:error, :unsupported_threshold_key}

      true ->
        :ok
    end
  end

  defp normalize_thresholds(thresholds) when is_map(thresholds) do
    Map.new(thresholds, fn {key, value} -> {to_string(key), value} end)
  end
end
