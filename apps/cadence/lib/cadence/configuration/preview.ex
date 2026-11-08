defmodule Cadence.Configuration.Preview do
  @moduledoc """
  Dry run of a set of ops: the real `Pipeline` inside a transaction that is always rolled back.

  A preview takes **no apply locks** (no head lock), so a slow preview never blocks an apply, and
  it runs under a statement timeout. Because kinds follow the `Cadence.Platform.ConfigKind`
  side-effect rule, nothing a preview does is observable outside its transaction.
  """

  alias Cadence.Configuration.Pipeline
  alias Cadence.Repo

  @statement_timeout_ms 15_000

  @type check :: %{key: String.t(), verdict: :go | :hold | :no_go, items: [map()]}
  @type t :: %{
          verdict: :go | :hold | :no_go,
          checks: [check()],
          effects: [map()],
          diffs: [map()]
        }

  @spec run(String.t(), String.t(), integer(), [Pipeline.op()]) :: {:ok, t()} | {:error, term()}
  def run(organization_id, mission_id, base_revision, ops) do
    Repo.transaction(
      fn ->
        Repo.query!("SET LOCAL statement_timeout = #{@statement_timeout_ms}")
        result = Pipeline.run(organization_id, mission_id, base_revision, ops)
        Repo.rollback({:preview, result})
      end,
      timeout: @statement_timeout_ms + 5_000
    )
    |> case do
      {:error, {:preview, result}} -> {:ok, summarize(result)}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, {:preview_failed, Exception.message(error)}}
  end

  @doc "Turns a pipeline result into GO / HOLD / NO-GO checks."
  @spec summarize(Pipeline.result()) :: t()
  def summarize(result) do
    checks = [
      check("validation", result.errors ++ halted(result)),
      check("conflicts", result.conflicts)
    ]

    %{
      verdict: verdict(checks),
      checks: checks,
      effects: result.effects,
      diffs: result.diffs
    }
  end

  @spec go?(t()) :: boolean()
  def go?(%{verdict: verdict}), do: verdict != :no_go

  defp check(key, []), do: %{key: key, verdict: :go, items: []}
  defp check(key, items), do: %{key: key, verdict: :no_go, items: items}

  defp halted(%{halted?: true}),
    do: [%{errors: [%{path: "", message: "Later changes were not checked"}]}]

  defp halted(_result), do: []

  defp verdict(checks) do
    cond do
      Enum.any?(checks, &(&1.verdict == :no_go)) -> :no_go
      Enum.any?(checks, &(&1.verdict == :hold)) -> :hold
      true -> :go
    end
  end
end
