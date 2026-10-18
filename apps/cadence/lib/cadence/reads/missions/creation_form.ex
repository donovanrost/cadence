defmodule Cadence.Reads.Missions.CreationForm do
  @moduledoc "Core mission creation form presentation."
  def new do
    %{
      "page" => %{
        "id" => "mission-new-page",
        "heading" => "New Mission",
        "breadcrumbs" => [
          %{"label" => "Missions", "href" => "/missions"},
          %{"label" => "New", "href" => nil}
        ]
      },
      "form" => %{
        "id" => "mission-form",
        "fields" => %{
          "display_name" =>
            mission_field("mission_display_name", "mission[display_name]", "Display Name"),
          "slug" => mission_field("mission_slug", "mission[slug]", "Slug")
        },
        "actions" => %{
          "submit" => %{"id" => "create-mission-button", "label" => "Create Mission"},
          "cancel" => %{"id" => "cancel-mission-link", "label" => "Cancel", "href" => "/missions"}
        }
      }
    }
  end

  defp mission_field(id, name, label),
    do: %{
      "id" => id,
      "name" => name,
      "type" => "text",
      "label" => label,
      "required" => true,
      "value" => ""
    }
end
