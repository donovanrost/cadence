defmodule Cadence.Applications.OpsConsole.Actions.RequirementTemplateInput do
  @moduledoc "Bounded native recurring-need form admission and UTC normalization."
  @fields ~w(spacecraft_id schedule_type anchor_at time_utc interval_minutes window_offset_minutes window_duration_minutes contact_intent success_measure minimum_duration_seconds preferred_duration_seconds minimum_data_volume_bytes contact_count minimum_separation_seconds priority approval_mode maximum_occurrences_per_run maximum_lookback_hours rationale)
  def fields, do: @fields

  def admit(%{"template" => form} = input) when map_size(input) == 1 and is_map(form) do
    cond do
      Enum.sort(Map.keys(form)) != Enum.sort(@fields) or
          not Enum.all?(
            Map.values(form),
            &(is_binary(&1) and byte_size(&1) <= 4096 and String.valid?(&1))
          ) ->
        {:error, :malformed_input}

      Enum.any?(~w(spacecraft_id contact_intent rationale), &(String.trim(form[&1]) == "")) ->
        {:error, :required_fields}

      true ->
        {:ok, form}
    end
  end

  def admit(_), do: {:error, :malformed_input}

  def parse(params) do
    with {:ok, anchor} <- parse_datetime(params["anchor_at"]),
         {:ok, offset} <- integer(params["window_offset_minutes"]),
         {:ok, duration} <- positive_integer(params["window_duration_minutes"]),
         {:ok, minimum} <- optional_positive_integer(params["minimum_duration_seconds"]),
         {:ok, preferred} <- optional_positive_integer(params["preferred_duration_seconds"]),
         {:ok, volume} <- optional_positive_integer(params["minimum_data_volume_bytes"]),
         {:ok, count} <- positive_integer(params["contact_count"]),
         {:ok, separation} <- nonnegative_integer(params["minimum_separation_seconds"]),
         {:ok, maximum} <- positive_integer(params["maximum_occurrences_per_run"]),
         {:ok, lookback} <- nonnegative_integer(params["maximum_lookback_hours"]),
         {:ok, schedule} <- schedule_document(params, anchor, offset, duration) do
      {:ok,
       %{
         spacecraft_id: params["spacecraft_id"],
         schedule_document: schedule,
         requirement_document: %{
           "service_direction" => "downlink",
           "contact_intent" => params["contact_intent"],
           "success_measure" => params["success_measure"],
           "minimum_duration_seconds" => minimum,
           "preferred_duration_seconds" => preferred,
           "minimum_data_volume_bytes" => volume,
           "contact_count" => count,
           "minimum_separation_seconds" => separation,
           "priority" => params["priority"],
           "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
           "station_constraints_document" => %{"allowed" => [], "excluded" => []},
           "policy_constraints_document" => %{},
           "approval_policy_document" => %{"mode" => params["approval_mode"]},
           "rationale" => params["rationale"],
           "metadata" => %{}
         },
         catch_up_policy_document: %{
           "maximum_occurrences_per_run" => maximum,
           "maximum_lookback_seconds" => lookback * 3_600
         }
       }}
    end
  end

  defp schedule_document(params, anchor, offset, duration) do
    base = %{
      "type" => params["schedule_type"],
      "anchor_at" => DateTime.to_iso8601(anchor),
      "ends_at" => nil,
      "window_offset_seconds" => offset * 60,
      "window_duration_seconds" => duration * 60
    }

    case params["schedule_type"] do
      "fixed_interval" ->
        with {:ok, interval} <- positive_integer(params["interval_minutes"]) do
          {:ok, Map.put(base, "interval_seconds", interval * 60)}
        end

      "daily" ->
        case Time.from_iso8601(normalize_daily_time(params["time_utc"])) do
          {:ok, time} -> {:ok, Map.put(base, "time_utc", Time.to_iso8601(time))}
          _invalid -> {:error, :invalid_daily_time}
        end

      _invalid ->
        {:error, :invalid_schedule_type}
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

  defp integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _invalid -> {:error, :invalid_integer}
    end
  end

  defp optional_positive_integer(""), do: {:ok, nil}
  defp optional_positive_integer(value), do: positive_integer(value)

  defp positive_integer(value) do
    with {integer, ""} <- Integer.parse(value), true <- integer > 0 do
      {:ok, integer}
    else
      _invalid -> {:error, :invalid_positive_integer}
    end
  end

  defp nonnegative_integer(value) do
    with {integer, ""} <- Integer.parse(value), true <- integer >= 0 do
      {:ok, integer}
    else
      _invalid -> {:error, :invalid_nonnegative_integer}
    end
  end

  defp normalize_daily_time(value) when byte_size(value) == 5, do: value <> ":00"
  defp normalize_daily_time(value), do: value
end
