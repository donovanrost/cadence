defmodule Cadence.Applications.DerivedTelemetry.ActionProvider do
  @moduledoc "Typed management action adapter for Derived Telemetry definitions."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.DerivedTelemetry.Definition
  alias Cadence.Governance

  @impl true
  def execute(
        %Scope{},
        %HostContext{placement: :mission, mission_id: mission_id},
        %ActionRequest{action_id: "save_definition", params: params}
      ) do
    with {:ok, point_id} <- required_param(params, "point_id", :point_id, "Point ID"),
         {:ok, expression} <- required_param(params, "expression", :expression, "Expression") do
      existing =
        mission_id
        |> Governance.list_derived_definitions()
        |> Enum.find(&(&1.point_id == point_id))

      definition =
        Definition.new(%{
          mission_id: mission_id,
          derived_definition_id:
            (existing && existing.derived_definition_id) || definition_id(point_id),
          point_id: point_id,
          point_name: optional_param(params, "point_name", :point_name) || point_id,
          expression: expression,
          version: (existing && existing.version + 1) || 1,
          metadata: %{"application" => "derived_telemetry"}
        })

      Governance.persist_derived_definition(definition)
    end
  end

  def execute(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :unsupported_application_action}

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

  defp definition_id(point_id) do
    digest = :crypto.hash(:sha256, point_id) |> Base.url_encode64(padding: false)
    "derived_definition:#{binary_part(digest, 0, 16)}"
  end
end
