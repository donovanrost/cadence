defmodule Cadence.Reads.Spacecraft.Presentation do
  @moduledoc false

  def mission_path(mission), do: "/missions/#{trusted_url(mission.mission_id)}"
  def spacecraft_path(mission, nil), do: "#{mission_path(mission)}/spacecraft"
  def spacecraft_path(mission, id), do: "#{mission_path(mission)}/spacecraft/#{trusted_url(id)}"

  def breadcrumb(label, href), do: %{"label" => label, "href" => href}

  def humanize(value),
    do:
      value
      |> to_string()
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  defp trusted_url(value), do: to_string(value)
end
