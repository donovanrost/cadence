defmodule CadenceWeb.AdminOrganizationNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Organizations.Organization

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"display_name" => "", "slug" => ""}, as: :organization)

    {:ok,
     socket
     |> assign(:page_title, "New Organization")
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"organization" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :organization))}
  end

  @impl true
  def handle_event("save", %{"organization" => params}, socket) do
    display_name = normalize_param(params["display_name"])
    slug = normalize_param(params["slug"])

    if is_nil(display_name) or is_nil(slug) do
      {:noreply, put_flash(socket, :error, "Display name and slug are required.")}
    else
      organization = Organization.new(%{display_name: display_name, slug: slug})

      case Cadence.persist_organization(organization) do
        {:ok, _org} ->
          {:noreply,
           socket
           |> put_flash(:info, "Organization created successfully.")
           |> push_navigate(to: ~p"/admin/organizations")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, put_flash(socket, :error, format_changeset_errors(changeset))}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Failed to create organization: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link navigate={~p"/admin/organizations"} class="text-sm text-primary hover:underline">
          &larr; Organizations
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">Create Organization</h1>
      </div>

      <.form for={@form} id="org-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.input field={@form[:display_name]} type="text" label="Display Name" required />
        <.input field={@form[:slug]} type="text" label="Slug" required />
        <button type="submit" class="btn btn-primary">Create Organization</button>
      </.form>
    </div>
    """
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
