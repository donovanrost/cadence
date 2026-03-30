defmodule Cadence.Catalog.Command.Verifier do
  @moduledoc """
  Canonical imported command verification stage.
  """

  alias Cadence.Catalog.Command.{MatchCriteria, Normalize, Provenance}
  alias Cadence.Ids

  @type phase :: :acceptance | :start | :completion | :custom
  @type severity :: :info | :warning | :error | :critical | nil

  @type t :: %__MODULE__{
          verifier_id: binary(),
          name: binary(),
          description: binary() | nil,
          phase: phase(),
          success_criteria: MatchCriteria.t() | nil,
          failure_criteria: MatchCriteria.t() | nil,
          timeout_ms: non_neg_integer() | nil,
          delay_ms: non_neg_integer() | nil,
          severity: severity(),
          metadata: map(),
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :verifier_id,
    :name,
    :description,
    :success_criteria,
    :failure_criteria,
    :timeout_ms,
    :delay_ms,
    :severity,
    :provenance,
    phase: :completion,
    metadata: %{},
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      verifier_id: Normalize.get(attrs, :verifier_id, Ids.new("command_verifier")),
      name: Normalize.fetch!(attrs, :name),
      description: Normalize.get(attrs, :description),
      phase: Normalize.get(attrs, :phase, :completion) |> normalize_phase(),
      success_criteria: Normalize.nested(attrs, :success_criteria, MatchCriteria),
      failure_criteria: Normalize.nested(attrs, :failure_criteria, MatchCriteria),
      timeout_ms: Normalize.get(attrs, :timeout_ms),
      delay_ms: Normalize.get(attrs, :delay_ms),
      severity: Normalize.get(attrs, :severity) |> normalize_severity(),
      metadata: Normalize.get(attrs, :metadata, %{}),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp normalize_phase(:acceptance), do: :acceptance
  defp normalize_phase("acceptance"), do: :acceptance
  defp normalize_phase(:start), do: :start
  defp normalize_phase("start"), do: :start
  defp normalize_phase(:completion), do: :completion
  defp normalize_phase("completion"), do: :completion
  defp normalize_phase(:custom), do: :custom
  defp normalize_phase("custom"), do: :custom
  defp normalize_phase(_other), do: :completion

  defp normalize_severity(nil), do: nil
  defp normalize_severity(:info), do: :info
  defp normalize_severity("info"), do: :info
  defp normalize_severity(:warning), do: :warning
  defp normalize_severity("warning"), do: :warning
  defp normalize_severity(:error), do: :error
  defp normalize_severity("error"), do: :error
  defp normalize_severity(:critical), do: :critical
  defp normalize_severity("critical"), do: :critical
  defp normalize_severity(_other), do: nil
end
