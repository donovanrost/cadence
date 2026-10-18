defmodule Cadence.Reads.CommandHistory.Projection do
  @moduledoc false
  alias Cadence.Reads.CommandHistory

  @times ~w(attempted_at released_at matched_at timeout_at generation_time receipt_time requested_at recorded_at)
  @identities ~w(id command_id target model_revision_id request_id queue_entry_id contact_id path_id binding_id release_attempt_id matched_record_id organization_id mission_id point_id packet_id evidence_id spacecraft_id family_key action_kind event_kind)

  def model(%{"valid" => true} = data, org, mission, request, query, observed) do
    request_row = record!(data["request"])
    true = request_row["id"] == request
    releases = ledger(data["release_rows"])
    verifiers = ledger(data["verifier_rows"])
    release = optional_record(data["release"])
    verifier = optional_record(data["verifier"])
    evidence = evidence(data["evidence"])

    model = %{
      "version" => 1,
      "organization_id" => org,
      "mission_id" => mission,
      "observed_at" => DateTime.to_iso8601(observed),
      "request" => request_row,
      "query" => query,
      "releases" => releases,
      "verifiers" => verifiers,
      "selection" => %{"release" => release, "verifier" => verifier},
      "evidence" => evidence
    }

    true = byte_size(Jason.encode!(model)) <= 524_288
    model
  end

  defp ledger(rows) when is_list(rows) and length(rows) <= 26 do
    entries = rows |> Enum.take(25) |> Enum.map(&record!/1)

    %{
      "entries" => entries,
      "limit" => 25,
      "next_after" => if(length(rows) > 25, do: List.last(entries)["id"])
    }
  end

  defp optional_record(nil), do: nil
  defp optional_record(value), do: record!(value)

  defp evidence(%{"status" => "ready", "record" => record}) do
    %{"status" => "ready", "record" => record!(record)}
  rescue
    _ -> %{"status" => "unavailable", "record" => nil}
  end

  defp evidence(%{"status" => status, "record" => nil})
       when status in ~w(not_selected unmatched unavailable),
       do: %{"status" => status, "record" => nil}

  defp record!(record) when is_map(record) do
    Map.new(record, fn {key, value} -> {key, field!(key, value)} end)
  end

  defp field!(key, nil) when key in @times or key in @identities or key == "target_name", do: nil

  defp field!(key, value) when key in @times do
    {:ok, naive} = NaiveDateTime.from_iso8601(value)
    {microseconds, _} = naive.microsecond

    naive
    |> Map.put(:microsecond, {microseconds, 6})
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp field!(key, value) when key in @identities do
    true = CommandHistory.identity?(value)
    value
  end

  defp field!(key, value) when key in ~w(raw_value_json engineering_value_json) do
    true = is_binary(value) and byte_size(value) <= 65_536
    {:ok, _} = Jason.decode(value)
    value
  end

  defp field!(key, value) when key in ~w(name point_name target_name) do
    true = is_binary(value) and String.valid?(value) and byte_size(value) in 1..512
    value
  end

  defp field!("quality_state", value) when value in ~w(good suspect bad), do: value
  defp field!("quality_state", _), do: raise(ArgumentError, "invalid sample quality")

  defp field!("signal_phase", value)
       when value in [nil, "acceptance", "start", "completion", "custom"], do: value

  defp field!("signal_phase", _), do: raise(ArgumentError, "invalid transport phase")

  defp field!("encoded_size_bytes", nil), do: nil

  defp field!("encoded_size_bytes", value)
       when is_integer(value) and value >= 0 and value <= 9_007_199_254_740_991, do: value

  defp field!("encoded_size_bytes", _), do: raise(ArgumentError, "invalid encoded size")
  defp field!(_, value), do: value
end
