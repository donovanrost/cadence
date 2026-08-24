defmodule CadenceWeb.NoOrganizationLive.Presentation do
  @moduledoc false

  use CadenceWeb, :html

  @doc false
  def build(pending_invitations_count) when is_integer(pending_invitations_count) do
    sign_out_action = ~p"/session"

    %{
      root: element(%{"class" => "space-y-4 text-center"}),
      heading:
        text("No organization access", %{"class" => "text-xl font-bold text-base-content"}),
      body:
        text(
          "You don't have access to any organization yet. Ask an administrator for an invitation.",
          %{"class" => "text-sm text-base-content/70"}
        ),
      pending_invitations: pending_invitations(pending_invitations_count),
      sign_out: %{
        form: %{
          attrs:
            raw_attrs(%{
              "action" => sign_out_action,
              "class" => "w-full",
              "method" => "post"
            }),
          hidden_fields: [
            element(%{
              "hidden" => true,
              "name" => "_method",
              "type" => "hidden",
              "value" => "delete"
            }),
            csrf_field(sign_out_action)
          ]
        },
        button:
          text("Sign out", %{
            "class" => "btn btn-ghost btn-sm w-full gap-2 text-xs uppercase tracking-wide",
            "type" => "submit"
          }),
        icon:
          element(%{
            "class" => "hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80"
          })
      }
    }
  end

  @doc false
  def raw_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp pending_invitations(count) when count > 0 do
    %{
      root:
        element(%{
          "class" => "p-4 border border-primary/30 rounded-sm bg-primary/5 text-left"
        }),
      message: %{
        root: element(%{"class" => "text-sm text-base-content"}),
        prefix: "You have",
        count: text(count, %{"class" => "font-bold text-primary"}),
        suffix: if(count == 1, do: "pending invitation.", else: "pending invitations.")
      },
      link:
        text("View notifications", %{
          "class" =>
            "mt-2 inline-flex items-center gap-1 text-xs text-primary uppercase tracking-wide hover:underline",
          "data-phx-link" => "redirect",
          "data-phx-link-state" => "push",
          "href" => ~p"/notifications"
        }),
      link_icon: element(%{"class" => "hero-arrow-right h-3 w-3"})
    }
  end

  defp pending_invitations(_count), do: nil

  defp csrf_field(action) do
    element(%{
      "hidden" => true,
      "name" => "_csrf_token",
      "type" => "hidden",
      "value" => Plug.CSRFProtection.get_csrf_token_for(action)
    })
  end

  defp element(attrs), do: %{attrs: raw_attrs(attrs)}
  defp text(value, attrs), do: %{attrs: raw_attrs(attrs), text: to_string(value)}
end
