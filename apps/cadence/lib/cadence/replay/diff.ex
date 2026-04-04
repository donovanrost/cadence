defmodule Cadence.Replay.Diff do
  @moduledoc """
  Compares replay telemetry outputs against live canonical telemetry for the same
  evidence and point identifiers.
  """

  import Ecto.Query

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.Schemas.{ReplayTelemetrySampleRow, TelemetrySampleRow}
  alias Cadence.Repo

  @type report :: %{
          replay_run_id: binary(),
          compared_count: non_neg_integer(),
          matching_count: non_neg_integer(),
          mismatches: [map()],
          missing_live: [map()],
          extra_live: [map()]
        }

  @spec diff_run(binary()) :: report()
  def diff_run(replay_run_id) when is_binary(replay_run_id) do
    replay_rows =
      ReplayTelemetrySampleRow
      |> where([sample_row], sample_row.replay_run_id == ^replay_run_id)
      |> order_by([sample_row],
        asc: sample_row.evidence_id,
        asc: sample_row.point_id,
        asc: sample_row.sample_id
      )
      |> Repo.all()

    replay_keys = Enum.map(replay_rows, &sample_key/1)
    evidence_ids = replay_rows |> Enum.map(& &1.evidence_id) |> Enum.uniq()

    live_rows =
      TelemetrySampleRow
      |> where([sample_row], sample_row.evidence_id in ^evidence_ids)
      |> order_by([sample_row],
        asc: sample_row.evidence_id,
        asc: sample_row.point_id,
        asc: sample_row.sample_id
      )
      |> Repo.all()

    replay_by_key = Map.new(replay_rows, &{sample_key(&1), &1})
    live_by_key = Map.new(live_rows, &{sample_key(&1), &1})

    {matching_count, mismatches, missing_live} =
      Enum.reduce(replay_keys, {0, [], []}, fn key, {matching_count, mismatches, missing_live} ->
        replay_row = Map.fetch!(replay_by_key, key)

        reduce_replay_row_comparison(
          key,
          replay_row,
          live_by_key,
          matching_count,
          mismatches,
          missing_live
        )
      end)

    extra_live =
      live_by_key
      |> Map.drop(replay_keys)
      |> Map.values()
      |> Enum.sort_by(&sample_key/1)
      |> Enum.map(fn live_row ->
        %{
          evidence_id: live_row.evidence_id,
          point_id: live_row.point_id,
          live_raw_value: JsonDocument.unwrap_value(live_row.raw_value)
        }
      end)

    %{
      replay_run_id: replay_run_id,
      compared_count: length(replay_rows),
      matching_count: matching_count,
      mismatches: Enum.reverse(mismatches),
      missing_live: Enum.reverse(missing_live),
      extra_live: extra_live
    }
  end

  defp reduce_replay_row_comparison(
         key,
         replay_row,
         live_by_key,
         matching_count,
         mismatches,
         missing_live
       ) do
    case Map.get(live_by_key, key) do
      nil ->
        {matching_count, mismatches, [missing_live_entry(replay_row) | missing_live]}

      live_row ->
        record_replay_row_comparison(
          replay_row,
          live_row,
          matching_count,
          mismatches,
          missing_live
        )
    end
  end

  defp record_replay_row_comparison(
         replay_row,
         live_row,
         matching_count,
         mismatches,
         missing_live
       ) do
    if equivalent_sample_rows?(replay_row, live_row) do
      {matching_count + 1, mismatches, missing_live}
    else
      {matching_count, [mismatch_entry(replay_row, live_row) | mismatches], missing_live}
    end
  end

  defp sample_key(sample_row), do: {sample_row.evidence_id, sample_row.point_id}

  defp equivalent_sample_rows?(replay_row, live_row) do
    JsonDocument.unwrap_value(replay_row.raw_value) ==
      JsonDocument.unwrap_value(live_row.raw_value) and
      JsonDocument.unwrap_value(replay_row.engineering_value) ==
        JsonDocument.unwrap_value(live_row.engineering_value) and
      replay_row.quality_state == live_row.quality_state
  end

  defp mismatch_entry(replay_row, live_row) do
    %{
      evidence_id: replay_row.evidence_id,
      point_id: replay_row.point_id,
      replay_raw_value: JsonDocument.unwrap_value(replay_row.raw_value),
      live_raw_value: JsonDocument.unwrap_value(live_row.raw_value),
      replay_engineering_value: JsonDocument.unwrap_value(replay_row.engineering_value),
      live_engineering_value: JsonDocument.unwrap_value(live_row.engineering_value),
      replay_quality_state: replay_row.quality_state,
      live_quality_state: live_row.quality_state
    }
  end

  defp missing_live_entry(replay_row) do
    %{
      evidence_id: replay_row.evidence_id,
      point_id: replay_row.point_id,
      replay_raw_value: JsonDocument.unwrap_value(replay_row.raw_value)
    }
  end
end
