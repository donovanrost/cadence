defmodule CadenceWeb.Console.PassListParams do
  @moduledoc """
  `GET …/passes` query params beyond the window (docs/apogee/api/contacts.md): `states` (a comma
  list of reservation words, plus a hand-started contact's own `defined`/`stopped`), `station`,
  `order` (`asc`, the default, or `desc` by start) and `include=hand_started` (U78).
  """

  alias Cadence.Reads.HandStartedPasses

  @booked ~w(requesting pending confirmed active completed unknown rejected canceling canceled failed)
  @states Enum.uniq(@booked ++ HandStartedPasses.states())
  @default_span_s 86_400

  @doc "Passes look forward: by default `from` is now and `to` is a day later."
  @spec with_defaults(map()) :: map()
  def with_defaults(params) do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    from =
      case DateTime.from_iso8601(params["from"] || "") do
        {:ok, from, _offset} -> from
        _missing -> now
      end

    params
    |> Map.put_new_lazy("from", fn -> DateTime.to_iso8601(now) end)
    |> Map.put_new_lazy("to", fn -> DateTime.to_iso8601(DateTime.add(from, @default_span_s)) end)
  end

  @doc "The read's filters besides the window and spacecraft."
  @spec parse(map()) :: {:ok, map()} | {:error, {:invalid_params, map()}}
  def parse(params) do
    with {:ok, states} <- states(params["states"]),
         {:ok, order} <- order(params["order"]),
         {:ok, hand_started?} <- include(params["include"]) do
      {:ok,
       %{
         station: blank_to_nil(params["station"]),
         states: states,
         order: order,
         hand_started: hand_started?
       }}
    end
  end

  defp states(nil), do: {:ok, nil}
  defp states(""), do: {:ok, nil}

  defp states(value) when is_binary(value) do
    states = value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if Enum.all?(states, &(&1 in @states)),
      do: {:ok, states},
      else: invalid("states", "must be a comma list of #{Enum.join(@states, ", ")}")
  end

  defp states(_value), do: invalid("states", "must be a comma list")

  defp order(nil), do: {:ok, :asc}
  defp order("asc"), do: {:ok, :asc}
  defp order("desc"), do: {:ok, :desc}
  defp order(_value), do: invalid("order", "must be asc or desc")

  defp include(nil), do: {:ok, false}
  defp include(""), do: {:ok, false}
  defp include("hand_started"), do: {:ok, true}
  defp include(_value), do: invalid("include", "must be hand_started")

  defp invalid(key, message), do: {:error, {:invalid_params, %{key => message}}}

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
