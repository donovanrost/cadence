defmodule Cadence.Reads.Catalog.Presentation do
  @moduledoc false

  alias Cadence.Ids

  def import_status_tone(:completed), do: "ready"
  def import_status_tone(:failed), do: "blocked"
  def import_status_tone(_status), do: "info"
  def import_status_label(:running), do: "Running"
  def import_status_label(:completed), do: "Completed"
  def import_status_label(:failed), do: "Failed"
  def import_status_label(status), do: status |> to_string() |> String.capitalize()

  def catalog_breadcrumbs(mission_id) do
    %{"attrs" => attrs, "items" => [mission, current]} =
      mission_breadcrumbs("Catalog", mission_id)

    %{
      "attrs" => attrs,
      "mission" => mission["link"],
      "separator" => current["separator"],
      "current" => current["current"]
    }
  end

  def mission_breadcrumbs(current, mission_id),
    do: %{
      "attrs" => %{
        "aria-label" => "Breadcrumb",
        "class" =>
          "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
      },
      "items" => [
        %{
          "key" => "mission",
          "separator" => nil,
          "link" => %{"attrs" => navigate_attrs(mission_href(mission_id)), "text" => "Mission"},
          "current" => nil
        },
        %{
          "key" => "current",
          "separator" => separator(),
          "link" => nil,
          "current" => %{"attrs" => %{"class" => "text-primary/90"}, "text" => current}
        }
      ]
    }

  def separator,
    do: %{"attrs" => %{"class" => "text-base-content/20", "aria-hidden" => "true"}, "text" => "/"}

  def navigate_attrs(href),
    do: %{"data-phx-link" => "redirect", "data-phx-link-state" => "push", "href" => href}

  def mission_href(mission_id), do: "/missions/#{mission_id}"
  def safe_key(key), do: String.replace(key, ~r/[^A-Za-z0-9_-]+/, "-")
  def atom_string(nil), do: nil
  def atom_string(value) when is_atom(value), do: Atom.to_string(value)
  def atom_string(value), do: value
  def format_datetime(nil), do: nil
  def format_datetime(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")
  def format_short_datetime(nil), do: nil
  def format_short_datetime(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S")

  def optional(fun) do
    case fun.() do
      {:ok, value} -> value
      {:error, _} -> nil
    end
  end

  def subject_id(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case Ids.path_segment(value) do
          {:ok, value} -> {:ok, value}
          {:error, :invalid_identifier} -> {:error, :invalid_application_request}
        end

      _invalid ->
        {:error, :invalid_application_request}
    end
  end
end
