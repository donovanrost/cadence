defmodule Cadence.Catalog.Command.TransmissionConstraint do
  @moduledoc """
  Canonical imported command precondition or interlock.
  """

  alias Cadence.Catalog.Command.{MatchCriteria, Normalize, Provenance}
  alias Cadence.Catalog.Ids

  @type constraint_type :: :precondition | :interlock | :timing_window | :custom

  @type t :: %__MODULE__{
          constraint_id: binary(),
          name: binary(),
          description: binary() | nil,
          constraint_type: constraint_type(),
          criteria: MatchCriteria.t() | nil,
          timeout_ms: non_neg_integer() | nil,
          blocking: boolean(),
          metadata: map(),
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :constraint_id,
    :name,
    :description,
    :criteria,
    :timeout_ms,
    :provenance,
    constraint_type: :precondition,
    blocking: true,
    metadata: %{},
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      constraint_id: Normalize.get(attrs, :constraint_id, Ids.new("command_constraint")),
      name: Normalize.fetch!(attrs, :name),
      description: Normalize.get(attrs, :description),
      constraint_type:
        Normalize.get(attrs, :constraint_type, :precondition) |> normalize_constraint_type(),
      criteria: Normalize.nested(attrs, :criteria, MatchCriteria),
      timeout_ms: Normalize.get(attrs, :timeout_ms),
      blocking: Normalize.get(attrs, :blocking, true),
      metadata: Normalize.get(attrs, :metadata, %{}),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp normalize_constraint_type(:precondition), do: :precondition
  defp normalize_constraint_type("precondition"), do: :precondition
  defp normalize_constraint_type(:interlock), do: :interlock
  defp normalize_constraint_type("interlock"), do: :interlock
  defp normalize_constraint_type(:timing_window), do: :timing_window
  defp normalize_constraint_type("timing_window"), do: :timing_window
  defp normalize_constraint_type(:custom), do: :custom
  defp normalize_constraint_type("custom"), do: :custom
  defp normalize_constraint_type(_other), do: :precondition
end
