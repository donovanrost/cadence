defmodule Cadence.ContactPlanning.ContactGaps do
  @moduledoc """
  The one definition of a contact gap (DECISIONS #74), shared by `RequirementEvaluator`
  (`max_gap_exceeded`) and the K1/S4 reads, so they show the number the evaluator checks.

  Over a window `[from, to)`, passes ordered by AOS: a gap runs from LOS to the next AOS, and
  overlapping passes merge. The window's edges count (`from` to the first AOS, the last LOS to
  `to`). A window with no pass is one gap, the whole window.
  """

  @type gap :: %{seconds: non_neg_integer(), from: DateTime.t() | nil, to: DateTime.t() | nil}

  @doc """
  The longest gap: `%{seconds, from, to}` (times at whole seconds; the first of equal gaps). A
  window fully covered reads `seconds: 0` with `from`/`to` nil.
  """
  @spec longest([%{starts_at: DateTime.t(), ends_at: DateTime.t()}], DateTime.t(), DateTime.t()) ::
          gap()
  def longest(passes, %DateTime{} = from, %DateTime{} = to) do
    case passes |> gaps(from, to) |> Enum.max_by(&seconds/1, fn -> nil end) do
      nil ->
        %{seconds: 0, from: nil, to: nil}

      {gap_from, gap_to} = gap ->
        %{
          seconds: seconds(gap),
          from: DateTime.truncate(gap_from, :second),
          to: DateTime.truncate(gap_to, :second)
        }
    end
  end

  defp gaps(passes, from, to) do
    {gaps, cursor} =
      passes
      |> Enum.filter(&(DateTime.before?(&1.starts_at, to) and DateTime.after?(&1.ends_at, from)))
      |> Enum.sort_by(& &1.starts_at, DateTime)
      |> Enum.reduce({[], from}, fn pass, {acc, cursor} ->
        acc =
          if DateTime.after?(pass.starts_at, cursor),
            do: [{cursor, pass.starts_at} | acc],
            else: acc

        {acc, later(cursor, pass.ends_at)}
      end)

    gaps = if DateTime.before?(cursor, to), do: [{cursor, to} | gaps], else: gaps
    Enum.reverse(gaps)
  end

  defp seconds({gap_from, gap_to}), do: DateTime.diff(gap_to, gap_from)

  defp later(a, b), do: if(DateTime.after?(b, a), do: b, else: a)
end
