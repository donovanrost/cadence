defmodule CadenceWeb.ApplicationSurfaces.TableEvents do
  @moduledoc "URL-backed LiveView event adapter for host-rendered table pages."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_patch: 2]

  alias CadenceWeb.ApplicationSurfaces.DocumentState

  @spec change(binary() | integer(), Phoenix.LiveView.Socket.t(), binary()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def change(page, socket, surface_path) when is_binary(surface_path) do
    page = normalize_page(page)
    path = "#{surface_path}?#{URI.encode_query(%{"page" => page})}"
    {:noreply, push_patch(socket, to: path)}
  end

  @spec handle_params(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, socket) when is_map(params) do
    query_params = query_params(params)

    if query_params == socket.assigns.application_surface_query_params do
      {:noreply, socket}
    else
      case DocumentState.load(socket, query_params) do
        {:ok, socket} ->
          {:noreply, socket}

        {:error, _reason} ->
          {:noreply,
           assign(socket, :application_action_feedback, %{
             kind: :error,
             code: "surface_page_failed",
             message: "The requested application page could not be loaded."
           })}
      end
    end
  end

  @spec query_params(map()) :: %{required(binary()) => pos_integer()}
  def query_params(params) when is_map(params) do
    %{"page" => normalize_page(Map.get(params, "page", 1))}
  end

  defp normalize_page(page) when is_integer(page), do: max(page, 1)

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {parsed, ""} -> max(parsed, 1)
      _invalid -> 1
    end
  end

  defp normalize_page(_page), do: 1
end
