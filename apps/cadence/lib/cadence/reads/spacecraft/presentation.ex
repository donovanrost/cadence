defmodule Cadence.Reads.Spacecraft.Presentation do
  @moduledoc false

  def trusted_url(value), do: to_string(value)

  def mission_path(mission), do: "/missions/#{trusted_url(mission.mission_id)}"
  def spacecraft_path(mission, nil), do: "#{mission_path(mission)}/spacecraft"
  def spacecraft_path(mission, id), do: "#{mission_path(mission)}/spacecraft/#{trusted_url(id)}"
  def profiles_path(mission), do: "#{spacecraft_path(mission, nil)}/profiles"
  def profile_path(mission, id), do: "#{profiles_path(mission)}/#{trusted_url(id)}"

  def identity_path(mission, spacecraft),
    do: "#{spacecraft_path(mission, spacecraft.spacecraft_id)}/identity"

  def breadcrumb(label, href), do: %{"label" => label, "href" => href}
  def navigation_item(label, href), do: breadcrumb(label, href)

  def header(title, subtitle),
    do: %{
      "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
      "body" => %{"attrs" => %{}},
      "content" => %{"attrs" => %{}},
      "title" => %{
        "attrs" => %{"class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"},
        "text" => title
      },
      "subtitle" => %{
        "attrs" => %{"class" => "mt-1 text-sm text-base-content/70"},
        "text" => subtitle
      }
    }

  def breadcrumbs(mission, label, href),
    do: %{
      "attrs" => %{"class" => "flex items-center gap-2 text-xs text-base-content/60"},
      "items" => [
        breadcrumb(mission.display_name, mission_path(mission)),
        breadcrumb(label, href)
      ]
    }

  def application_summary(applications),
    do: applications |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &humanize/1)

  def humanize(value),
    do:
      value
      |> to_string()
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  def field(id, name, type, label, value, required),
    do: %{
      "id" => id,
      "name" => name,
      "type" => type,
      "label" => label,
      "value" => value,
      "required" => required
    }
end
