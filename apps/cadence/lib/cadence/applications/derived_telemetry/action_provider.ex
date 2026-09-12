defmodule Cadence.Applications.DerivedTelemetry.ActionProvider do
  @moduledoc "Reviewed management actions for immutable Derived Telemetry definitions."
  @behaviour Cadence.Applications.ActionProvider
  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.DerivedTelemetry.Definition
  alias Cadence.Governance
  alias Cadence.Missions

  @impl true
  def application_key, do: "derived_telemetry"

  @impl true
  def execute(
        %Scope{} = scope,
        %HostContext{placement: :mission, mission_id: mission} = host,
        %ActionRequest{
          application_key: "derived_telemetry",
          application_version: 1,
          surface_id: "manage",
          surface_version: 1,
          action_id: "save_definition",
          params: params
        }
      ) do
    with {:ok, _} <- Missions.fetch_mission(scope.organization_id, mission),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: host.mission_id
           }),
         {:ok, point} <- required(params, "point_id", 240, "Point ID"),
         {:ok, expression} <- required(params, "expression", 8192, "Expression"),
         {:ok, name} <- name(params, point),
         {:ok, version, id} <- review(params),
         {:ok, definition} <-
           Governance.append_derived_definition(
             scope.organization_id,
             mission,
             %{
               point_id: point,
               point_name: name,
               expression: expression,
               expected_definition_id: id,
               metadata: %{"application" => "derived_telemetry"}
             },
             version
           ) do
      {:ok, definition}
    else
      {:error, :derived_definition_version_conflict} ->
        failure(
          "review_conflict",
          "This definition changed. Refresh and review its current version before saving."
        )

      {:error, :derived_definition_review_required} ->
        failure("review_required", "Review the current definition before saving.")

      {:error, %ActionFailure{}} = error ->
        error

      {:error, reason} when reason in [:forbidden, :not_found] ->
        {:error, reason}

      {:error, _reason} ->
        failure(
          "invalid_expression",
          "The expression could not be saved. Use a valid stateless expression with canonical point IDs.",
          "expression"
        )
    end
  end

  def execute(_, _, _), do: {:error, :unsupported_application_action}

  @impl true
  def result(%Definition{} = d),
    do: %{
      "definitionId" => d.derived_definition_id,
      "pointId" => d.point_id,
      "pointName" => d.point_name,
      "expression" => d.expression,
      "version" => d.version,
      "sourceCount" => length(d.source_point_ids)
    }

  def result(_), do: nil

  defp required(params, key, maximum, label) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        cond do
          trimmed == "" -> failure("required_field", "#{label} is required.", key)
          byte_size(trimmed) > maximum -> failure("invalid_field", "#{label} is too long.", key)
          true -> {:ok, trimmed}
        end

      _ ->
        failure("required_field", "#{label} is required.", key)
    end
  end

  defp name(params, point) do
    if Map.get(params, "point_name") in [nil, ""],
      do: {:ok, point},
      else: required(params, "point_name", 240, "Display name")
  end

  defp review(%{"expected_version" => 0, "expected_definition_id" => nil}), do: {:ok, 0, nil}

  defp review(%{"expected_version" => version, "expected_definition_id" => id})
       when is_integer(version) and version > 0 and is_binary(id) and byte_size(id) in 1..256,
       do: {:ok, version, id}

  defp review(_), do: {:error, :derived_definition_review_required}

  defp failure(code, message, field \\ nil),
    do: {:error, %ActionFailure{code: code, message: message, field: field}}
end
