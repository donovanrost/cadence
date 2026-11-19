defmodule Cadence.ContactPlanning.TemplateDescriptions do
  @moduledoc """
  Server-made sentences for a contact requirement template version (console
  CP1/CP3), so the console never re-derives them: what it targets
  (`applies_to/2`) and what it asks for (`rule_summary/1`). Pure.
  """

  alias Cadence.ContactPlanning.ContactRequirementTemplateVersion

  @doc """
  The target in words. `names` maps profile ids and spacecraft ids to display
  names (missing ones fall back to the id).
  """
  @spec applies_to(map(), map()) :: binary()
  def applies_to(target, names \\ %{}) do
    base =
      case target do
        %{"kind" => "profile", "spacecraft_type_id" => id} -> "profile #{name(names, id)}"
        %{"kind" => "plane", "plane" => plane} -> "plane #{plane}"
        %{"kind" => "spacecraft_ids", "spacecraft_ids" => [id]} -> name(names, id)
        %{"kind" => "spacecraft_ids", "spacecraft_ids" => ids} -> "#{length(ids)} spacecraft"
      end

    case Map.get(target, "exclude_spacecraft_ids", []) do
      [] -> base
      excluded -> "#{base}, except #{length(excluded)}"
    end
  end

  @doc ~S|"1 downlink ≥ 5 min every 6h00" style: count, direction, duration, cadence.|
  @spec rule_summary(ContactRequirementTemplateVersion.t()) :: binary()
  def rule_summary(%ContactRequirementTemplateVersion{} = version) do
    [requirement_summary(version.requirement_document), cadence(version.schedule_document)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc ~S|"2 downlinks ≥ 5 min each": what one requirement asks for (string-keyed content).|
  @spec requirement_summary(map()) :: binary()
  def requirement_summary(requirement) do
    count = requirement["contact_count"] || 1
    direction = direction(requirement["service_direction"], count)

    measure =
      case requirement do
        %{"success_measure" => "minimum_data_volume", "minimum_data_volume_bytes" => bytes}
        when is_integer(bytes) ->
          "≥ #{bytes(bytes)} each"

        %{"minimum_duration_seconds" => seconds} when is_integer(seconds) ->
          "≥ #{duration(seconds)} each"

        _other ->
          nil
      end

    ["#{count} #{direction}", measure] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  defp cadence(%{"type" => "fixed_interval", "interval_seconds" => seconds}),
    do: "every #{duration(seconds)}"

  defp cadence(%{"type" => "daily", "time_utc" => time}), do: "daily at #{time} UTC"
  defp cadence(_schedule), do: nil

  defp direction("uplink", 1), do: "uplink"
  defp direction("uplink", _count), do: "uplinks"
  defp direction("bidirectional", 1), do: "two-way contact"
  defp direction("bidirectional", _count), do: "two-way contacts"
  defp direction(_downlink, 1), do: "downlink"
  defp direction(_downlink, _count), do: "downlinks"

  @doc "Seconds as `45 s`, `5 min`, `6h00`, `2 d`."
  @spec duration(integer()) :: binary()
  def duration(seconds) when seconds < 60, do: "#{seconds} s"

  def duration(seconds) when seconds < 3_600 and rem(seconds, 60) == 0,
    do: "#{div(seconds, 60)} min"

  def duration(seconds) when seconds < 3_600, do: "#{div(seconds, 60)} min #{rem(seconds, 60)} s"

  def duration(seconds) when rem(seconds, 86_400) == 0 and seconds >= 86_400,
    do: "#{div(seconds, 86_400)} d"

  def duration(seconds) do
    minutes =
      seconds |> rem(3_600) |> div(60) |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{div(seconds, 3_600)}h#{minutes}"
  end

  defp bytes(n) when n >= 1_000_000_000, do: "#{Float.round(n / 1_000_000_000, 1)} GB"
  defp bytes(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)} MB"
  defp bytes(n), do: "#{n} B"

  defp name(names, id), do: Map.get(names, id) || id
end
