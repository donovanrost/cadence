defmodule Cadence.Alarms.SuggestionStrategy do
  @moduledoc """
  Behaviour for generating intelligent alarm rule suggestions.

  Strategies analyze uncovered parameters and generate context-aware rule
  suggestions based on parameter semantics, data types, and mission context.

  ## Built-in Strategies

  - `Cadence.Alarms.SuggestionStrategy.Default` - Basic two-rule strategy
  - `Cadence.Alarms.SuggestionStrategy.Semantic` - Naming-pattern aware strategy

  ## Implementing a Custom Strategy

      defmodule MyStrategy do
        @behaviour Cadence.Alarms.SuggestionStrategy

        @impl true
        def suggest(parameter, context) do
          # Analyze parameter and return suggestions
          [%{...}, %{...}]
        end

        @impl true
        def name, do: "My Custom Strategy"

        @impl true
        def description, do: "Does something special"
      end
  """

  alias Cadence.Alarms.CoverageAnalyzer

  @type parameter :: CoverageAnalyzer.parameter_with_limits()

  @type context :: %{
          mission_id: String.t(),
          organization_id: String.t(),
          definition_set_id: String.t()
        }

  @type suggestion :: %{
          name: String.t(),
          event_type: String.t(),
          conditions: map(),
          severity: atom(),
          message_template: String.t(),
          parameter: parameter(),
          # Strategy-specific metadata about why this suggestion was made
          rationale: String.t() | nil,
          # Confidence score (0.0 - 1.0) for how appropriate this suggestion is
          confidence: float()
        }

  @doc """
  Generates suggestions for a single uncovered parameter.

  Returns a list of suggestion maps, typically one per severity level
  (critical, warning, info) that the strategy determines is appropriate.
  """
  @callback suggest(parameter(), context()) :: [suggestion()]

  @doc """
  Returns the human-readable name of this strategy.
  """
  @callback name() :: String.t()

  @doc """
  Returns a description of what this strategy does.
  """
  @callback description() :: String.t()

  @doc """
  Optional: Returns parameter categories this strategy specializes in.

  Strategies can indicate which types of parameters they handle best,
  allowing the system to combine multiple strategies intelligently.
  """
  @callback specializes_in() :: [atom()]
  @optional_callbacks [specializes_in: 0]
end
