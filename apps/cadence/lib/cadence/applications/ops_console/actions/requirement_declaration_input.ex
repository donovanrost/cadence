defmodule Cadence.Applications.OpsConsole.Actions.RequirementDeclarationInput do
  @moduledoc "Native declaration input admission shared by compiled and historical action adapters."
  @fields ~w(
    spacecraft_id contact_intent earliest_start latest_end success_measure
    minimum_duration_seconds preferred_duration_seconds minimum_data_volume_bytes
    contact_count minimum_separation_seconds priority allowed_providers
    excluded_providers allowed_stations excluded_stations rationale
  )
  def fields, do: @fields

  def admit(%{"contact_requirement" => form} = input)
      when map_size(input) == 1 and is_map(form) do
    cond do
      Enum.sort(Map.keys(form)) != Enum.sort(@fields) or
          not Enum.all?(
            Map.values(form),
            &(is_binary(&1) and byte_size(&1) <= 4096 and String.valid?(&1))
          ) ->
        {:error, :malformed_input}

      Enum.any?(~w(spacecraft_id rationale), &(String.trim(form[&1]) == "")) ->
        {:error, :required_fields}

      true ->
        {:ok, form}
    end
  end

  def admit(_), do: {:error, :malformed_input}

  def parse(params) do
    with {:ok, earliest_start} <- parse_datetime(params["earliest_start"]),
         {:ok, latest_end} <- parse_datetime(params["latest_end"]),
         {:ok, minimum_duration} <- optional_integer(params["minimum_duration_seconds"]),
         {:ok, preferred_duration} <- optional_integer(params["preferred_duration_seconds"]),
         {:ok, minimum_volume} <- optional_integer(params["minimum_data_volume_bytes"]),
         {:ok, contact_count} <- positive_integer(params["contact_count"], 1),
         {:ok, separation} <- nonnegative_integer(params["minimum_separation_seconds"], 0) do
      {:ok,
       %{
         spacecraft_id: params["spacecraft_id"],
         service_direction: :downlink,
         contact_intent: params["contact_intent"],
         earliest_start: earliest_start,
         latest_end: latest_end,
         success_measure: params["success_measure"],
         minimum_duration_seconds: minimum_duration,
         preferred_duration_seconds: preferred_duration,
         minimum_data_volume_bytes: minimum_volume,
         contact_count: contact_count,
         minimum_separation_seconds: separation,
         priority: params["priority"],
         provider_constraints_document: %{
           "allowed" => refs(params["allowed_providers"]),
           "excluded" => refs(params["excluded_providers"])
         },
         station_constraints_document: %{
           "allowed" => refs(params["allowed_stations"]),
           "excluded" => refs(params["excluded_stations"])
         },
         policy_constraints_document: %{},
         approval_policy_document: %{"mode" => "manual"},
         rationale: params["rationale"],
         metadata: %{"source" => "ops_contact_requirement_form"}
       }}
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    if Regex.match?(
         ~r/\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\.[0-9]{1,6})?)?Z?\z/,
         value
       ) do
      value = String.trim_trailing(value, "Z")
      value = if byte_size(value) == 16, do: value <> ":00", else: value

      case NaiveDateTime.from_iso8601(value) do
        {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
        _ -> {:error, :invalid_datetime}
      end
    else
      {:error, :invalid_datetime}
    end
  end

  defp parse_datetime(_), do: {:error, :invalid_datetime}

  defp optional_integer(value) when value in [""], do: {:ok, nil}
  defp optional_integer(value), do: positive_integer(value, nil)

  defp positive_integer(value, default) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      {_, ""} -> {:error, :invalid_positive_integer}
      _invalid when value == "" -> {:ok, default}
      _invalid -> {:error, :invalid_positive_integer}
    end
  end

  defp nonnegative_integer(value, default) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _invalid when value == "" -> {:ok, default}
      _invalid -> {:error, :invalid_nonnegative_integer}
    end
  end

  defp refs(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
