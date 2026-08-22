defmodule Cadence.Applications.Limits.ActionProvider do
  @moduledoc "Typed management action adapter for governed limit definitions."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Limits
  alias Cadence.Limits.Definition

  @threshold_fields [
    {"red_low", :red_low},
    {"yellow_low", :yellow_low},
    {"yellow_high", :yellow_high},
    {"red_high", :red_high}
  ]

  @impl true
  def execute(
        %Scope{},
        %HostContext{placement: :mission, mission_id: mission_id},
        %ActionRequest{action_id: "save_limit_definition", params: params}
      ) do
    with {:ok, point_id} <- required_param(params, "point_id", :point_id, "Canonical point ID"),
         limit_set_name <- optional_param(params, "limit_set_name", :limit_set_name) || "DEFAULT",
         {:ok, thresholds} <- thresholds(params),
         :ok <- validate_threshold_order(thresholds) do
      existing = existing_definition(mission_id, point_id, limit_set_name)

      definition =
        Definition.new(%{
          mission_id: mission_id,
          limit_definition_id:
            (existing && existing.limit_definition_id) || definition_id(point_id, limit_set_name),
          point_id: point_id,
          version: (existing && existing.version + 1) || 1,
          limit_set_name: limit_set_name,
          thresholds: thresholds,
          metadata: %{"application" => "limits"}
        })

      Limits.persist_limit_definition(definition)
    end
  end

  def execute(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :unsupported_application_action}

  defp existing_definition(mission_id, point_id, limit_set_name) do
    mission_id
    |> Limits.list_limit_definitions()
    |> Enum.find(fn definition ->
      definition.point_id == point_id and definition.limit_set_name == limit_set_name
    end)
  end

  defp thresholds(params) do
    Enum.reduce_while(
      @threshold_fields,
      {:ok, %{}},
      &put_threshold(params, &1, &2)
    )
    |> require_threshold()
  end

  defp put_threshold(params, {key, atom_key}, {:ok, acc}) do
    params
    |> optional_param(key, atom_key)
    |> parsed_threshold(key, acc)
  end

  defp parsed_threshold(nil, _key, acc), do: {:cont, {:ok, acc}}

  defp parsed_threshold(value, key, acc) do
    case parse_number(value) do
      {:ok, number} ->
        {:cont, {:ok, Map.put(acc, key, number)}}

      :error ->
        {:halt,
         {:error,
          %ActionFailure{
            code: "invalid_number",
            message: "#{key |> humanize_field() |> String.capitalize()} must be a number.",
            field: key
          }}}
    end
  end

  defp require_threshold({:ok, thresholds}) when map_size(thresholds) == 0,
    do:
      {:error,
       %ActionFailure{
         code: "threshold_required",
         message: "Configure at least one threshold."
       }}

  defp require_threshold(result), do: result

  defp validate_threshold_order(thresholds) do
    ordered_keys = ["red_low", "yellow_low", "yellow_high", "red_high"]

    thresholds
    |> then(fn configured ->
      for left <- ordered_keys,
          right <- ordered_keys,
          Enum.find_index(ordered_keys, &(&1 == left)) <
            Enum.find_index(ordered_keys, &(&1 == right)),
          Map.has_key?(configured, left),
          Map.has_key?(configured, right),
          do: {left, Map.fetch!(configured, left), right, Map.fetch!(configured, right)}
    end)
    |> Enum.find(fn {_left_key, left, _right_key, right} -> left >= right end)
    |> case do
      nil ->
        :ok

      {left_key, _left, right_key, _right} ->
        {:error,
         %ActionFailure{
           code: "invalid_threshold_order",
           message:
             "#{left_key |> humanize_field() |> String.capitalize()} must be lower than #{humanize_field(right_key)}.",
           field: right_key
         }}
    end
  end

  defp parse_number(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _other -> :error
    end
  end

  defp required_param(params, key, atom_key, label) do
    case optional_param(params, key, atom_key) do
      nil ->
        {:error,
         %ActionFailure{
           code: "required_field",
           message: "#{label} is required.",
           field: key
         }}

      value ->
        {:ok, value}
    end
  end

  defp optional_param(params, key, atom_key) do
    case Map.get(params, key, Map.get(params, atom_key)) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end

  defp definition_id(point_id, limit_set_name) do
    digest =
      :crypto.hash(:sha256, point_id <> ":" <> limit_set_name)
      |> Base.url_encode64(padding: false)

    "limit_definition:#{binary_part(digest, 0, 16)}"
  end

  defp humanize_field(field) do
    String.replace(field, "_", " ")
  end
end
