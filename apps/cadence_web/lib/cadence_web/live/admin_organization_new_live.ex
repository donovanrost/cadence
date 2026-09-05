defmodule CadenceWeb.AdminOrganizationNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Organizations.Organization

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Organization")
     |> assign(:nav_item, :admin_organizations)
     |> assign(:page, page_dto())
     |> assign(:form, form_dto(%{}))}
  end

  @impl true
  def handle_event("validate", %{"organization" => params}, socket) do
    {:noreply, assign(socket, :form, form_dto(params))}
  end

  @impl true
  def handle_event("save", %{"organization" => params}, socket) do
    display_name = normalize_param(params["display_name"])
    slug = normalize_param(params["slug"])

    if is_nil(display_name) or is_nil(slug) do
      {:noreply,
       socket
       |> assign(:form, form_dto(params))
       |> put_flash(:error, "Display name and slug are required.")}
    else
      organization = Organization.new(%{display_name: display_name, slug: slug})

      case Cadence.Organizations.persist_organization(organization) do
        {:ok, _org} ->
          {:noreply,
           socket
           |> put_flash(:info, "Organization created successfully.")
           |> push_navigate(to: ~p"/admin/organizations")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(:form, form_dto(params))
           |> put_flash(:error, format_changeset_errors(changeset))}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="admin-organization-new-component"
        v-component="FederatedFullPageSurface"
        application_key="organization_admin"
        surface_id="admin_organization_new"
        host_scope="admin"
        v-ssr={false}
      />
    </Layouts.app>
    """
  end

  @doc false
  def federated_props do
    %{page: page_dto(), form: form_dto(%{})}
  end

  @doc false
  def federated_form(params) when is_map(params), do: form_dto(params)

  defp page_dto do
    %{
      title: "Create Organization",
      breadcrumbs: [
        %{label: "Platform Admin", href: ~p"/admin"},
        %{label: "Organizations", href: ~p"/admin/organizations"},
        %{label: "Create Organization", href: nil}
      ],
      submit_label: "Create organization",
      cancel_label: "Cancel",
      cancel_href: ~p"/admin/organizations"
    }
  end

  defp form_dto(params) do
    %{
      display_name: string_param(params, "display_name"),
      slug: string_param(params, "slug")
    }
  end

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

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end
end
