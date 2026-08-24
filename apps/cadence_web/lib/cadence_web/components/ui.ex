defmodule CadenceWeb.UI do
  @moduledoc """
  Cadence browser primitive component set.

  HEEx function components that capture the Cadence HUD aesthetic using
  Tailwind v4 utilities internally. Start small — only the primitives
  that a concrete page actually needs should be added here.
  """

  use Phoenix.Component
  use LiveVue
  use LiveVue.Components, vue_root: ["./assets/vue", "./lib/cadence_web"]

  import Phoenix.Component, except: [sigil_H: 2]
  import LiveVue.SharedPropsView, only: [sigil_H: 2]

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  @doc """
  Bell icon with unread badge and recent-notifications dropdown.

  Attrs:
    * `id` — unique DOM id (layouts render this twice, so ids must differ)
    * `count` — unread count (integer)
    * `notifications` — list of `%Cadence.Notifications.Notification{}` (top 5)
  """
  attr :id, :string, required: true
  attr :count, :integer, default: 0
  attr :notifications, :list, default: []

  def notifications_bell(assigns) do
    assigns = assign(assigns, :presentation, notifications_bell_presentation(assigns))

    ~H"""
    <.vue
      id={@id}
      v-component="NotificationsBell"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  @doc false
  def notifications_bell_presentation(assigns) do
    notifications_path = ~p"/notifications"

    %{
      "root" => %{"class" => "dropdown dropdown-end"},
      "trigger" => %{
        "class" => "btn btn-ghost btn-sm btn-circle relative",
        "attrs" =>
          raw_attrs(%{
            "type" => "button",
            "data-dropdown-trigger" => true,
            "aria-haspopup" => "menu",
            "aria-expanded" => "false",
            "aria-controls" => "#{assigns.id}-menu",
            "aria-label" => "Notifications"
          }),
        "icon_class" => "hero-bell h-5 w-5",
        "badge" => notification_badge(assigns.count)
      },
      "menu" => %{
        "id" => "#{assigns.id}-menu",
        "class" =>
          "dropdown-content menu bg-base-200 z-[var(--z-popover)] w-80 p-2 shadow-lg border border-primary/20 max-h-96 overflow-y-auto",
        "attrs" => raw_attrs(%{"role" => "menu"}),
        "title" => %{
          "item_class" => "menu-title px-3 py-2",
          "label_class" => "hud-label",
          "label" => "Notifications",
          "unread_class" => "text-primary",
          "unread_label" => unread_label(assigns.count)
        },
        "empty_state" =>
          if(assigns.notifications == [],
            do: %{
              "class" => "px-3 py-4 text-center text-sm text-base-content/60",
              "label" => "No notifications"
            },
            else: nil
          ),
        "notifications" =>
          assigns.notifications
          |> Enum.with_index()
          |> Enum.map(fn {notification, index} ->
            notification_presentation(notification, index, notifications_path)
          end),
        "footer" => %{
          "item_class" => "border-t border-primary/10 mt-1 pt-1",
          "class" => "text-xs text-primary uppercase tracking-wide",
          "attrs" => navigate_attrs(notifications_path),
          "label" => "See all notifications"
        }
      }
    }
  end

  defp notification_badge(count) when count > 0 do
    %{
      "class" => "badge badge-primary badge-xs absolute -top-0.5 -right-0.5 font-mono",
      "text" => format_count(count)
    }
  end

  defp notification_badge(_count), do: nil

  defp unread_label(count) when count > 0, do: "(#{count} unread)"
  defp unread_label(_count), do: nil

  defp notification_presentation(notification, index, notifications_path) do
    %{
      "key" => notification |> Map.get(:notification_id, index) |> to_string(),
      "link" => %{
        "class" => "flex items-start gap-2 px-3 py-2",
        "attrs" => navigate_attrs(notifications_path)
      },
      "dot_class" => notification_dot_class(notification.read_at),
      "content_class" => "flex-1 min-w-0",
      "title" => %{
        "class" => "block text-xs font-semibold text-base-content truncate",
        "text" => notification.title
      },
      "body" =>
        if(notification.body,
          do: %{
            "class" => "block text-xs text-base-content/70 truncate",
            "text" => notification.body
          },
          else: nil
        )
    }
  end

  defp notification_dot_class(nil),
    do: "mt-1.5 w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0"

  defp notification_dot_class(read_at) when read_at not in [nil, false],
    do: "mt-1.5 w-1.5 h-1.5 flex-shrink-0"

  defp notification_dot_class(_read_at), do: nil

  defp format_count(n) when n > 9, do: "9+"
  defp format_count(n), do: Integer.to_string(n)

  @doc """
  Top-right user menu — trigger plus popover panel with identity, org context,
  platform-admin shortcut (when applicable), and sign out.

  Attrs:
    * `id` — unique DOM id (layouts render this twice, so ids must differ)
    * `scope` — `%Cadence.Auth.Scope{}` with `:user` and optional `:organization`
    * `memberships` — list of `%{membership: OrganizationMembership.t(), organization: Organization.t()}`
    * `platform_admin?` — boolean
  """
  attr :id, :string, required: true
  attr :scope, :any, required: true
  attr :memberships, :list, default: []
  attr :platform_admin?, :boolean, default: false

  def user_menu(assigns) do
    assigns = assign(assigns, :presentation, user_menu_presentation(assigns))

    ~H"""
    <.vue
      id={@id}
      v-component="UserMenu"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  @doc false
  def user_menu_presentation(assigns) do
    user = assigns.scope.user

    %{
      "root" => %{"class" => "dropdown dropdown-end"},
      "trigger" => %{
        "class" => "btn btn-ghost btn-sm gap-1",
        "attrs" =>
          raw_attrs(%{
            "type" => "button",
            "data-dropdown-trigger" => true,
            "aria-haspopup" => "menu",
            "aria-expanded" => "false",
            "aria-controls" => "#{assigns.id}-menu"
          }),
        "label" => %{
          "class" => "text-xs text-base-content/60",
          "text" => display_label(user)
        },
        "icon_class" => "hero-chevron-down h-3 w-3 opacity-60 transition-transform"
      },
      "menu" => %{
        "id" => "#{assigns.id}-menu",
        "class" =>
          "dropdown-content menu bg-base-200 z-[var(--z-popover)] w-72 p-2 shadow-lg border border-primary/20",
        "attrs" => raw_attrs(%{"role" => "menu"}),
        "identity" => identity_presentation(user),
        "organization" => organization_presentation(assigns.scope, assigns.memberships),
        "admin_action" => admin_action_presentation(assigns.scope, assigns.platform_admin?),
        "leave_admin_mode" => leave_admin_mode_presentation(assigns.scope),
        "sign_out" => sign_out_presentation()
      }
    }
  end

  defp identity_presentation(user) do
    %{
      "element" => "div",
      "class" => "px-3 py-2",
      "attrs" => raw_attrs(%{"role" => "presentation"}),
      "label" => %{
        "class" => "text-sm font-semibold text-base-content",
        "text" => display_label(user)
      },
      "email" =>
        if(user.display_name not in [nil, ""],
          do: %{
            "class" => "text-xs text-base-content/60 truncate",
            "text" => user.email
          },
          else: nil
        )
    }
  end

  defp organization_presentation(%{organization: nil}, _memberships), do: nil

  defp organization_presentation(scope, memberships) do
    organization = scope.organization

    %{
      "element" => "div",
      "class" => "border-t border-primary/10 mt-1 pt-1",
      "attrs" => raw_attrs(%{"role" => "presentation"}),
      "label" => %{
        "class" => "hud-label px-3 py-1 block",
        "text" => "ORGANIZATION"
      },
      "current" => %{
        "class" => "px-3 py-2 text-sm text-base-content truncate",
        "text" => organization.display_name
      },
      "switcher" => organization_switcher(organization, memberships)
    }
  end

  defp organization_switcher(_organization, memberships) when length(memberships) <= 1,
    do: nil

  defp organization_switcher(organization, memberships) do
    %{
      "class" => "group",
      "summary" => %{
        "class" =>
          "flex items-center justify-between gap-2 px-3 py-2 cursor-pointer text-sm text-base-content list-none",
        "label_class" => "truncate",
        "label" => organization.display_name,
        "icon_class" =>
          "hero-chevron-down h-3 w-3 opacity-60 transition-transform group-open:rotate-180"
      },
      "list_class" => "mt-1 space-y-0.5",
      "organizations" =>
        memberships
        |> Enum.reject(fn %{organization: other} ->
          other.organization_id == organization.organization_id
        end)
        |> Enum.map(fn %{organization: other} ->
          %{
            "key" => other.organization_id,
            "item_attrs" => raw_attrs(%{"role" => "presentation"}),
            "form" => organization_switch_form(other),
            "label" => other.display_name
          }
        end)
    }
  end

  defp organization_switch_form(organization) do
    form_presentation(~p"/session/organization", "put", [
      %{"name" => "organization_id", "value" => organization.organization_id}
    ])
    |> Map.put("button", %{
      "class" =>
        "flex w-full items-center gap-2 px-3 py-2 text-xs text-base-content/70 hover:text-primary",
      "attrs" => raw_attrs(%{"type" => "submit", "role" => "menuitem"}),
      "label_class" => "truncate"
    })
  end

  defp admin_action_presentation(_scope, false), do: nil

  defp admin_action_presentation(scope, true) do
    {href, label} =
      if scope.admin_mode? do
        {~p"/admin", "System administration"}
      else
        {~p"/admin-mode", "Enter admin mode"}
      end

    %{
      "item_class" => "border-t border-primary/10 mt-1 pt-1",
      "item_attrs" => raw_attrs(%{"role" => "presentation"}),
      "class" =>
        "flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase text-base-content/70 hover:text-primary",
      "attrs" => navigate_attrs(href, %{"role" => "menuitem"}),
      "icon_class" => "hero-cog-6-tooth h-4 w-4 opacity-80",
      "label" => label
    }
  end

  defp leave_admin_mode_presentation(%{admin_mode?: false}), do: nil

  defp leave_admin_mode_presentation(%{admin_mode?: true}) do
    form_presentation(~p"/admin-mode", "delete")
    |> Map.merge(%{
      "item_class" => nil,
      "item_attrs" => raw_attrs(%{"role" => "presentation"}),
      "button" => %{
        "class" =>
          "flex w-full items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase text-base-content/70 hover:text-primary",
        "attrs" => raw_attrs(%{"type" => "submit", "role" => "menuitem"}),
        "icon_class" => "hero-lock-closed h-4 w-4 opacity-80",
        "label" => "Leave admin mode"
      }
    })
  end

  defp sign_out_presentation do
    form_presentation(~p"/session", "delete")
    |> Map.merge(%{
      "item_class" => "border-t border-primary/10 mt-1 pt-1",
      "item_attrs" => raw_attrs(%{"role" => "presentation"}),
      "button" => %{
        "class" =>
          "flex w-full items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase text-base-content/70 hover:text-primary",
        "attrs" => raw_attrs(%{"type" => "submit", "role" => "menuitem"}),
        "icon_class" => "hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80",
        "label" => "Sign out"
      }
    })
  end

  defp form_presentation(action, method, extra_hidden_fields \\ []) do
    method_field = %{"name" => "_method", "value" => method}

    csrf_field = %{
      "hidden" => true,
      "name" => "_csrf_token",
      "value" => Plug.CSRFProtection.get_csrf_token_for(action)
    }

    %{
      "attrs" => raw_attrs(%{"action" => action, "method" => "post"}),
      "hidden_fields" =>
        [method_field, csrf_field]
        |> Kernel.++(extra_hidden_fields)
        |> Enum.map(&hidden_field_presentation/1)
    }
  end

  defp hidden_field_presentation(field) do
    %{
      "attrs" =>
        field
        |> Map.put("type", "hidden")
        |> raw_attrs()
    }
  end

  defp navigate_attrs(href, extra_attrs \\ %{}) do
    %{
      "href" => href,
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push"
    }
    |> Map.merge(extra_attrs)
    |> raw_attrs()
  end

  defp raw_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp display_label(%{display_name: name, email: email}) when name in [nil, ""], do: email
  defp display_label(%{display_name: name}), do: name

  @doc """
  Single-line breadcrumb trail. Items are `{label, path}` tuples; pass
  `nil` for the path to render the segment as plain text (used for the
  final segment, which represents the current page).
  """
  attr :items, :list, required: true

  def breadcrumbs(assigns) do
    assigns = assign(assigns, :last_index, length(assigns.items) - 1)

    ~H"""
    <nav
      aria-label="Breadcrumb"
      class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
    >
      <%= for {{label, path}, index} <- Enum.with_index(@items) do %>
        <span :if={index > 0} class="text-base-content/20" aria-hidden="true">/</span>
        <%= cond do %>
          <% index == @last_index -> %>
            <span class="text-primary/90">{label}</span>
          <% path -> %>
            <.link navigate={path} class="hover:text-primary transition-colors">{label}</.link>
          <% true -> %>
            <span>{label}</span>
        <% end %>
      <% end %>
    </nav>
    """
  end

  @doc """
  A sub-page / in-card section header: an optional `eyebrow` label over a
  title and description, with right-aligned `:actions` (a badge or button).

  Distinct from `<.page_header>` (page-level). Set `title_mono` for value-style
  titles (endpoints, IDs) that render in monospace primary. Left-column content
  richer than a plain title (counts, summaries, inline version tags) should stay
  as raw markup.
  """
  attr :eyebrow, :string, default: nil
  attr :title, :string, default: nil
  attr :title_mono, :boolean, default: false
  attr :description, :string, default: nil
  attr :class, :string, default: nil
  slot :actions

  def section_header(assigns) do
    ~H"""
    <div class={["flex items-start justify-between gap-4", @class]}>
      <div>
        <p :if={@eyebrow} class="hud-label mb-2">{@eyebrow}</p>
        <h2 :if={@title} class={["text-lg font-semibold", @title_mono && "font-mono text-primary"]}>
          {@title}
        </h2>
        <p :if={@description} class="mt-1 max-w-2xl text-sm text-base-content/70">{@description}</p>
      </div>
      <div :if={@actions != []} class="flex flex-wrap items-center justify-end gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end
end
