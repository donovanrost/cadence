defmodule Cadence.Applications.Limits.ActionProvider do
  @moduledoc "Typed management action adapter for governed limit definitions."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Limits
  alias Cadence.Limits.Definition
  alias Cadence.Missions

  @impl true
  def application_key, do: "limits"

  @threshold_fields [
    {"red_low", :red_low},
    {"yellow_low", :yellow_low},
    {"yellow_high", :yellow_high},
    {"red_high", :red_high}
  ]

  @impl true
  def execute(
        %Scope{} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %ActionRequest{
          application_key: "limits",
          application_version: 1,
          surface_id: "manage",
          surface_version: 1,
          action_id: "save_limit_definition",
          params: params
        }
      ) do
    with {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission_id),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, point_id} <- required_param(params, "point_id", :point_id, "Canonical point ID"),
         {:ok, limit_set_name} <- limit_set_name(params),
         :ok <- bounded_identity(point_id, limit_set_name),
         {:ok, thresholds} <- thresholds(params),
         :ok <- validate_threshold_order(thresholds),
         {:ok, reviewed} <- review(params) do
      Limits.append_limit_definition(
        scope.organization_id,
        mission_id,
        %{
          point_id: point_id,
          limit_set_name: limit_set_name,
          thresholds: thresholds,
          metadata: %{"application" => "limits"}
        },
        reviewed
      )
    end
    |> action_result()
  end

  def execute(_, _, _), do: {:error, :unsupported_application_action}

  defp action_result({:error, :limit_definition_review_conflict}),
    do:
      failure(
        "review_conflict",
        "This definition or its active version changed. Refresh and review it before saving."
      )

  defp action_result({:error, :limit_definition_version_conflict}),
    do:
      failure(
        "review_conflict",
        "This immutable version already exists with different contents. Refresh before saving."
      )

  defp action_result({:error, :limit_definition_review_required}),
    do: failure("review_required", "Review the current point and limit set before saving.")

  defp action_result({:error, %Ecto.Changeset{}}),
    do:
      failure(
        "invalid_definition",
        "The limit definition could not be saved and activated. Check the retained draft."
      )

  defp action_result(result), do: result

  defp review(%{
         "expected_definition_id" => nil,
         "expected_version" => 0,
         "expected_activation_event_id" => nil
       }),
       do: {:ok, %{definition_id: nil, version: 0, activation_event_id: nil}}

  defp review(%{
         "expected_definition_id" => id,
         "expected_version" => version,
         "expected_activation_event_id" => event
       })
       when is_binary(id) and byte_size(id) in 1..240 and is_integer(version) and
              version in 1..9_007_199_254_740_991 and
              (is_nil(event) or (is_binary(event) and byte_size(event) in 1..240)),
       do: {:ok, %{definition_id: id, version: version, activation_event_id: event}}

  defp review(_), do: {:error, :limit_definition_review_required}

  defp bounded_identity(point, set) do
    cond do
      byte_size(point) > 240 ->
        failure("invalid_field", "Canonical point ID is too long.", "point_id")

      byte_size(set) > 240 ->
        failure("invalid_field", "Limit set name is too long.", "limit_set_name")

      true ->
        :ok
    end
  end

  defp failure(code, message, field \\ nil),
    do: {:error, %ActionFailure{code: code, message: message, field: field}}

  @impl true
  def result(%Definition{} = definition) do
    %{
      "definitionId" => definition.limit_definition_id,
      "pointId" => definition.point_id,
      "limitSetName" => definition.limit_set_name,
      "thresholds" => definition.thresholds,
      "version" => definition.version
    }
  end

  def result(value) when is_map(value), do: value
  def result(_value), do: nil

  defp thresholds(params) do
    Enum.reduce_while(
      @threshold_fields,
      {:ok, %{}},
      &put_threshold(params, &1, &2)
    )
    |> require_threshold()
  end

  defp put_threshold(params, {key, atom_key}, {:ok, acc}) do
    value = Map.get(params, key, Map.get(params, atom_key))
    value = if is_binary(value), do: String.trim(value), else: value
    parsed_threshold(if(value == "", do: nil, else: value), key, acc)
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

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} when abs(number) <= 9_007_199_254_740_991 -> {:ok, number}
      _other -> :error
    end
  end

  defp parse_number(_), do: :error

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

  defp limit_set_name(params) do
    case Map.get(params, "limit_set_name", Map.get(params, :limit_set_name)) do
      value when is_nil(value) or is_binary(value) ->
        {:ok, optional_param(params, "limit_set_name", :limit_set_name) || "DEFAULT"}

      _ ->
        failure("invalid_field", "Limit set must be a name.", "limit_set_name")
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

  defp humanize_field(field) do
    String.replace(field, "_", " ")
  end
end
