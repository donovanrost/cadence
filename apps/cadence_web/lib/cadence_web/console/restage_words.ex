defmodule CadenceWeb.Console.RestageWords do
  @moduledoc """
  D3's `restage_needed` refusal in words (U109, mms-ux on #633): the version a change set staged
  isn't the one to use any more, so nothing was applied. The why comes from each entry's
  `current_reason` (one to one with U109's five), the pin named by its catalog revision number,
  else its composition number, else "this composition"; the line by the act.
  """

  @doc "The refusal's message for `entries` (sorted by composition) and the act that met it."
  @spec message([map()], :apply | :request_review | :approve) :: binary()
  def message([first | rest] = entries, act) do
    why = why(first) <> more(length(rest))
    none_left? = Enum.any?(entries, &(&1[:current_reason] == "none_left"))
    line(act, why, none_left?)
  end

  defp line(:approve, why, none_left?),
    do:
      "Not approved: #{why}, so nothing was applied and the change set stays in review. " <>
        "Your approval wasn't recorded. " <>
        if(none_left?,
          do: "Send it back so it can move to an approved composition.",
          else: "Send it back so it can be staged again."
        )

  defp line(act, why, none_left?),
    do: "#{opener(act)} #{why}, so nothing changed. " <> next(none_left?)

  defp opener(:request_review), do: "Not sent for review:"
  defp opener(_apply), do: "Not applied:"

  defp next(true), do: "Move it to an approved composition first."
  defp next(false), do: "Stage it again to use the current version."

  defp why(entry) do
    pin = pin(entry)

    case entry[:current_reason] do
      "newer_approved" -> "a newer approved version of #{pin} is now the one to use"
      "withdrawn" -> "#{pin}'s approval was withdrawn"
      "unrunnable" -> "the version of #{pin} it staged doesn't run on this version of Cadence"
      "none_left" -> "no approved version of #{pin} is left"
      _unknown -> "the version of #{pin} it staged isn't the one to use any more"
    end
  end

  defp pin(%{catalog_revision_number: n}) when is_integer(n), do: "catalog rev #{n}"
  defp pin(%{composition_number: n}) when is_integer(n), do: "composition #{n}"
  defp pin(_entry), do: "this composition"

  defp more(0), do: ""
  defp more(1), do: " and 1 more catalog revision changed too"
  defp more(n), do: " and #{n} more catalog revisions changed too"
end
