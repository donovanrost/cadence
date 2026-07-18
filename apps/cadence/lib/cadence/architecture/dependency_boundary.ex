defmodule Cadence.Architecture.DependencyBoundary do
  @moduledoc """
  Ratchets transitional root-facade and persistence-schema dependencies.

  The checked-in baseline is debt, not permission for new code. A change fails
  when it adds an unlisted dependency, leaves a resolved dependency in the
  baseline, or lets the baseline review date expire.
  """

  @root_facade "lib/cadence.ex"
  @schema_prefix "lib/cadence/persistence/schemas/"
  @persistence_context ["lib/cadence/persistence.ex", "lib/cadence/persistence/"]

  @type finding :: %{
          required(:kind) => :root_facade | :persistence_schema,
          required(:source) => String.t(),
          required(:sink) => String.t(),
          required(:label) => String.t(),
          required(:fingerprint) => String.t()
        }

  @type baseline :: %{
          required(:owner) => String.t(),
          required(:review_by) => Date.t(),
          required(:rationale) => String.t(),
          required(:allowed) => MapSet.t(String.t())
        }

  @spec findings(map()) :: [finding()]
  def findings(graph) when is_map(graph) do
    graph
    |> Enum.flat_map(fn {source, sinks} ->
      Enum.flat_map(sinks, &edge_finding(source, &1))
    end)
    |> Enum.sort_by(& &1.fingerprint)
  end

  @spec read_baseline!(String.t()) :: baseline()
  def read_baseline!(path) do
    lines = path |> File.read!() |> String.split("\n")

    %{
      owner: required_metadata!(lines, "owner"),
      review_by: required_date_metadata!(lines, "review-by"),
      rationale: required_metadata!(lines, "rationale"),
      allowed:
        lines
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
        |> MapSet.new()
    }
  end

  @spec compare([finding()], baseline(), Date.t()) :: map()
  def compare(findings, baseline, today \\ Date.utc_today()) do
    current = MapSet.new(findings, & &1.fingerprint)

    %{
      current: current,
      new: Enum.reject(findings, &MapSet.member?(baseline.allowed, &1.fingerprint)),
      resolved: MapSet.difference(baseline.allowed, current) |> Enum.sort(),
      expired?: Date.after?(today, baseline.review_by),
      owner: baseline.owner,
      review_by: baseline.review_by,
      rationale: baseline.rationale
    }
  end

  @spec format_finding(finding()) :: String.t()
  def format_finding(finding) do
    "#{finding.kind}: #{finding.source} -> #{finding.sink} (#{finding.label})"
  end

  defp edge_finding(source, {sink, label}) do
    cond do
      internal_cadence_source?(source) and sink == @root_facade ->
        [finding(:root_facade, source, sink, label)]

      not persistence_context?(source) and String.starts_with?(sink, @schema_prefix) ->
        [finding(:persistence_schema, source, sink, label)]

      true ->
        []
    end
  end

  defp finding(kind, source, sink, label) do
    %{
      kind: kind,
      source: source,
      sink: sink,
      label: to_string(label),
      fingerprint: Enum.join([kind, source, sink], "|")
    }
  end

  defp internal_cadence_source?(source) do
    source != @root_facade and String.starts_with?(source, "lib/cadence/")
  end

  defp persistence_context?(source) do
    Enum.any?(@persistence_context, fn path ->
      source == path or String.starts_with?(source, path)
    end)
  end

  defp required_metadata!(lines, key) do
    prefix = "# #{key}:"

    case Enum.find(lines, &String.starts_with?(&1, prefix)) do
      nil ->
        raise ArgumentError, "dependency baseline is missing #{key} metadata"

      line ->
        line
        |> String.replace_prefix(prefix, "")
        |> String.trim()
        |> ensure_metadata_value!(key)
    end
  end

  defp ensure_metadata_value!("", key) do
    raise ArgumentError, "dependency baseline has empty #{key} metadata"
  end

  defp ensure_metadata_value!(value, _key), do: value

  defp required_date_metadata!(lines, key) do
    value = required_metadata!(lines, key)

    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> raise ArgumentError, "dependency baseline has invalid #{key} metadata"
    end
  end
end
