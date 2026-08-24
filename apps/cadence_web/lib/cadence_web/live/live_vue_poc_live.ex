defmodule CadenceWeb.LiveVuePocLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "LiveVue PoC")
     |> assign(:presentation, page_presentation())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="livevue-poc-page-component"
        v-component="LiveVuePocPage"
        presentation={@presentation}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp page_presentation do
    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "livevue-poc-page",
            "class" => "space-y-6"
          })
      },
      "header" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "border-b border-primary/20 pb-4"
          }),
        "body" => %{
          "attrs" => presentation_attrs(%{"class" => false})
        },
        "content" => %{
          "attrs" => presentation_attrs(%{"class" => nil})
        },
        "title" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
            }),
          "text" => "LiveVue PoC"
        },
        "subtitle" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
            }),
          "text" => "A Vue component mounted inside the authenticated Cadence LiveView shell."
        }
      },
      "demo" => %{
        "attrs" => presentation_attrs(%{"id" => "livevue-poc-component"}),
        "message" => "Vue is mounted inside a Cadence LiveView"
      }
    }
  end
end
