defmodule Cadence.DerivedTelemetry.Definition do
  @moduledoc """
  Mission-scoped governed definition for one derived telemetry point.
  """

  alias Cadence.DerivedTelemetry.ExpressionEvaluator
  alias Cadence.DerivedTelemetry.ExpressionParser
  alias Cadence.Ids

  @type t :: %__MODULE__{
          derived_definition_id: binary(),
          mission_id: binary(),
          point_id: binary(),
          point_name: binary(),
          expression: binary(),
          version: pos_integer(),
          source_point_ids: [binary()],
          metadata: map()
        }

  defstruct [
    :derived_definition_id,
    :mission_id,
    :point_id,
    :point_name,
    :expression,
    :version,
    source_point_ids: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    expression = Map.fetch!(attrs, :expression)

    %__MODULE__{
      derived_definition_id:
        Map.get(attrs, :derived_definition_id, Ids.new("derived_definition")),
      mission_id: Map.fetch!(attrs, :mission_id),
      point_id: Map.fetch!(attrs, :point_id),
      point_name: Map.get(attrs, :point_name, Map.fetch!(attrs, :point_id)),
      expression: expression,
      version: Map.get(attrs, :version, 1),
      source_point_ids:
        Map.get_lazy(attrs, :source_point_ids, fn ->
          case ExpressionParser.extract_variables(expression) do
            {:ok, point_ids} -> point_ids
            {:error, _reason} -> []
          end
        end),
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

      definition.expression in [nil, ""] ->
        {:error, :missing_expression}

      true ->
        with :ok <- ExpressionEvaluator.validate(definition.expression),
             {:ok, false} <- ExpressionParser.has_stateful_functions?(definition.expression) do
          :ok
        else
          {:ok, true} -> {:error, :stateful_functions_not_supported}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
