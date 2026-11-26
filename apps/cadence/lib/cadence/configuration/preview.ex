defmodule Cadence.Configuration.Preview do
  @moduledoc """
  Dry run of a set of ops: the real `Pipeline` inside a transaction that is always rolled back.

  A preview takes **no apply locks** (no head lock), so a slow preview never blocks an apply, and
  it runs under a statement timeout. Because kinds follow the `Cadence.Platform.ConfigKind`
  side-effect rule, nothing a preview does is observable outside its transaction.
  """

  alias Cadence.Configuration.{Pipeline, Rollback}
  alias Cadence.Repo

  @statement_timeout_ms 15_000

  @type check :: %{key: String.t(), verdict: :go | :hold | :no_go, items: [map()]}
  @type t :: %{
          verdict: :go | :hold | :no_go,
          checks: [check()],
          effects: [map()],
          diffs: [map()]
        }

  @doc """
  Options: `outcome:` a zero-arity reader (#522). Only the explicit preview passes one; the
  preview that submit and review run as their gate never does (api-ops). It's called before and
  after the staged ops, inside this transaction, each time behind a savepoint: a read that fails
  rolls back to the savepoint and gives `outcome: nil`, never changing the verdict or checks.
  With a reader the answer has `outcome: %{now, after} | nil` (nil also when the pipeline didn't
  fully check the set: a halt, errors or conflicts).
  """
  @spec run(String.t(), String.t(), integer(), [Pipeline.op()], keyword()) ::
          {:ok, t()} | {:error, term()}
  def run(organization_id, mission_id, base_revision, ops, opts \\ []) do
    reader = Keyword.get(opts, :outcome)

    Repo.transaction(
      fn ->
        Repo.query!("SET LOCAL statement_timeout = #{@statement_timeout_ms}")
        now = guarded(reader)

        result =
          organization_id
          |> Pipeline.run(mission_id, base_revision, ops)
          |> Map.update(:holds, Rollback.holds(ops), &(&1 ++ Rollback.holds(ops)))

        later = if checked?(result), do: guarded(reader), else: nil
        Repo.rollback({:preview, result, pair(reader, now, later)})
      end,
      timeout: @statement_timeout_ms + 5_000
    )
    |> case do
      {:error, {:preview, result, :none}} ->
        {:ok, summarize(result)}

      {:error, {:preview, result, outcome}} ->
        {:ok, Map.put(summarize(result), :outcome, outcome)}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, {:preview_failed, Exception.message(error)}}
  end

  defp guarded(nil), do: nil

  defp guarded(reader) when is_function(reader, 0) do
    Repo.query!("SAVEPOINT preview_outcome")

    try do
      value = reader.()
      Repo.query!("RELEASE SAVEPOINT preview_outcome")
      value
    rescue
      _error ->
        Repo.query!("ROLLBACK TO SAVEPOINT preview_outcome")
        nil
    end
  end

  # Only a set the pipeline fully checked has an "after": with errors, conflicts or a halt, the
  # derived kinds (routes, compatibility) never ran, so the after-state would mislead.
  defp checked?(result),
    do:
      Map.get(result, :halted?) != true and Map.get(result, :errors, []) == [] and
        Map.get(result, :conflicts, []) == []

  defp pair(nil, _now, _later), do: :none
  defp pair(_reader, nil, _later), do: nil
  defp pair(_reader, _now, nil), do: nil
  defp pair(_reader, now, later), do: %{now: now, after: later}

  @doc "Turns a pipeline result into GO / HOLD / NO-GO checks."
  @spec summarize(Pipeline.result()) :: t()
  def summarize(result) do
    checks = [
      check("validation", result.errors ++ halted(result)),
      check("conflicts", result.conflicts),
      hold_check("compatibility", Map.get(result, :holds, []))
    ]

    %{
      verdict: verdict(checks),
      checks: checks,
      effects: result.effects,
      diffs: result.diffs
    }
  end

  @doc "Whether a HOLD can't be acknowledged away yet (a blocking item)."
  @spec blocked?(t()) :: boolean()
  def blocked?(%{checks: checks}), do: Enum.any?(checks, &(Map.get(&1, :blocking) == true))

  @spec go?(t()) :: boolean()
  def go?(%{verdict: verdict}), do: verdict != :no_go

  defp hold_check(key, []), do: %{key: key, verdict: :go, items: [], blocking: false}

  # A blocking item (DECISIONS #65: a command in flight, a pending configuration) can't be
  # acknowledged away: the apply waits until it clears.
  defp hold_check(key, items),
    do: %{
      key: key,
      verdict: :hold,
      items: items,
      blocking: Enum.any?(items, &(&1[:blocking] == true))
    }

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
