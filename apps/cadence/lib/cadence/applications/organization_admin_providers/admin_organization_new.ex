defmodule Cadence.Applications.OrganizationAdminProviders.AdminOrganizationNew do
  @moduledoc false

  alias Cadence.Organizations.Organization

  @spec props() :: map()
  def props, do: %{page: page_dto(), form: form_dto(%{})}

  @spec form(map()) :: map()
  def form(params) when is_map(params), do: form_dto(params)

  @spec create(map()) :: {:ok, map()} | {:error, term()}
  def create(params) when is_map(params) do
    display_name = normalize_param(params["display_name"])
    slug = normalize_param(params["slug"])

    if is_binary(display_name) and is_binary(slug) do
      case Cadence.Organizations.persist_organization(
             Organization.new(%{display_name: display_name, slug: slug})
           ) do
        {:ok, _organization} -> {:ok, %{navigate: "/admin/organizations"}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_organization}
    end
  end

  defp page_dto do
    %{
      title: "Create Organization",
      breadcrumbs: [
        %{label: "Platform Admin", href: "/admin"},
        %{label: "Organizations", href: "/admin/organizations"},
        %{label: "Create Organization", href: nil}
      ],
      submit_label: "Create organization",
      cancel_label: "Cancel",
      cancel_href: "/admin/organizations"
    }
  end

  defp form_dto(params),
    do: %{display_name: string_param(params, "display_name"), slug: string_param(params, "slug")}

  defp string_param(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp normalize_param(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_param(_other), do: nil
end
