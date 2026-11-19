defmodule Cadence.Reads.EventLog.Classify do
  @moduledoc """
  The Timeline's console vocabulary for one entry (`Cadence.Reads.EventLog`): its console `kind`
  (`limit | flight_event | contact | command | config | operator | data`), its `severity`
  (`critical | caution | nominal | info`), which raw kinds are data-plane housekeeping, and the
  severity floor (`severity_at_least`). The page, the SQL density and the raw-kind picker all
  classify with these, so the list and the bar agree.
  """

  alias Cadence.MissionEvents.Entry

  @severity_rank %{critical: 3, caution: 2, nominal: 1, info: 0}

  @doc "Severity order, most severe highest."
  @spec rank(atom()) :: non_neg_integer()
  def rank(severity), do: Map.get(@severity_rank, severity, 0)

  @doc "The page's console kind and severity for an entry (also built from a density group)."
  @spec entry(Entry.t()) :: {binary(), atom()}
  def entry(%Entry{} = entry), do: {kind(entry), severity(entry)}

  @spec kind(Entry.t()) :: binary()
  def kind(%Entry{kind: kind} = entry) when is_atom(kind) or is_binary(kind) do
    raw = to_string(kind)

    cond do
      housekeeping?(raw) -> "data"
      String.starts_with?(raw, "limit_definition_") -> "config"
      String.contains?(raw, "contact") -> "contact"
      true -> classify(entry)
    end
  end

  def kind(entry), do: classify(entry)

  # 21:08Z 500s (domain): the default Timeline excludes `data`, so its rows needn't be read.
  @doc "Whether a kinds filter leaves out housekeeping rows (they needn't be read)."
  @spec skip_housekeeping?(term()) :: boolean()
  def skip_housekeeping?([_ | _] = kinds), do: "data" not in kinds
  def skip_housekeeping?(_all), do: false

  @doc "Whether `severity` is at or above `floor` (`nil` = no floor; U69 A9a)."
  def at_least?(_severity, nil), do: true

  def at_least?(severity, floor),
    do: rank(severity) >= Map.fetch!(@severity_rank, floor)

  defp housekeeping?(raw),
    do: String.starts_with?(raw, "source_") or String.contains?(raw, "watermark")

  defp classify(%Entry{source_record_kind: :limit_event}), do: "limit"
  defp classify(%Entry{kind: :limit_violation}), do: "limit"
  defp classify(%Entry{source_record_kind: :contact_action}), do: "contact"
  defp classify(%Entry{source_record_kind: :managed_action_request}), do: "command"

  defp classify(%Entry{source_record_kind: source})
       when source in [:combined_downlink_record, :downlink_diagnostic], do: "contact"

  defp classify(%Entry{kind: :binding_set_activated}), do: "config"
  defp classify(%Entry{source_record_kind: :config_revision}), do: "config"
  defp classify(%Entry{category: :transport}), do: "contact"
  defp classify(%Entry{category: :runtime}), do: "config"
  defp classify(%Entry{category: :health}), do: "data"
  defp classify(%Entry{}), do: "operator"

  @spec severity(Entry.t()) :: atom()
  def severity(%Entry{status: status})
      when status in [:cleared, :resolved, "cleared", "resolved"],
      do: :nominal

  def severity(%Entry{kind: kind})
      when kind in [:source_health_recovered, "source_health_recovered"],
      do: :nominal

  def severity(%Entry{severity: severity}) when severity in [:critical, :error], do: :critical
  def severity(%Entry{severity: :warning}), do: :caution
  def severity(%Entry{}), do: :info
end
