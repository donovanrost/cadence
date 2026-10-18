defmodule CadenceWeb.ApplicationActionInput do
  @moduledoc "Host JSON admission with explicit bounded domain fields."
  alias Cadence.Applications.JSONBoundary

  @spec safe(term()) :: {:ok, term()} | {:error, term()}
  def safe(params) do
    case normalize(params) do
      {:ok, _} = result -> result
      {:error, _} -> {:error, :application_surface_bounds_exceeded}
    end
  end

  defp normalize(
         %{
           "applicationKey" => "ops_console",
           "applicationVersion" => 1,
           "surfaceId" => "contact_schedule",
           "surfaceVersion" => 1
         } = params
       ) do
    case JSONBoundary.safe(params) do
      {:ok, _} = safe -> safe
      _ -> if reserve?(params), do: capability_input(params), else: JSONBoundary.safe(params)
    end
  end

  defp normalize(
         %{
           "applicationKey" => "derived_telemetry",
           "applicationVersion" => 1,
           "surfaceId" => "manage",
           "surfaceVersion" => 1
         } = params
       ) do
    case JSONBoundary.safe(params) do
      {:ok, _} = bounded ->
        bounded

      {:error, _} = error ->
        if save_definition?(params), do: definition_input(params), else: error
    end
  end

  defp normalize(params), do: JSONBoundary.safe(params)

  defp save_definition?(%{"actionId" => "save_definition"} = params),
    do: Map.get(params, "actionVersion", 1) == 1 and Map.get(params, "version", 1) == 1

  defp save_definition?(%{"operation" => "save_definition", "operationVersion" => 1}), do: true
  defp save_definition?(_), do: false

  defp definition_input(params) do
    fields = Map.take(params, ~w(input params))

    with [input] <- fields |> Map.values() |> Enum.uniq(),
         true <- is_map(input),
         true <-
           Enum.all?(
             Map.keys(input),
             &(&1 in ~w(point_id point_name expression expected_definition_id expected_version))
           ),
         expression when is_binary(expression) and byte_size(expression) in 1..8192 <-
           input["expression"],
         true <- String.valid?(expression),
         {:ok, rest} <- JSONBoundary.safe(Map.delete(input, "expression")),
         {:ok, envelope} <- JSONBoundary.safe(Map.drop(params, Map.keys(fields))) do
      input = Map.put(rest, "expression", expression)
      result = Map.merge(envelope, Map.new(fields, fn {key, _} -> {key, input} end))

      if byte_size(Jason.encode!(result)) <= 65_536,
        do: {:ok, result},
        else: {:error, :document_bytes}
    else
      _ -> {:error, :application_surface_bounds_exceeded}
    end
  end

  defp reserve?(%{"actionId" => action}), do: action == "reserve"
  defp reserve?(%{"operation" => "reserve", "operationVersion" => 1}), do: true
  defp reserve?(_), do: false

  defp capability_input(params) do
    with {:ok, fields} <- capability_fields(params),
         {:ok, normalized} <- JSONBoundary.safe(Map.drop(params, Map.keys(fields))),
         result = Map.merge(normalized, fields),
         {:ok, encoded} <- Jason.encode(result),
         true <- byte_size(encoded) <= 65_536 do
      {:ok, result}
    else
      _ -> {:error, :application_surface_bounds_exceeded}
    end
  end

  defp capability_fields(params) do
    fields = Map.take(params, ~w(input params))

    with [input] <- fields |> Map.values() |> Enum.uniq(),
         :ok <- capability_value(input),
         do: {:ok, fields},
         else: (_ -> {:error, :invalid_application_request})
  end

  defp capability_value(%{"token" => token} = input)
       when map_size(input) == 1 and is_binary(token) and byte_size(token) in 1..8192 do
    if String.valid?(token), do: :ok, else: {:error, :string}
  end

  defp capability_value(
         %{"contract_version" => 2, "operation_id" => id, "payload" => %{"token" => _} = payload} =
           input
       )
       when map_size(input) == 3 do
    with {:ok, ^id} <- Ecto.UUID.cast(id), do: capability_value(payload)
  end

  defp capability_value(_), do: {:error, :invalid_application_request}
end
