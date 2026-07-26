defmodule Cadence.Applications.PreflightReport do
  @moduledoc "Host-standard activation readiness derived from typed preflight checks."

  alias Cadence.Applications.{ApplicationDefinition, PreflightCheck}

  @type state :: PreflightCheck.state()

  @type t :: %__MODULE__{
          application_key: binary(),
          application_version: pos_integer(),
          state: state(),
          summary: binary(),
          checks: [PreflightCheck.t()]
        }

  @enforce_keys [:application_key, :application_version, :state, :summary, :checks]
  defstruct [:application_key, :application_version, :state, :summary, checks: []]

  @spec new(ApplicationDefinition.t(), [PreflightCheck.t()]) :: t()
  def new(%ApplicationDefinition{} = definition, checks) when is_list(checks) do
    state = overall_state(checks)

    %__MODULE__{
      application_key: definition.application_key,
      application_version: definition.version,
      state: state,
      summary: summary(state, checks),
      checks: checks
    }
  end

  @spec ready?(t()) :: boolean()
  def ready?(%__MODULE__{checks: checks}) do
    Enum.all?(checks, &(&1.state != :blocked))
  end

  defp overall_state(checks) do
    cond do
      Enum.any?(checks, &(&1.state == :blocked)) -> :blocked
      Enum.any?(checks, &(&1.state == :attention)) -> :attention
      true -> :ready
    end
  end

  defp summary(:blocked, checks) do
    count = Enum.count(checks, &(&1.state == :blocked))

    "#{count} #{pluralize(count, "blocking check", "blocking checks")} must be resolved before activation."
  end

  defp summary(:attention, checks) do
    count = Enum.count(checks, &(&1.state == :attention))
    "Activation is available with #{count} #{pluralize(count, "advisory", "advisories")}."
  end

  defp summary(:ready, []), do: "No activation prerequisites are declared."
  defp summary(:ready, _checks), do: "All declared dependencies and resource claims are ready."

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural
end
