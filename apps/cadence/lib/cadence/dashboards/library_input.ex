defmodule Cadence.Dashboards.LibraryInput do
  @moduledoc "Bounded input for reusable widget authoring and library navigation."
  alias Cadence.Dashboards.AuthoringInput
  @max_version 9_007_199_254_740_990
  @query_keys ~w(q after item_id version before_version consumer_after dashboard_query dashboard_after target_id)

  def query(params) when is_map(params) do
    with true <- Map.keys(params) -- @query_keys == [],
         true <-
           Enum.all?(~w(q dashboard_query), &AuthoringInput.text?(Map.get(params, &1, ""), 120)),
         true <-
           Enum.all?(
             ~w(after item_id consumer_after dashboard_after target_id),
             &optional_id?(params[&1])
           ),
         {:ok, version} <- number_text(params["version"]),
         {:ok, before_version} <- number_text(params["before_version"]),
         true <-
           params["item_id"] != nil or
             (is_nil(version) and is_nil(before_version) and is_nil(params["consumer_after"])) do
      {:ok,
       %{
         q: String.trim(Map.get(params, "q", "")),
         after: params["after"],
         item_id: params["item_id"],
         version: version,
         before_version: before_version,
         consumer_after: params["consumer_after"],
         dashboard_query: String.trim(Map.get(params, "dashboard_query", "")),
         dashboard_after: params["dashboard_after"],
         target_id: params["target_id"]
       }}
    else
      _ -> {:error, :invalid_input}
    end
  end

  def query(_), do: {:error, :invalid_input}

  def admit("create_item", input) when is_map(input) do
    if exact?(input, ~w(name description change_summary widget_json)) and
         AuthoringInput.text?(input["name"], 120) and String.trim(input["name"]) != "" and
         AuthoringInput.text?(input["description"], 4096) and summary?(input),
       do: widget(input),
       else: {:error, :invalid_input}
  end

  def admit("add_version", input) when is_map(input) do
    if exact?(input, ~w(item_id expected_version change_summary widget_json)) and
         id?(input["item_id"]) and version?(input["expected_version"]) and summary?(input),
       do: widget(input),
       else: {:error, :invalid_input}
  end

  def admit("add_to_draft", input) when is_map(input) do
    if exact?(input, ~w(item_id version dashboard_id expected_version)) and
         Enum.all?(~w(item_id dashboard_id), &id?(input[&1])) and
         Enum.all?(~w(version expected_version), &version?(input[&1])),
       do: {:ok, input},
       else: {:error, :invalid_input}
  end

  def admit(_, _), do: {:error, :invalid_input}

  def decode(json) do
    with true <- AuthoringInput.text?(json, 32_768),
         {:ok, value} when is_map(value) <- Jason.decode(json),
         true <- bounded?(value, 0),
         true <-
           Map.keys(value) -- ~w(widget_type_id widget_type_version title binding options) == [],
         true <- id?(value["widget_type_id"]),
         true <- version?(Map.get(value, "widget_type_version", 1)),
         true <- is_nil(value["title"]) or AuthoringInput.text?(value["title"], 4096),
         true <- is_map(Map.get(value, "binding", %{})) and is_map(Map.get(value, "options", %{})) do
      {:ok, value}
    else
      _ -> {:error, :invalid_widget}
    end
  end

  def encode(value) do
    with {:ok, json} <- Jason.encode(value), {:ok, _} <- decode(json), do: {:ok, json}
  end

  def id?(value), do: AuthoringInput.id?(value) and not Regex.match?(~r/[\x00-\x1f]/u, value)
  def version?(value), do: is_integer(value) and value in 1..@max_version
  defp optional_id?(nil), do: true
  defp optional_id?(value), do: id?(value)
  defp summary?(input), do: AuthoringInput.text?(input["change_summary"], 4096)
  defp exact?(input, keys), do: Enum.sort(Map.keys(input)) == Enum.sort(keys)

  defp widget(input) do
    with {:ok, definition} <- decode(input["widget_json"]),
         do: {:ok, Map.put(input, "widget_definition", definition)}
  end

  defp number_text(nil), do: {:ok, nil}

  defp number_text(value) when is_binary(value) and byte_size(value) <= 16 do
    case Integer.parse(value) do
      {n, ""} when n in 1..@max_version -> if to_string(n) == value, do: {:ok, n}, else: :error
      _ -> :error
    end
  end

  defp number_text(_), do: :error
  defp bounded?(_, depth) when depth > 8, do: false
  defp bounded?(nil, _), do: true
  defp bounded?(value, _) when is_boolean(value), do: true
  defp bounded?(value, _) when is_number(value), do: abs(value) <= @max_version
  defp bounded?(value, _) when is_binary(value), do: byte_size(value) <= 4096

  defp bounded?(value, depth) when is_list(value),
    do: length(value) <= 100 and Enum.all?(value, &bounded?(&1, depth + 1))

  defp bounded?(value, depth) when is_map(value),
    do:
      map_size(value) <= 64 and
        Enum.all?(value, fn {key, value} ->
          byte_size(key) <= 256 and bounded?(value, depth + 1)
        end)

  defp bounded?(_, _), do: false
end
