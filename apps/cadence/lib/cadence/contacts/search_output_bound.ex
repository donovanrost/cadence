defmodule Cadence.Contacts.SearchOutputBound do
  @moduledoc """
  Bounds an opportunity search result to what the console API answers in one response: as many
  opportunities as fit in 60 KB of trusted JSON, in order, with `truncated` set when some don't.
  """

  alias Cadence.Applications.JSONBoundary

  @max_bytes 60_000

  @doc "The result, cut to fit; `{:error, :opportunity_response_unavailable}` if it can't be made safe."
  @spec bound(map()) :: {:ok, map()} | {:error, :opportunity_response_unavailable}
  def bound(result) do
    base = Map.put(result, "opportunities", [])

    bounded =
      Enum.reduce_while(result["opportunities"], base, fn opportunity, acc ->
        candidate = Map.update!(acc, "opportunities", &(&1 ++ [opportunity]))

        if fits?(candidate),
          do: {:cont, candidate},
          else: {:halt, Map.put(acc, "truncated", true)}
      end)

    case JSONBoundary.safe_trusted_output(bounded) do
      {:ok, safe} -> {:ok, safe}
      {:error, _} -> {:error, :opportunity_response_unavailable}
    end
  end

  defp fits?(candidate) do
    case JSONBoundary.safe_trusted_output(candidate) do
      {:ok, safe} -> byte_size(Jason.encode!(safe)) <= @max_bytes
      {:error, _} -> false
    end
  end
end
