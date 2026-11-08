defmodule CadenceWeb.Console.ConfigParams do
  @moduledoc """
  Translates console JSON bodies into `Cadence.Control.Configuration` inputs.
  Only known keys become atoms; documents, change values and options stay as
  JSON maps (the facade normalizes them).
  """

  @op_keys %{
    "kind" => :kind,
    "action" => :action,
    "entity_id" => :entity_id,
    "document" => :document,
    "changes" => :changes,
    "options" => :options
  }

  @spec stage(map()) :: {:ok, map(), [map()]} | {:error, map()}
  def stage(%{"ops" => ops} = body) when is_list(ops) do
    {:ok, %{summary: body["summary"], source: source(body["source"])}, Enum.map(ops, &op/1)}
  end

  def stage(_body), do: {:error, %{ops: "must be a list of operations"}}

  @spec ops(map()) :: {:ok, [map()]} | {:error, map()}
  def ops(%{"ops" => ops}) when is_list(ops), do: {:ok, Enum.map(ops, &op/1)}
  def ops(_body), do: {:error, %{ops: "must be a list of operations"}}

  @spec submit(map()) :: {:ok, map()} | {:error, map()}
  def submit(body) do
    with {:ok, version} <- expected_version(body) do
      {:ok,
       %{
         reason: string(body["reason"]),
         expected_version: version,
         acknowledged_holds: body["acknowledged_holds"] == true
       }}
    end
  end

  @spec review(map()) :: {:ok, :approve | :send_back, map()} | {:error, map()}
  def review(body) do
    with {:ok, decision} <- decision(body["decision"]),
         {:ok, version} <- expected_version(body) do
      {:ok, decision, %{comment: string(body["comment"]), expected_version: version}}
    end
  end

  @spec expected_version(map()) :: {:ok, integer()} | {:error, map()}
  def expected_version(%{"expected_version" => version}) when is_integer(version),
    do: {:ok, version}

  def expected_version(_body), do: {:error, %{expected_version: "is required (integer)"}}

  @spec rebase_choice(map()) :: {:ok, :keep_mine | :take_live} | {:error, map()}
  def rebase_choice(%{"choice" => "keep_mine"}), do: {:ok, :keep_mine}
  def rebase_choice(%{"choice" => "take_live"}), do: {:ok, :take_live}
  def rebase_choice(_body), do: {:error, %{choice: "must be keep_mine or take_live"}}

  @spec revision_number(term()) :: {:ok, pos_integer()} | {:error, map()}
  def revision_number(value) do
    case Integer.parse(to_string(value || "")) do
      {n, ""} when n > 0 -> {:ok, n}
      _other -> {:error, %{revision: "must be a positive integer"}}
    end
  end

  @spec list_opts(map()) :: {:ok, keyword()} | {:error, map()}
  def list_opts(params) do
    with {:ok, limit} <- optional_int(params["limit"], :limit, 1..100),
         {:ok, before} <- optional_int(params["before"], :before, 1..1_000_000_000) do
      {:ok, Enum.reject([limit: limit, before: before], fn {_key, value} -> is_nil(value) end)}
    end
  end

  defp op(op) when is_map(op) do
    Enum.reduce(op, %{}, fn {key, value}, acc ->
      case Map.fetch(@op_keys, key) do
        {:ok, atom} -> Map.put(acc, atom, value)
        :error -> acc
      end
    end)
  end

  defp op(_op), do: %{}

  defp decision("approve"), do: {:ok, :approve}
  defp decision("send_back"), do: {:ok, :send_back}
  defp decision(_other), do: {:error, %{decision: "must be approve or send_back"}}

  defp source(source) when is_map(source), do: source
  defp source(_source), do: %{}

  defp string(value) when is_binary(value), do: value
  defp string(_value), do: nil

  defp optional_int(nil, _key, _range), do: {:ok, nil}

  defp optional_int(value, key, range) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> if n in range, do: {:ok, n}, else: {:error, %{key => "is out of range"}}
      _other -> {:error, %{key => "must be an integer"}}
    end
  end
end
