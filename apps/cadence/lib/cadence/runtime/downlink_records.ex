defmodule Cadence.Runtime.DownlinkRecords do
  @moduledoc "Data-plane persistence boundary for combined downlink records and diagnostics."

  import Ecto.Query

  alias Cadence.Contacts.{CombinedDownlinkRecord, DownlinkDiagnostic}
  alias Cadence.Repo

  alias Cadence.Runtime.DownlinkRecords.{
    CombinedDownlinkRecordRow,
    DownlinkDiagnosticRow
  }

  alias Ecto.Multi

  @spec add_combined_record_inserts(Multi.t(), [CombinedDownlinkRecord.t()]) :: Multi.t()
  def add_combined_record_inserts(%Multi{} = multi, records) when is_list(records) do
    Enum.reduce(records, multi, fn %CombinedDownlinkRecord{} = record, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:combined_downlink_record, record.merged_record_id},
        CombinedDownlinkRecordRow.changeset(record)
      )
    end)
  end

  @spec add_diagnostic_inserts(Multi.t(), [DownlinkDiagnostic.t()]) :: Multi.t()
  def add_diagnostic_inserts(%Multi{} = multi, diagnostics) when is_list(diagnostics) do
    Enum.reduce(diagnostics, multi, fn %DownlinkDiagnostic{} = diagnostic, %Multi{} = acc ->
      Multi.insert(
        acc,
        {:downlink_diagnostic, diagnostic.diagnostic_id},
        DownlinkDiagnosticRow.changeset(diagnostic)
      )
    end)
  end

  @spec list_combined(binary()) :: [CombinedDownlinkRecord.t()]
  def list_combined(mission_id) when is_binary(mission_id) do
    CombinedDownlinkRecordRow
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.all()
    |> Enum.map(&CombinedDownlinkRecordRow.to_domain/1)
  end

  @spec list_diagnostics(binary()) :: [DownlinkDiagnostic.t()]
  def list_diagnostics(mission_id) when is_binary(mission_id) do
    DownlinkDiagnosticRow
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.all()
    |> Enum.map(&DownlinkDiagnosticRow.to_domain/1)
  end
end
