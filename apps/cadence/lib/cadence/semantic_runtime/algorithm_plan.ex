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
          implementation: map(),
          space_system_id: binary() | nil,
          runtime_name: binary() | nil
        }

  @enforce_keys [:algorithm_id, :input_parameter_ids, :outputs]
  defstruct @enforce_keys ++
              [
                triggers: [],
                missing_input: :skip,
                maximum_age_ms: nil,
                quality_policy: :worst_input,
                time_basis: :receipt_time,
                implementation: %{kind: :expression},
                # The owning SpaceSystem and qualified runtime name (ADR-020 P5); nil for a plan
                # compiled before them. Where an algorithm lives is not what it computes.
                space_system_id: nil,
                runtime_name: nil
              ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      algorithm_id: value(attrs, :algorithm_id),
      input_parameter_ids: value(attrs, :input_parameter_ids, []),
      outputs: value(attrs, :outputs, []) |> Enum.map(&output/1),
      triggers: value(attrs, :triggers, []),
      missing_input: attrs |> value(:missing_input, :skip) |> decode(:missing_input),
      maximum_age_ms: value(attrs, :maximum_age_ms),
      quality_policy: attrs |> value(:quality_policy, :worst_input) |> decode(:quality_policy),
      time_basis: attrs |> value(:time_basis, :receipt_time) |> decode(:time_basis),
      implementation: value(attrs, :implementation, %{kind: :expression}),
      space_system_id: value(attrs, :space_system_id),
      runtime_name: value(attrs, :runtime_name)
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

  # The settings decode through closed maps of the runtime's own vocabulary (the compiler writes
  # these names since #1114), so a compiled plan never reaches evaluation with a value the evaluator
  # has no clause for: an unmapped `:receipt` once raised in the staleness check and tripped the
  # partition (#451 T4a). Any other value, an old catalog name included, is refused here, when the
  # plan is decoded, with the setting named.
  @vocabulary %{
    time_basis: %{"receipt_time" => :receipt_time, "generation_time" => :generation_time},
    quality_policy: %{"worst_input" => :worst_input},
    missing_input: %{"skip" => :skip, "bad_quality" => :bad_quality}
  }

  defp decode(value, setting) do
    case Map.fetch(Map.fetch!(@vocabulary, setting), to_string(value)) do
      {:ok, decoded} ->
        decoded

      :error ->
        raise ArgumentError,
              "algorithm plan #{setting} #{inspect(value)} is not one of " <>
                inspect(Map.keys(Map.fetch!(@vocabulary, setting)))
    end
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
