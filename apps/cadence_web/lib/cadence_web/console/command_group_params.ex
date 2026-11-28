defmodule CadenceWeb.Console.CommandGroupParams do
  @moduledoc """
  Parses console command-group bodies into the domain draft and decision
  shapes. Contract: docs/apogee/api/commanding.md. Argument values arrive as
  `argument_values_json` strings (64-bit integers survive) and are decoded by
  the same `ArgumentDocument` rules single requests use. Actors never come
  from the body (DECISIONS #30).
  """

  alias Cadence.Commanding.Groups.Validation
  alias Cadence.Management.Commanding.ArgumentDocument

  @max_text 4_000
  @decisions %{
    "go" => :go,
    "go_excluding" => :go_excluding,
    "send_back" => :send_back,
    "no_go" => :no_go
  }

  @doc """
  The spacecraft ids of an endpoints read: a list in the POST body, at most the size guard's
  `max_targets`, each once.
  """
  @spec spacecraft_ids(map()) :: {:ok, [binary()]} | {:error, term()}
  def spacecraft_ids(%{"spacecraft_ids" => ids}) when is_list(ids) do
    max = Validation.bounds().max_targets

    with {:ok, ids} <- string_list(ids, "spacecraft_ids") do
      if length(ids) > max,
        do: {:error, {:command_group_too_large, %{max_targets: max, targets: length(ids)}}},
        else: {:ok, Enum.uniq(ids)}
    end
  end

  def spacecraft_ids(_params), do: {:ok, []}

  @spec draft(map()) :: {:ok, map()} | {:error, {:invalid_params, map()}}
  def draft(params) when is_map(params) do
    with {:ok, targets} <- targets(params["targets"]),
         {:ok, commands} <- commands(params["commands"]),
         {:ok, not_before} <- time(params, "not_before"),
         {:ok, expires_at} <- time(params, "expires_at"),
         {:ok, priority} <- priority(params["priority"]) do
      {:ok,
       %{
         title: text(params["title"]),
         log_entry: text(params["log_entry"]),
         requested_approver_user_id: text(params["requested_approver_user_id"]),
         sent_back_from: text(params["sent_back_from"]),
         target_query: if(is_map(params["target_query"]), do: params["target_query"], else: %{}),
         targets: targets,
         commands: commands,
         not_before: not_before,
         expires_at: expires_at,
         priority: priority
       }}
    end
  end

  def draft(_params), do: invalid("draft", "must be an object")

  @doc "`draft_revision`: the Compose draft this group came from (deleted if still current)."
  @spec draft_revision(map()) :: {:ok, pos_integer() | nil} | {:error, term()}
  def draft_revision(%{"draft_revision" => n}) when is_integer(n) and n > 0, do: {:ok, n}
  def draft_revision(%{"draft_revision" => nil}), do: {:ok, nil}

  def draft_revision(%{"draft_revision" => _other}),
    do: invalid("draft_revision", "must be a positive integer or null")

  def draft_revision(_params), do: {:ok, nil}

  @max_ack_note 1_000

  @doc """
  `acknowledged_holds: [{key, hold_basis, note}]` (DECISIONS #60). A note is required; the actor is
  the session user.
  """
  @spec acknowledged_holds(map()) :: {:ok, [map()]} | {:error, {:invalid_params, map()}}
  def acknowledged_holds(params) do
    case Map.get(params, "acknowledged_holds") do
      nil -> {:ok, []}
      list when is_list(list) -> list |> Enum.map(&ack/1) |> collect_acks()
      _other -> invalid("acknowledged_holds", "must be a list")
    end
  end

  defp ack(%{"key" => key, "hold_basis" => basis, "note" => note})
       when is_binary(key) and is_binary(basis) and is_binary(note) do
    note = String.trim(note)

    cond do
      note == "" ->
        {:error, "each acknowledgement needs a note"}

      String.length(note) > @max_ack_note ->
        {:error, "notes are at most #{@max_ack_note} characters"}

      true ->
        {:ok, %{key: key, hold_basis: basis, note: note}}
    end
  end

  defp ack(_other), do: {:error, "each item needs key, hold_basis and note"}

  defp collect_acks(results) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, ack} -> ack end)}
      {:error, message} -> invalid("acknowledged_holds", message)
    end
  end

  @spec decision(map()) :: {:ok, map()} | {:error, {:invalid_params, map()}}
  def decision(params) when is_map(params) do
    case Map.fetch(@decisions, params["kind"]) do
      {:ok, kind} ->
        with {:ok, excluded} <- string_list(params["excluded"], "excluded") do
          {:ok,
           %{
             kind: kind,
             excluded: excluded,
             note: text(params["note"]),
             expected_review: text(params["expected_review"])
           }}
        end

      :error ->
        invalid(
          "kind",
          "must be one of #{@decisions |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"
        )
    end
  end

  @spec note(map(), binary()) :: {:ok, binary() | nil} | {:error, {:invalid_params, map()}}
  def note(params, key) when is_map(params) do
    case params[key] do
      nil -> {:ok, nil}
      value when is_binary(value) and byte_size(value) <= @max_text -> {:ok, value}
      _other -> invalid(key, "must be text up to #{@max_text} bytes")
    end
  end

  defp targets(list) when is_list(list) and list != [] do
    Enum.reduce_while(list, {:ok, []}, fn
      %{"spacecraft_id" => id} = target, {:ok, acc} when is_binary(id) and id != "" ->
        {:cont,
         {:ok,
          acc ++ [%{spacecraft_id: id, source_endpoint_id: text(target["source_endpoint_id"])}]}}

      _bad, _acc ->
        {:halt, invalid("targets", "must be a list of {spacecraft_id, source_endpoint_id?}")}
    end)
  end

  defp targets(_list), do: invalid("targets", "must be a non-empty list")

  defp commands(list) when is_list(list) and list != [] do
    list
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {command, index}, {:ok, acc} ->
      case command(command) do
        {:ok, parsed} -> {:cont, {:ok, acc ++ [parsed]}}
        {:error, message} -> {:halt, invalid("commands", "item #{index}: #{message}")}
      end
    end)
  end

  defp commands(_list), do: invalid("commands", "must be a non-empty list")

  defp command(%{"command_id" => id} = command) when is_binary(id) and id != "" do
    with {:ok, values} <- values(Map.get(command, "argument_values_json", "{}")),
         {:ok, per_target} <- per_target(Map.get(command, "per_target")) do
      {:ok, %{command_id: id, argument_values: values, per_target: per_target}}
    end
  end

  defp command(_command), do: {:error, "must be {command_id, argument_values_json}"}

  defp values(json) do
    case ArgumentDocument.decode(json) do
      {:ok, values} -> {:ok, values}
      _invalid -> {:error, "argument_values_json must be a JSON object of scalar values"}
    end
  end

  # Compose "Per target" (CommandFlow B2): values for some targets, overriding the command's own.
  defp per_target(nil), do: {:ok, %{}}

  defp per_target(list) when is_list(list),
    do: Enum.reduce_while(list, {:ok, %{}}, &per_target_entry/2)

  defp per_target(_value),
    do: {:error, "per_target must be [{spacecraft_id, argument_values_json}]"}

  defp per_target_entry(%{"spacecraft_id" => sc} = entry, {:ok, acc})
       when is_binary(sc) and sc != "" do
    if Map.has_key?(acc, sc),
      do: {:halt, {:error, "per_target names #{sc} twice"}},
      else: per_target_values(sc, entry, acc)
  end

  defp per_target_entry(_entry, _acc),
    do: {:halt, {:error, "per_target must be [{spacecraft_id, argument_values_json}]"}}

  defp per_target_values(sc, entry, acc) do
    case values(Map.get(entry, "argument_values_json", "{}")) do
      {:ok, values} -> {:cont, {:ok, Map.put(acc, sc, values)}}
      error -> {:halt, error}
    end
  end

  defp time(params, key) do
    case params[key] do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, at, _offset} -> {:ok, at}
          _error -> invalid(key, "must be an ISO-8601 timestamp")
        end

      _other ->
        invalid(key, "must be an ISO-8601 timestamp")
    end
  end

  defp priority(nil), do: {:ok, 3}
  defp priority(value) when is_integer(value) and value in 0..9, do: {:ok, value}
  defp priority(_value), do: invalid("priority", "must be an integer from 0 to 9")

  defp string_list(nil, _key), do: {:ok, []}

  defp string_list(list, key) when is_list(list) do
    if Enum.all?(list, &(is_binary(&1) and &1 != "")),
      do: {:ok, list},
      else: invalid(key, "must be a list of ids")
  end

  defp string_list(_value, key), do: invalid(key, "must be a list of ids")

  defp text(value) when is_binary(value) and byte_size(value) <= @max_text do
    case String.trim(value) do
      "" -> nil
      _text -> value
    end
  end

  defp text(_value), do: nil

  defp invalid(key, message), do: {:error, {:invalid_params, %{key => message}}}
end
