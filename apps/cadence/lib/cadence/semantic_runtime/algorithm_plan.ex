defmodule Cadence.SemanticRuntime.AlgorithmPlan do
  @moduledoc "Executable safe-core algorithm definition."

  alias Cadence.Catalog.MissionModel.Expression

  @type t :: %__MODULE__{
          algorithm_id: binary(),
          input_parameter_ids: [binary()],
          outputs: [
            %{parameter_id: binary(), qualified_name: binary(), expression: Expression.t()}
          ],
          triggers: [map()],
          missing_input: :skip | :bad_quality,
          maximum_age_ms: non_neg_integer() | nil,
          quality_policy: :worst_input,
          time_basis: :receipt_time | :generation_time,
          implementation: map()
        }

  @enforce_keys [:algorithm_id, :input_parameter_ids, :outputs]
  defstruct @enforce_keys ++
              [
                triggers: [],
                missing_input: :skip,
                maximum_age_ms: nil,
                quality_policy: :worst_input,
                time_basis: :receipt_time,
                implementation: %{kind: :expression}
              ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      algorithm_id: value(attrs, :algorithm_id),
      input_parameter_ids: value(attrs, :input_parameter_ids, []),
      outputs: value(attrs, :outputs, []) |> Enum.map(&output/1),
      triggers: value(attrs, :triggers, []),
      missing_input: attrs |> value(:missing_input, :skip) |> normalize_atom(),
      maximum_age_ms: value(attrs, :maximum_age_ms),
      quality_policy: attrs |> value(:quality_policy, :worst_input) |> normalize_atom(),
      time_basis: attrs |> value(:time_basis, :receipt_time) |> normalize_atom(),
      implementation: value(attrs, :implementation, %{kind: :expression})
    }
  end

  defp output(attrs) do
    %{
      parameter_id: value(attrs, :parameter_id),
      qualified_name: value(attrs, :qualified_name),
      expression: attrs |> value(:expression) |> build_expression()
    }
  end

  defp build_expression(%Expression{} = expression), do: expression
  defp build_expression(attrs), do: Expression.new(attrs)

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
