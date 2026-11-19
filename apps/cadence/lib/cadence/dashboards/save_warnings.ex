defmodule Cadence.Dashboards.SaveWarnings do
  @moduledoc """
  What a dashboard save went through despite (lead 11-14, dashboards' save sheet): sources a read
  reported unavailable or degraded. These no longer block a save (`PublishReadiness`); the sheet
  says the widgets may stay empty until the source answers.

  One entry per (code, logical source, realm), so one slow source behind ten widgets is one
  warning: `%{code, logical_source, realm, reasons, observed_at, placement_ids, message}`.
  `observed_at` is the latest health time seen (nil without a health row).
  """

  alias Cadence.Dashboards
  alias Cadence.Dashboards.Document

  @codes [:source_unavailable, :source_degraded]

  @spec for_document(Document.t()) :: [map()]
  def for_document(%Document{organization_id: org, mission_id: mission} = document)
      when is_binary(org) and is_binary(mission) do
    org
    |> Dashboards.validate_publish_readiness(mission, document)
    |> Map.get(:warnings, [])
    |> group()
  rescue
    # The save already happened; a failed re-check must not turn it into an error.
    _exception -> []
  end

  def for_document(_document), do: []

  @doc false
  @spec group([map()]) :: [map()]
  def group(warnings) do
    warnings
    |> Enum.filter(&(&1.code in @codes))
    |> Enum.group_by(fn %{code: code, details: d} -> {code, d[:logical_source], d[:realm]} end)
    |> Enum.map(fn {{code, logical_source, realm}, members} ->
      details = Enum.map(members, & &1.details)

      %{
        code: code,
        logical_source: logical_source,
        realm: realm,
        reasons: details |> Enum.flat_map(&(&1[:reasons] || [])) |> Enum.uniq() |> Enum.sort(),
        observed_at: details |> Enum.map(& &1[:observed_at]) |> latest(),
        placement_ids: details |> Enum.flat_map(&placement_ids/1) |> Enum.uniq() |> Enum.sort(),
        message: details |> Enum.map(& &1[:source_warning_message]) |> Enum.find(&is_binary/1)
      }
    end)
    |> Enum.sort_by(&{to_string(&1.code), to_string(&1.logical_source), to_string(&1.realm)})
  end

  defp placement_ids(details),
    do: List.wrap(details[:placement_id]) ++ (get_in(details, [:details, :placement_ids]) || [])

  defp latest(times) do
    case Enum.filter(times, &match?(%DateTime{}, &1)) do
      [] -> nil
      seen -> Enum.max(seen, DateTime)
    end
  end
end
