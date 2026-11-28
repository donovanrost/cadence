defmodule CadenceWeb.Console.CommandGroupListParams do
  @moduledoc """
  U69 A5a/b/c: `GET /command-groups` query params for `CommandGroups.page/4`: `state`, `stage`,
  `q`, `target`, `withdrawn_revision`, `awaiting_me`, `mine`, `cursor`, `limit`. Contract:
  commanding.md.
  """

  alias Cadence.Reads.CommandGroups.Search

  @states ~w(approval_pending queued rejected sent_back aborted)

  @spec parse(map()) :: {:ok, keyword()} | {:error, {:invalid_params, map()}}
  def parse(params) do
    {opts, errors} =
      Enum.reduce(
        [
          {:states, "state", &list(&1, @states)},
          {:stages, "stage", &list(&1, Search.stages())},
          {:q, "q", &q/1},
          {:target, "target", &target/1},
          {:withdrawn_revision, "withdrawn_revision", &target/1},
          {:limit, "limit", &limit/1}
        ],
        {[], %{}},
        fn {key, name, parse}, {opts, errors} ->
          case parse.(params[name]) do
            {:ok, value} -> {Keyword.put(opts, key, value), errors}
            {:error, message} -> {opts, Map.put(errors, name, message)}
          end
        end
      )

    errors = both_filters(params, errors)

    if errors == %{},
      do:
        {:ok,
         opts ++
           [
             awaiting_me: params["awaiting_me"] == "true",
             mine: params["mine"] == "true",
             cursor: blank_to_nil(params["cursor"])
           ]},
      else: {:error, {:invalid_params, errors}}
  end

  defp list(nil, _allowed), do: {:ok, nil}
  defp list("", _allowed), do: {:ok, nil}

  defp list(value, allowed) when is_binary(value) do
    items = value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if Enum.all?(items, &(&1 in allowed)),
      do: {:ok, items},
      else: {:error, "must be a comma list of #{Enum.join(allowed, ", ")}"}
  end

  defp list(_value, allowed), do: {:error, "must be a comma list of #{Enum.join(allowed, ", ")}"}

  defp q(nil), do: {:ok, nil}

  defp q(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      text when byte_size(text) <= 100 -> {:ok, text}
      _long -> {:error, "must be at most 100 characters"}
    end
  end

  defp q(_value), do: {:error, "must be text"}

  # E2 (#546): the two ways to name craft don't mix.
  defp both_filters(params, errors) do
    if blank_to_nil(params["target"]) && blank_to_nil(params["withdrawn_revision"]),
      do: Map.put(errors, "withdrawn_revision", "can't be combined with target"),
      else: errors
  end

  defp target(nil), do: {:ok, nil}
  defp target(""), do: {:ok, nil}
  defp target(value) when is_binary(value) and byte_size(value) <= 255, do: {:ok, value}
  defp target(_value), do: {:error, "must be a spacecraft id"}

  defp limit(nil), do: {:ok, 100}

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in 1..200 -> {:ok, n}
      _invalid -> {:error, "must be an integer from 1 to 200"}
    end
  end

  defp limit(_value), do: {:error, "must be an integer from 1 to 200"}

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
