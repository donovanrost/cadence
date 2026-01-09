defmodule CadenceWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: CadenceWeb.Gettext

  alias Phoenix.Component
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices with mission control HUD styling.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:success} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil

  attr :kind, :atom,
    values: [:info, :success, :warning, :error],
    doc: "used for styling and flash lookup"

  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-[90vw] sm:max-w-96 text-wrap break-words whitespace-pre-wrap max-h-64 overflow-auto",
        @kind == :info && "alert-info",
        @kind == :success && "alert-success",
        @kind == :warning && "alert-warning",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :success} name="hero-check-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :warning} name="hero-exclamation-triangle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-x-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold text-xs uppercase tracking-wider">{@title}</p>
          <p class="break-words">{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  Uses HUD/Mission Control styling with sharp corners and uppercase text.

  ## Variants

    * `"primary"` - Main action button with glow effect
    * `"secondary"` - Secondary actions
    * `"ghost"` - Minimal button for tertiary actions
    * `"danger"` - Destructive actions

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
      <.button variant="danger" phx-click="delete">Delete</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string
  attr :variant, :string, values: ~w(primary secondary ghost danger soft), default: "soft"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "btn-primary",
      "secondary" => "btn-secondary",
      "ghost" => "btn-ghost",
      "danger" => "btn-error",
      "soft" => "btn-primary btn-soft"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-3">
      <label class="flex items-center gap-3 cursor-pointer">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "checkbox checkbox-sm checkbox-primary"}
          {@rest}
        />
        <span class="text-sm">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-3">
      <label>
        <span :if={@label} class="hud-label block mb-1.5">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-3">
      <label>
        <span :if={@label} class="hud-label block mb-1.5">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-3">
      <label>
        <span :if={@label} class="hud-label block mb-1.5">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title in HUD/Mission Control style.

  Features uppercase tracking and subtle underline accent.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4", @class]}>
      <div>
        <h1 class="text-xl font-bold text-base-content">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-xs text-base-content/50 mt-0.5">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a HUD-style panel with optional corner brackets and header.

  ## Examples

      <.hud_panel>
        Content here
      </.hud_panel>

      <.hud_panel title="SYSTEM STATUS" corners={true}>
        <:header_actions>
          <.button variant="ghost">Refresh</.button>
        </:header_actions>
        Panel content
      </.hud_panel>
  """
  attr :title, :string, default: nil
  attr :corners, :boolean, default: false, doc: "show decorative corner brackets"
  attr :class, :string, default: nil
  slot :header_actions
  slot :inner_block, required: true

  def hud_panel(assigns) do
    ~H"""
    <div class={[
      "hud-panel",
      @corners && "hud-corners",
      @class
    ]}>
      <div :if={@title} class="hud-panel-header flex items-center justify-between">
        <span class="hud-label">{@title}</span>
        <div :if={@header_actions != []} class="flex items-center gap-2">
          {render_slot(@header_actions)}
        </div>
      </div>
      <div class="p-4">
        {render_slot(@inner_block)}
      </div>
      <!-- Bottom corners (CSS handles top corners) -->
      <div
        :if={@corners}
        class="absolute bottom-0 left-0 w-3 h-3 border-l-2 border-b-2 border-primary/60"
      >
      </div>
      <div
        :if={@corners}
        class="absolute bottom-0 right-0 w-3 h-3 border-r-2 border-b-2 border-primary/60"
      >
      </div>
    </div>
    """
  end

  @doc """
  Renders a HUD-style data display row.

  ## Examples

      <.hud_data label="ALTITUDE" value="408.2 km" />
      <.hud_data label="VELOCITY" value="7.66 km/s" status="nominal" />
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :status, :string, default: nil, values: [nil, "nominal", "warning", "critical"]

  def hud_data(assigns) do
    status_class =
      case assigns.status do
        "nominal" -> "text-success"
        "warning" -> "text-warning"
        "critical" -> "text-error"
        _ -> ""
      end

    assigns = assign(assigns, :status_class, status_class)

    ~H"""
    <div class="hud-data-row">
      <span class="hud-data-label">{@label}</span>
      <span class={["hud-data-value font-mono-data", @status_class]}>{@value}</span>
    </div>
    """
  end

  @doc """
  Renders a HUD-style status indicator.

  ## Examples

      <.hud_status status="nominal">Systems Online</.hud_status>
      <.hud_status status="warning">Low Fuel</.hud_status>
      <.hud_status status="critical">Hull Breach</.hud_status>
  """
  attr :status, :string, default: "nominal", values: ["nominal", "warning", "critical"]
  slot :inner_block, required: true

  def hud_status(assigns) do
    ~H"""
    <div class={["hud-status", "hud-status-#{@status}"]}>
      <span class="hud-status-dot"></span>
      <span>{render_slot(@inner_block)}</span>
    </div>
    """
  end

  @doc """
  Renders a table with generic styling.

  Uses HUD/Mission Control styling with monospace fonts and uppercase headers.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="hud-panel overflow-visible">
      <div class="overflow-x-auto">
        <table class="table table-zebra">
          <thead>
            <tr>
              <th :for={col <- @col}>{col[:label]}</th>
              <th :if={@action != []} class="text-right">
                <span class="sr-only">{gettext("Actions")}</span>
              </th>
            </tr>
          </thead>
          <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
            <tr
              :for={row <- @rows}
              id={@row_id && @row_id.(row)}
              class="hover:bg-primary/5 transition-colors"
            >
              <td
                :for={col <- @col}
                phx-click={@row_click && @row_click.(row)}
                class={@row_click && "hover:cursor-pointer"}
              >
                {render_slot(col, @row_item.(row))}
              </td>
              <td :if={@action != []} class="text-right overflow-visible">
                <div class="dropdown dropdown-end dropdown-left">
                  <div tabindex="0" role="button" class="btn btn-ghost btn-sm">
                    <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
                  </div>
                  <ul
                    tabindex="0"
                    class="dropdown-content menu bg-base-200 z-[100] w-52 p-2 shadow-lg border border-primary/20"
                  >
                    <%= for action <- @action do %>
                      <li>{render_slot(action, @row_item.(row))}</li>
                    <% end %>
                  </ul>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(CadenceWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(CadenceWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  ## Additional Components

  @doc """
  Renders a modal with HUD/Mission Control styling.

  Features sharp corners, subtle glow effects, and a technical appearance.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :title, :string, default: nil, doc: "optional header title for the modal"
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 bg-base-300/80 dark:bg-black/80 backdrop-blur-sm transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center p-4">
          <div class="w-full max-w-2xl">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="relative hidden hud-panel hud-corners hud-border-glow transition"
            >
              <!-- Header bar -->
              <div class="flex items-center justify-between px-4 py-3 border-b border-primary/20 bg-primary/5">
                <span :if={@title} class="hud-label">{@title}</span>
                <span :if={!@title} class="hud-label text-base-content/40">MODAL</span>
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="btn btn-ghost btn-sm btn-square"
                  aria-label="close"
                >
                  <.icon name="hero-x-mark" class="h-4 w-4" />
                </button>
              </div>
              <!-- Content -->
              <div id={"#{@id}-content"} class="p-6">
                {render_slot(@inner_block)}
              </div>
              <!-- Bottom corners -->
              <div class="absolute bottom-0 left-0 w-3 h-3 border-l-2 border-b-2 border-primary/60">
              </div>
              <div class="absolute bottom-0 right-0 w-3 h-3 border-r-2 border-b-2 border-primary/60">
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  defp hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Renders a back navigation link.
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders breadcrumb navigation.

  ## Examples

      <.breadcrumb items={[
        {"Database Catalog", ~p"/missions/\#{@mission}/database"},
        {@database.name, nil}
      ]} />
  """
  attr :items, :list,
    required: true,
    doc: "List of {label, path} tuples. Last item path should be nil."

  def breadcrumb(assigns) do
    ~H"""
    <nav class="flex items-center gap-2 text-sm mb-4">
      <%= for {{label, path}, index} <- Enum.with_index(@items) do %>
        <%= if index > 0 do %>
          <span class="text-base-content/30">/</span>
        <% end %>
        <%= if path do %>
          <.link navigate={path} class="hud-label hover:text-primary transition-colors">
            {label}
          </.link>
        <% else %>
          <span class="text-base-content font-medium">{label}</span>
        <% end %>
      <% end %>
    </nav>
    """
  end

  @doc """
  Renders a simple form.
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders an avatar with user initials.

  ## Examples

      <.avatar email="john@example.com" />
      <.avatar email="jane@example.com" name="Jane Doe" />
      <.avatar email="user@example.com" size="lg" />
  """
  attr :email, :string, required: true
  attr :name, :string, default: nil
  attr :size, :string, default: "md", values: ~w(xs sm md lg)
  attr :class, :string, default: nil

  def avatar(assigns) do
    initials = avatar_initials(assigns)
    bg_class = avatar_background_class(assigns.email)
    size_class = avatar_size_class(assigns.size)

    assigns = assign(assigns, initials: initials, bg_class: bg_class, size_class: size_class)

    ~H"""
    <div class={[
      "avatar placeholder",
      @class
    ]}>
      <div class={[
        "rounded-full",
        @bg_class,
        @size_class,
        "flex items-center justify-center font-semibold"
      ]}>
        <span>{@initials}</span>
      </div>
    </div>
    """
  end

  defp avatar_initials(%{name: name, email: email}) do
    name
    |> display_name(email)
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp display_name(nil, email) do
    email
    |> String.split("@")
    |> List.first()
  end

  defp display_name(name, _email), do: name

  defp avatar_background_class(email) do
    :crypto.hash(:md5, email)
    |> :binary.decode_unsigned()
    |> rem(5)
    |> color_class()
  end

  defp color_class(0), do: "bg-primary text-primary-content"
  defp color_class(1), do: "bg-secondary text-secondary-content"
  defp color_class(2), do: "bg-accent text-accent-content"
  defp color_class(3), do: "bg-info text-info-content"
  defp color_class(_), do: "bg-success text-success-content"

  defp avatar_size_class("xs"), do: "h-6 w-6 text-[10px]"
  defp avatar_size_class("sm"), do: "h-8 w-8 text-xs"
  defp avatar_size_class("md"), do: "h-10 w-10 text-sm"
  defp avatar_size_class("lg"), do: "h-12 w-12 text-base"

  @doc """
  Renders a dropdown menu.

  ## Examples

      <.dropdown id="user-menu">
        <:trigger>
          <button class="btn">Menu</button>
        </:trigger>
        <li><a href="/profile">Profile</a></li>
        <li><a href="/settings">Settings</a></li>
        <li class="divider"></li>
        <li><a phx-click="logout">Sign Out</a></li>
      </.dropdown>
  """
  attr :id, :string, required: true
  attr :class, :string, default: nil
  slot :trigger, required: true
  slot :inner_block, required: true

  def dropdown(assigns) do
    ~H"""
    <div class={["dropdown dropdown-end", @class]} id={@id}>
      <div tabindex="0" role="button">
        {render_slot(@trigger)}
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-200 rounded-box z-[100] w-56 p-2 shadow-lg border border-primary/20 hud-grid"
      >
        {render_slot(@inner_block)}
      </ul>
    </div>
    """
  end

  @doc """
  Renders a sidebar navigation item with HUD/Mission Control styling.

  Features sharp corners, uppercase labels, and active state indicators.

  ## Examples

      <.sidebar_nav_item navigate={~p"/dashboard"} active={true}>
        <:icon><.icon name="hero-home" /></:icon>
        Dashboard
      </.sidebar_nav_item>
  """
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :active, :boolean, default: false
  attr :class, :string, default: nil
  slot :icon
  slot :inner_block, required: true

  def sidebar_nav_item(assigns) do
    ~H"""
    <li class="relative">
      <.link
        navigate={@navigate}
        patch={@patch}
        class={[
          "flex items-center gap-2 px-3 py-2 transition-all text-xs tracking-wide",
          @active &&
            [
              "bg-primary/10 text-primary border-l-2 border-primary",
              "shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]"
            ],
          !@active &&
            [
              "text-base-content/60 border-l-2 border-transparent",
              "hover:bg-primary/5 hover:text-base-content hover:border-primary/30"
            ],
          @class
        ]}
      >
        <span
          :if={@icon != []}
          class="opacity-80 flex-shrink-0 w-5 h-5 flex items-center justify-center"
        >
          {render_slot(@icon)}
        </span>
        <span class="flex-1 uppercase font-medium sidebar-label">{render_slot(@inner_block)}</span>
        <span :if={@active} class="w-4 h-4 flex items-center justify-center flex-shrink-0">
          <span class="w-1.5 h-1.5 bg-primary rounded-sm shadow-[0_0_6px_rgba(125,207,255,0.8)]">
          </span>
        </span>
      </.link>
    </li>
    """
  end

  @doc """
  Renders a collapsible sidebar navigation group with child items.

  The group auto-expands when any child is active.

  ## Examples

      <.sidebar_nav_group label="Database" icon="hero-circle-stack" expanded={@is_database or @is_catalog}>
        <.sidebar_nav_item navigate={~p"/database"} active={@is_database}>
          Versions
        </.sidebar_nav_item>
        <.sidebar_nav_item navigate={~p"/catalog"} active={@is_catalog}>
          Catalog
        </.sidebar_nav_item>
      </.sidebar_nav_group>
  """
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :expanded, :boolean, default: false
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def sidebar_nav_group(assigns) do
    # Generate a unique ID if not provided
    assigns =
      assign_new(assigns, :group_id, fn ->
        assigns[:id] || "nav-group-#{:erlang.phash2(assigns.label)}"
      end)

    ~H"""
    <li class="relative">
      <details open={@expanded} class="group">
        <summary class={[
          "flex items-center gap-2 px-3 py-2 transition-all cursor-pointer text-xs tracking-wide",
          "text-base-content/60 border-l-2 border-transparent",
          "hover:bg-primary/5 hover:text-base-content hover:border-primary/30",
          "[&::-webkit-details-marker]:hidden [&::marker]:hidden",
          @expanded && "text-base-content"
        ]}>
          <span class="opacity-80 flex-shrink-0 w-5 h-5 flex items-center justify-center">
            <.icon name={@icon} class="h-4 w-4" />
          </span>
          <span class="flex-1 uppercase font-medium sidebar-label">{@label}</span>
          <span class="w-4 h-4 flex items-center justify-center flex-shrink-0">
            <.icon
              name="hero-chevron-right"
              class="h-3 w-3 opacity-60 transition-transform group-open:rotate-90"
            />
          </span>
        </summary>
        <ul class="ml-5 mt-1 space-y-0.5 border-l border-primary/20 pl-2 sidebar-expanded-only">
          {render_slot(@inner_block)}
        </ul>
      </details>
    </li>
    """
  end

  @doc """
  Renders a child item within a sidebar nav group.

  ## Examples

      <.sidebar_nav_child navigate={~p"/catalog"} active={@is_catalog}>
        Catalog
      </.sidebar_nav_child>
  """
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  def sidebar_nav_child(assigns) do
    ~H"""
    <li>
      <.link
        navigate={@navigate}
        patch={@patch}
        class={[
          "flex items-center gap-2 px-3 py-1.5 text-xs tracking-wide transition-all uppercase",
          @active && "text-primary font-medium",
          !@active && "text-base-content/50 hover:text-base-content"
        ]}
      >
        <span class="w-1 h-1 rounded-sm bg-current opacity-40"></span>
        {render_slot(@inner_block)}
      </.link>
    </li>
    """
  end

  @doc """
  Renders a badge.

  ## Examples

      <.badge>New</.badge>
      <.badge variant="primary">Admin</.badge>
  """
  attr :variant, :string,
    default: "neutral",
    values: ~w(primary secondary accent info success warning error neutral)

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    variant_class =
      case assigns.variant do
        "primary" -> "badge-primary"
        "secondary" -> "badge-secondary"
        "accent" -> "badge-accent"
        "info" -> "badge-info"
        "success" -> "badge-success"
        "warning" -> "badge-warning"
        "error" -> "badge-error"
        _ -> "badge-neutral"
      end

    assigns = assign(assigns, :variant_class, variant_class)

    ~H"""
    <span class={["badge", @variant_class, @class]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders a status badge with automatic variant mapping.

  Automatically maps common status strings to appropriate badge variants.

  ## Examples

      <.status_badge status="active" />
      <.status_badge status="online" />
      <.status_badge status={@user.status} />
      <.status_badge status={true} true_label="Enabled" false_label="Disabled" />
  """
  attr :status, :any, required: true, doc: "status value (string or boolean)"
  attr :true_label, :string, default: "Yes", doc: "label for boolean true"
  attr :false_label, :string, default: "No", doc: "label for boolean false"
  attr :class, :string, default: nil

  def status_badge(assigns) do
    {variant, label} = status_to_variant(assigns.status, assigns.true_label, assigns.false_label)
    assigns = assign(assigns, variant: variant, label: label)

    ~H"""
    <.badge variant={@variant} class={@class}>{@label}</.badge>
    """
  end

  defp status_to_variant(true, true_label, _false_label), do: {"success", true_label}
  defp status_to_variant(false, _true_label, false_label), do: {"neutral", false_label}

  defp status_to_variant(status, _true_label, _false_label) when is_binary(status) do
    case status do
      # Success states
      s when s in ~w(active online enabled connected closed nominal yes on running) ->
        {"success", status}

      # Warning states
      s when s in ~w(standby connecting half_open pending warning degraded) ->
        {"warning", status}

      # Error states
      s when s in ~w(error failed suspended offline disconnected open critical) ->
        {"error", status}

      # Info states
      s when s in ~w(read info) ->
        {"info", status}

      # Accent states
      s when s in ~w(write) ->
        {"accent", status}

      # Secondary states
      s when s in ~w(read_write) ->
        {"secondary", status}

      # Default neutral
      _ ->
        {"neutral", status}
    end
  end

  defp status_to_variant(status, _true_label, _false_label), do: {"neutral", to_string(status)}
end
