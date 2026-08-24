defmodule CadenceWeb.AdminModeLive.Presentation do
  @moduledoc false

  use CadenceWeb, :html

  @doc false
  def build do
    action = ~p"/admin-mode"

    %{
      root: element(%{"class" => "space-y-4"}),
      header: %{
        root: element(%{"class" => "text-center"}),
        brand:
          text("◆ CADENCE", %{"class" => "text-primary tracking-[0.15em] text-sm font-semibold"}),
        heading:
          text("Enter admin mode", %{"class" => "mt-3 text-xl font-bold text-base-content"}),
        body:
          text(
            "Re-enter your password to temporarily enable platform-wide administration.",
            %{"class" => "mt-1 text-xs text-base-content/70"}
          )
      },
      form: %{
        attrs:
          raw_attrs(%{
            "action" => action,
            "class" => "space-y-4",
            "id" => "admin-mode-form",
            "method" => "post"
          }),
        hidden_fields: [csrf_field(action)],
        password: %{
          root: element(%{"class" => "fieldset mb-3"}),
          label: text("Password", %{"class" => "hud-label block mb-1.5"}),
          input:
            element(%{
              "autocomplete" => "current-password",
              "autofocus" => true,
              "class" => "w-full input",
              "id" => "admin_mode_password",
              "name" => "admin_mode[password]",
              "required" => true,
              "type" => "password"
            })
        },
        submit:
          text("Enter admin mode", %{
            "class" => "btn btn-primary w-full",
            "type" => "submit"
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

  defp csrf_field(action) do
    element(%{
      "hidden" => true,
      "name" => "_csrf_token",
      "type" => "hidden",
      "value" => Plug.CSRFProtection.get_csrf_token_for(action)
    })
  end

  defp element(attrs), do: %{attrs: raw_attrs(attrs)}
  defp text(value, attrs), do: %{attrs: raw_attrs(attrs), text: value}
end
