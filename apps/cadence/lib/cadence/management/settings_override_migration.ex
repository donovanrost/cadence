defmodule Cadence.Management.SettingsOverrideMigration do
  @moduledoc """
  Per-field settings overrides (BACKLOG §4, director 11-13). Mission overrides used to be full
  copies of their section. This keeps only the fields that differ from the organization's value
  at the moment of the run; the rest follow the organization again. Governance (approval) fields
  always stay set for the mission, even where they equal the organization's.

  - `dry_run/0` writes nothing: it returns `%{plan, report}`, the report one block per mission for
    qa and the director to read before the real run.
  - `run/1` (given the plan they read) writes one revision per section it changes, marked
    `"migration"`, and skips a section that moved since the plan. The audit shows one entry per
    mission (`Cadence.Reads.OrganizationAudit`).

  A section whose fields are all kept isn't written, so its settings token is unchanged. That's
  always true of Governance, so pending activation approvals stay valid.
  """

  alias Cadence.Governance.ActivationPolicy

  alias Cadence.Management.{
    ConfigurationSettingsSection,
    PassReviewSettingsSection
  }

  alias Cadence.Management.Commanding.WorkspaceSettings
  alias Cadence.Missions
  alias Cadence.Platform.ScopedSettings

  @migration "per_field_v1"
  @actor %{id: "system:settings-migration", name: "Cadence"}
  @governance ["cadence.governance"]
  @providers %{
    "cadence.governance" => {ActivationPolicy, "Governance"},
    "commanding.defaults" => {WorkspaceSettings, "Commanding"},
    "cadence.pass_review" => {PassReviewSettingsSection, "Pass review"},
    "cadence.configuration" => {ConfigurationSettingsSection, "Configuration"}
  }

  @doc "The plan and its report; nothing is written."
  def dry_run do
    plan = plan()
    %{plan: plan, report: report(plan)}
  end

  @doc """
  Per mission with an override: `%{organization_id, mission_id, mission_name, governance_kept?,
  sections: [section]}`, where a section is `%{section_id, title, version, status, kept,
  inheriting, governance_kept, value}`. `status` is `:rewrite` (some fields inherit again),
  `:unchanged` (every field is kept) or `:skipped` (a section this migration doesn't know).
  """
  def plan do
    ScopedSettings.mission_overrides()
    |> Enum.map(&section_plan/1)
    |> Enum.group_by(&{&1.organization_id, &1.mission_id})
    |> Enum.map(fn {{organization_id, mission_id}, sections} ->
      %{
        organization_id: organization_id,
        mission_id: mission_id,
        mission_name: mission_name(organization_id, mission_id),
        governance_kept?: Enum.any?(sections, &(&1.governance_kept != [])),
        sections: Enum.sort_by(sections, & &1.section_id)
      }
    end)
    |> Enum.sort_by(&{&1.organization_id, &1.mission_id})
  end

  @doc """
  Writes the plan's rewrites. Returns per mission `%{mission_id, written: [section_id], stale:
  [section_id]}`; a stale section moved since the plan and was left alone (plan again).
  """
  def run(plan) when is_list(plan) do
    Enum.map(plan, fn mission ->
      results =
        for section <- mission.sections, section.status == :rewrite do
          {section.section_id, write(mission, section)}
        end

      %{
        organization_id: mission.organization_id,
        mission_id: mission.mission_id,
        written: for({id, :ok} <- results, do: id),
        stale: for({id, {:error, _reason}} <- results, do: id)
      }
    end)
  end

  defp write(mission, section) do
    document = %{
      "value" => if(section.kept == [], do: nil, else: Map.take(section.value, section.kept)),
      "migration" => %{"id" => @migration, "governance_kept" => mission.governance_kept?}
    }

    case ScopedSettings.rewrite_override(
           mission.organization_id,
           mission.mission_id,
           section.section_id,
           section.version,
           document,
           @actor
         ) do
      {:ok, _revision} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp section_plan(%{section_id: section_id} = override) do
    base = Map.take(override, [:organization_id, :mission_id, :section_id, :version, :value])

    case Map.fetch(@providers, section_id) do
      {:ok, {provider, title}} ->
        organization =
          provider.settings_snapshot(override.organization_id, override.mission_id)
          |> Map.get(:organization_default)

        base |> Map.put(:title, title) |> Map.merge(split(override, organization || %{}))

      :error ->
        Map.merge(base, %{
          title: section_id,
          status: :skipped,
          kept: [],
          inheriting: [],
          governance_kept: [],
          organization: %{}
        })
    end
  end

  # Fields equal to the organization's inherit again, except governance ones (kept explicitly).
  defp split(%{section_id: section_id, value: value}, organization) do
    {same, different} =
      value
      |> Map.keys()
      |> Enum.sort()
      |> Enum.split_with(&(Map.has_key?(organization, &1) and organization[&1] == value[&1]))

    {kept, inheriting, governance_kept} =
      if section_id in @governance,
        do: {Enum.sort(different ++ same), [], same},
        else: {different, same, []}

    %{
      status: if(inheriting == [], do: :unchanged, else: :rewrite),
      kept: kept,
      inheriting: inheriting,
      governance_kept: governance_kept,
      organization: organization
    }
  end

  defp mission_name(organization_id, mission_id) do
    case Missions.fetch_mission(organization_id, mission_id) do
      {:ok, mission} -> mission.display_name
      _missing -> nil
    end
  end

  # -- report ----------------------------------------------------------------------------------

  @doc "The plan as text, one block per mission."
  def report(plan) do
    rewrites = Enum.count(plan, &rewrites?/1)

    header =
      "Per-field settings overrides: dry run, #{length(plan)} mission(s) with an override, " <>
        "#{rewrites} to rewrite."

    Enum.join([header | Enum.map(plan, &mission_block/1)], "\n\n") <> "\n"
  end

  defp rewrites?(mission), do: Enum.any?(mission.sections, &(&1.status == :rewrite))

  defp mission_block(mission) do
    audit =
      if rewrites?(mission),
        do: ~s(Audit entry: "#{ScopedSettings.migration_note(mission.governance_kept?)}"),
        else: "No change: nothing is written and no audit entry is made."

    lines =
      [
        "#{mission.mission_name || "(unnamed)"} (#{mission.mission_id}, org #{mission.organization_id})"
      ] ++
        Enum.flat_map(mission.sections, &section_lines/1) ++ ["  " <> audit]

    Enum.join(lines, "\n")
  end

  defp section_lines(%{status: :skipped} = section),
    do: [
      "  #{section.section_id} v#{section.version}: skipped (not a settings section this run knows)"
    ]

  defp section_lines(section) do
    status =
      if section.status == :rewrite,
        do: "rewritten as v#{section.version + 1}",
        else: "unchanged"

    ["  #{section.title} v#{section.version}: #{status}"] ++
      field_lines(section, section.kept -- section.governance_kept, "kept (differs)") ++
      field_lines(
        section,
        section.governance_kept,
        "kept explicitly (governance, equals the org)"
      ) ++
      field_lines(section, section.inheriting, "now inheriting (equals the org)")
  end

  defp field_lines(section, paths, label) do
    for path <- paths do
      "    #{label}: #{path} = #{show(section.value[path])}" <>
        " (organization: #{show(section.organization[path])})"
    end
  end

  defp show(value), do: Jason.encode!(value)
end
