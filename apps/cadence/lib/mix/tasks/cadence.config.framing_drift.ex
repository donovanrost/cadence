defmodule Mix.Tasks.Cadence.Config.FramingDrift do
  @moduledoc """
  Read-only audit (DECISIONS #33): lists, per profile and transport, where a spacecraft's
  profile framing differs from the transport's ingress metadata that decode uses today.

      mix cadence.config.framing_drift --mission-id MISSION
  """

  use Mix.Task

  alias Cadence.Comms.FramingDrift
  alias Cadence.Missions

  @shortdoc "List profile framing that differs from transport ingress metadata"

  @impl true
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [mission_id: :string])

    mission_id =
      opts[:mission_id] || Mix.raise("usage: mix cadence.config.framing_drift --mission-id ID")

    Mix.Task.run("app.start")

    organization_id =
      Missions.organization_id_for_mission(mission_id) ||
        Mix.raise("mission not found: #{mission_id}")

    case FramingDrift.audit(organization_id, mission_id) do
      [] ->
        Mix.shell().info("No framing drift: every profile matches the transports feeding it.")

      items ->
        Enum.each(items, &print_item/1)
    end
  end

  defp print_item(item) do
    Mix.shell().info(
      "#{item.profile.name} vs #{item.transport.name} (#{item.spacecraft_count} spacecraft):"
    )

    Enum.each(item.differences, fn d ->
      Mix.shell().info(
        "  #{d.path}: profile #{inspect(d.profile_value)}, transport #{inspect(d.transport_value)}"
      )
    end)
  end
end
