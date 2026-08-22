defmodule CadenceWeb.ReviewLive.Changes do
  @moduledoc """
  LiveView for viewing procedure version changes with inline commenting.

  This is the "Changes" tab of the review workflow, providing:
  - Read-only view of procedure content (no editing)
  - Inline diff annotations showing added/removed/modified elements
  - Anchored comment threads on sections, steps, and blocks
  - Thread panel for viewing and adding comments

  Review approval actions are handled in the Overview tab.
  """
  use CadenceWeb, :live_view

  alias Cadence.Procedures
  alias Cadence.Procedures.V2
  alias CadenceWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        {:noreply, apply_action(socket, socket.assigns.live_action, params)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp apply_action(socket, :changes, %{
         "procedure_id" => procedure_id,
         "version_id" => version_id
       }) do
    mission = socket.assigns.mission

    case load_version_for_mission(mission, procedure_id, version_id) do
      {:ok, procedure, version} ->
        # Load sections with steps and blocks
        sections = V2.list_sections_with_steps(version_id)

        # Compute diff if there's a previous version
        {diff, diff_status_map} = load_diff(procedure, version)

        # Load thread counts for inline badges
        thread_counts = Procedures.get_thread_counts_by_anchor(version_id)

        # Load all threads for this version
        all_threads = Procedures.list_threads(version_id)

        # Count open threads for tab badge
        open_thread_count = Enum.count(all_threads, &(&1.status == :open))

        socket
        |> assign(:page_title, "Changes: #{procedure.name} v#{version.version_number}")
        |> assign(:procedure, procedure)
        |> assign(:version, version)
        |> assign(:sections, sections)
        |> assign(:diff, diff)
        |> assign(:diff_status_map, diff_status_map)
        |> assign(:thread_counts, thread_counts)
        |> assign(:all_threads, all_threads)
        |> assign(:open_thread_count, open_thread_count)
        |> assign(:selected_thread, nil)
        |> assign(:new_thread_anchor, nil)
        |> assign(:collapsed_sections, MapSet.new())

      {:error, message} ->
        socket
        |> put_flash(:error, message)
        |> push_navigate(to: ~p"/missions/#{mission}/procedures")
    end
  end

  # ─────────────────────────────────────────────────────────────────────
  # Data Loading
  # ─────────────────────────────────────────────────────────────────────

  defp load_version_for_mission(mission, procedure_id, version_id) do
    with {:ok, procedure} <- get_procedure(mission, procedure_id),
         {:ok, version} <- get_version(procedure, version_id) do
      {:ok, procedure, version}
    end
  end

  defp get_procedure(mission, procedure_id) do
    case Procedures.get_procedure(procedure_id) do
      nil ->
        {:error, "Procedure not found"}

      procedure ->
        if procedure.mission_id == mission.id do
          {:ok, procedure}
        else
          {:error, "Procedure does not belong to this mission"}
        end
    end
  end

  defp get_version(procedure, version_id) do
    case Procedures.get_version(version_id) do
      nil ->
        {:error, "Version not found"}

      version ->
        if version.procedure_id == procedure.id do
          {:ok, version}
        else
          {:error, "Version does not belong to this procedure"}
        end
    end
  end

  defp load_diff(procedure, version) do
    # Find the previous version to diff against
    previous_version = Procedures.get_previous_version(procedure.id, version.version_number)

    if previous_version do
      diff = V2.compute_version_diff(previous_version.id, version.id)

      if diff do
        status_map = V2.build_diff_status_map(diff)
        {diff, status_map}
      else
        {nil, %{}}
      end
    else
      {nil, %{}}
    end
  end

  # ─────────────────────────────────────────────────────────────────────
  # Event Handlers - Thread Management
  # ─────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_thread", %{"thread-id" => thread_id}, socket) do
    thread = Enum.find(socket.assigns.all_threads, &(&1.id == thread_id))
    {:noreply, assign(socket, :selected_thread, thread)}
  end

  def handle_event("close_thread_panel", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_thread, nil)
     |> assign(:new_thread_anchor, nil)}
  end

  def handle_event(
        "start_new_thread",
        %{"anchor-type" => anchor_type, "anchor-id" => anchor_id},
        socket
      ) do
    anchor_type = String.to_existing_atom(anchor_type)

    anchor_id =
      if anchor_id == "" or anchor_id == "null" do
        nil
      else
        anchor_id
      end

    {:noreply, assign(socket, :new_thread_anchor, {anchor_type, anchor_id})}
  end

  def handle_event("cancel_new_thread", _params, socket) do
    {:noreply, assign(socket, :new_thread_anchor, nil)}
  end

  def handle_event("create_thread", %{"body" => body}, socket) do
    {anchor_type, anchor_id} = socket.assigns.new_thread_anchor
    version = socket.assigns.version
    user_id = socket.assigns.current_scope.user.id

    case Procedures.create_thread(version, user_id,
           body: body,
           anchor_type: anchor_type,
           anchor_id: anchor_id
         ) do
      {:ok, thread} ->
        # Reload threads and counts
        all_threads = Procedures.list_threads(version.id)
        thread_counts = Procedures.get_thread_counts_by_anchor(version.id)
        open_thread_count = Enum.count(all_threads, &(&1.status == :open))

        {:noreply,
         socket
         |> assign(:all_threads, all_threads)
         |> assign(:thread_counts, thread_counts)
         |> assign(:open_thread_count, open_thread_count)
         |> assign(:new_thread_anchor, nil)
         |> assign(:selected_thread, thread)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create thread: #{inspect(reason)}")}
    end
  end

  def handle_event("add_comment", %{"body" => body}, socket) do
    thread = socket.assigns.selected_thread
    user_id = socket.assigns.current_scope.user.id

    case Procedures.add_comment(thread, user_id, body) do
      {:ok, _comment} ->
        # Reload the thread with updated comments
        updated_thread =
          Procedures.get_thread!(thread.id)
          |> Cadence.Repo.preload([:author, :review, comments: :user])

        all_threads = Procedures.list_threads(socket.assigns.version.id)

        {:noreply,
         socket
         |> assign(:selected_thread, updated_thread)
         |> assign(:all_threads, all_threads)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to add comment: #{inspect(reason)}")}
    end
  end

  def handle_event("resolve_thread", _params, socket) do
    thread = socket.assigns.selected_thread
    user_id = socket.assigns.current_scope.user.id

    case Procedures.resolve_thread(thread, user_id) do
      {:ok, updated_thread} ->
        all_threads = Procedures.list_threads(socket.assigns.version.id)
        thread_counts = Procedures.get_thread_counts_by_anchor(socket.assigns.version.id)
        open_thread_count = Enum.count(all_threads, &(&1.status == :open))

        {:noreply,
         socket
         |> assign(
           :selected_thread,
           Cadence.Repo.preload(updated_thread, [:author, :review, comments: :user])
         )
         |> assign(:all_threads, all_threads)
         |> assign(:thread_counts, thread_counts)
         |> assign(:open_thread_count, open_thread_count)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Already #{reason}")}
    end
  end

  def handle_event("reopen_thread", _params, socket) do
    thread = socket.assigns.selected_thread

    case Procedures.reopen_thread(thread) do
      {:ok, updated_thread} ->
        all_threads = Procedures.list_threads(socket.assigns.version.id)
        thread_counts = Procedures.get_thread_counts_by_anchor(socket.assigns.version.id)
        open_thread_count = Enum.count(all_threads, &(&1.status == :open))

        {:noreply,
         socket
         |> assign(
           :selected_thread,
           Cadence.Repo.preload(updated_thread, [:author, :review, comments: :user])
         )
         |> assign(:all_threads, all_threads)
         |> assign(:thread_counts, thread_counts)
         |> assign(:open_thread_count, open_thread_count)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Already #{reason}")}
    end
  end

  # ─────────────────────────────────────────────────────────────────────
  # Event Handlers - Section Collapse
  # ─────────────────────────────────────────────────────────────────────

  def handle_event("toggle_section", %{"section-id" => section_id}, socket) do
    collapsed = socket.assigns.collapsed_sections

    new_collapsed =
      if MapSet.member?(collapsed, section_id) do
        MapSet.delete(collapsed, section_id)
      else
        MapSet.put(collapsed, section_id)
      end

    {:noreply, assign(socket, :collapsed_sections, new_collapsed)}
  end

  # ─────────────────────────────────────────────────────────────────────
  # Render
  # ─────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:bare}>
      <div class="h-[calc(100vh-3rem)] flex flex-col overflow-hidden">
        <%!-- Header --%>
        <div class="flex flex-col gap-2 px-4 py-3 border-b border-primary/20 bg-surface-raised">
          <%!-- Breadcrumb Navigation --%>
          <nav class="flex items-center gap-2 text-xs">
            <.link
              navigate={~p"/missions/#{@mission}/procedures/reviews"}
              class="hud-label hover:text-primary transition-colors"
            >
              Reviews
            </.link>
            <span class="text-base-content/30">/</span>
            <.link
              navigate={~p"/missions/#{@mission}/procedures/#{@procedure}"}
              class="hud-label hover:text-primary transition-colors"
            >
              {@procedure.name}
            </.link>
            <span class="text-base-content/30">/</span>
            <span class="text-base-content font-medium">v{@version.version_number}</span>
          </nav>

          <%!-- Title Row --%>
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <h1 class="text-lg font-bold">{@procedure.name}</h1>
              <span class="text-xs text-base-content/60">v{@version.version_number}</span>
              <.version_status_badge status={@version.status} />
            </div>

            <%!-- Diff Stats (compact) --%>
            <.diff_stats_compact :if={@diff} diff={@diff} />
          </div>

          <%!-- Tab Navigation --%>
          <div class="flex items-center gap-1 border-b border-base-content/10 -mb-3 -mx-4 px-4">
            <.link
              navigate={
                ~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{@version.id}/review"
              }
              class="tab tab-bordered"
            >
              Overview
            </.link>
            <.link
              patch={
                ~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{@version.id}/review/changes"
              }
              class="tab tab-bordered tab-active"
            >
              Changes
              <span :if={@open_thread_count > 0} class="badge badge-xs badge-warning ml-1">
                {@open_thread_count}
              </span>
            </.link>
          </div>
        </div>

        <%!-- Main Content --%>
        <div class="flex-1 flex overflow-hidden">
          <%!-- Procedure Content --%>
          <div class={[
            "flex-1 overflow-y-auto bg-base-100",
            (@selected_thread || @new_thread_anchor) && "mr-96"
          ]}>
            <div class="p-4 max-w-4xl mx-auto">
              <%!-- Diff Summary Card --%>
              <div
                :if={@diff}
                class="mb-6 p-4 rounded-lg bg-base-200/50 border border-base-content/5"
              >
                <div class="flex items-center gap-3 mb-3">
                  <.icon name="hero-document-magnifying-glass" class="h-5 w-5 text-primary" />
                  <span class="font-semibold text-sm">Changes from previous version</span>
                </div>
                <.diff_stats diff={@diff} />
              </div>

              <%!-- Inline Comment Hint --%>
              <div class="mb-6 p-3 rounded-lg bg-info/10 border border-info/20 flex items-center gap-3">
                <.icon name="hero-chat-bubble-left" class="h-5 w-5 text-info" />
                <p class="text-sm text-info">
                  Click the <span class="font-mono bg-base-200 px-1 rounded">💬</span>
                  icon on any section, step, or block to add a comment.
                </p>
              </div>

              <%!-- Procedure Sections --%>
              <div class="space-y-6">
                <%= for section <- @sections do %>
                  <.section_card
                    section={section}
                    diff_status_map={@diff_status_map}
                    thread_counts={@thread_counts}
                    all_threads={@all_threads}
                    selected_thread={@selected_thread}
                    collapsed={MapSet.member?(@collapsed_sections, section.id)}
                  />
                <% end %>

                <div :if={Enum.empty?(@sections)} class="text-center py-16 text-base-content/50">
                  <.icon name="hero-document-text" class="h-16 w-16 mx-auto mb-4 opacity-30" />
                  <p class="text-lg font-medium">No content in this version</p>
                  <p class="text-sm mt-1">This version doesn't have any sections yet.</p>
                </div>
              </div>
            </div>
          </div>

          <%!-- Right: Thread Detail Panel --%>
          <.thread_panel
            :if={@selected_thread || @new_thread_anchor}
            selected_thread={@selected_thread}
            new_thread_anchor={@new_thread_anchor}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ─────────────────────────────────────────────────────────────────────
  # Components
  # ─────────────────────────────────────────────────────────────────────

  defp version_status_badge(assigns) do
    color =
      case assigns.status do
        :draft -> "badge-ghost"
        :in_review -> "badge-info"
        :changes_requested -> "badge-warning"
        :approved -> "badge-success"
        :closed -> "badge-ghost"
        :deprecated -> "badge-error"
        _ -> "badge-ghost"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={"badge badge-sm #{@color}"}>{Phoenix.Naming.humanize(@status)}</span>
    """
  end

  defp diff_stats(assigns) do
    assigns = assign(assigns, :stats, assigns.diff.stats)

    ~H"""
    <div class="flex flex-wrap items-center gap-4 text-sm">
      <span :if={@stats.sections_added > 0} class="text-success">
        +{@stats.sections_added} sections
      </span>
      <span :if={@stats.sections_removed > 0} class="text-error">
        -{@stats.sections_removed} sections
      </span>
      <span :if={@stats.steps_added > 0} class="text-success">
        +{@stats.steps_added} steps
      </span>
      <span :if={@stats.steps_removed > 0} class="text-error">
        -{@stats.steps_removed} steps
      </span>
      <span :if={@stats.blocks_added > 0} class="text-success">
        +{@stats.blocks_added} blocks
      </span>
      <span :if={@stats.blocks_removed > 0} class="text-error">
        -{@stats.blocks_removed} blocks
      </span>
      <span
        :if={@stats.sections_modified + @stats.steps_modified + @stats.blocks_modified > 0}
        class="text-warning"
      >
        ~{@stats.sections_modified + @stats.steps_modified + @stats.blocks_modified} modified
      </span>
    </div>
    """
  end

  defp diff_stats_compact(assigns) do
    stats = assigns.diff.stats

    total_added =
      stats.sections_added + stats.steps_added + stats.blocks_added

    total_removed =
      stats.sections_removed + stats.steps_removed + stats.blocks_removed

    total_modified =
      stats.sections_modified + stats.steps_modified + stats.blocks_modified

    assigns =
      assigns
      |> assign(:total_added, total_added)
      |> assign(:total_removed, total_removed)
      |> assign(:total_modified, total_modified)

    ~H"""
    <div class="flex items-center gap-3 text-xs font-mono">
      <span :if={@total_added > 0} class="text-success font-semibold">+{@total_added}</span>
      <span :if={@total_removed > 0} class="text-error font-semibold">-{@total_removed}</span>
      <span :if={@total_modified > 0} class="text-warning font-semibold">~{@total_modified}</span>
    </div>
    """
  end

  attr :threads, :list, required: true
  attr :selected_thread, :map, default: nil
  attr :compact, :boolean, default: false

  defp inline_threads(assigns) do
    # Sort threads: blocking first, then by status (open before resolved), then by date
    sorted_threads =
      assigns.threads
      |> Enum.sort_by(fn thread ->
        blocking_priority = if thread.review_id, do: 0, else: 1
        status_priority = if thread.status == :open, do: 0, else: 1
        {blocking_priority, status_priority, thread.inserted_at}
      end)

    assigns = assign(assigns, :sorted_threads, sorted_threads)

    ~H"""
    <div class={[
      "border-t border-base-content/10 bg-info/5",
      @compact && "text-sm"
    ]}>
      <%= for thread <- @sorted_threads do %>
        <.inline_thread_item
          thread={thread}
          selected={@selected_thread && @selected_thread.id == thread.id}
          compact={@compact}
        />
      <% end %>
    </div>
    """
  end

  attr :thread, :map, required: true
  attr :selected, :boolean, default: false
  attr :compact, :boolean, default: false

  defp inline_thread_item(assigns) do
    first_comment =
      if is_list(assigns.thread.comments) && length(assigns.thread.comments) > 0 do
        List.first(assigns.thread.comments)
      else
        nil
      end

    icon_class =
      if assigns.compact,
        do: "shrink-0 text-base-content/30 h-3 w-3",
        else: "shrink-0 text-base-content/30 h-4 w-4"

    # Determine if this is a blocking thread (associated with a request_changes review)
    is_blocking = not is_nil(assigns.thread.review_id)

    assigns =
      assigns
      |> assign(:first_comment, first_comment)
      |> assign(:icon_class, icon_class)
      |> assign(:is_blocking, is_blocking)

    ~H"""
    <button
      type="button"
      phx-click="select_thread"
      phx-value-thread-id={@thread.id}
      class={[
        "w-full text-left transition-colors border-l-2",
        @compact && "px-3 py-2",
        !@compact && "px-4 py-3",
        @selected && "bg-primary/10 border-l-primary",
        !@selected && @is_blocking && @thread.status == :open &&
          "border-l-error bg-error/5 hover:bg-error/10",
        !@selected && !@is_blocking && @thread.status == :open &&
          "border-l-warning hover:bg-warning/10",
        !@selected && @thread.status == :resolved && "border-l-success hover:bg-success/10"
      ]}
    >
      <div class="flex items-start gap-3">
        <%!-- Blocking indicator icon --%>
        <div :if={@is_blocking && @thread.status == :open} class="shrink-0 mt-0.5">
          <.icon name="hero-exclamation-triangle-solid" class="h-4 w-4 text-error" />
        </div>

        <%!-- Avatar --%>
        <div class={[
          "shrink-0 rounded-full flex items-center justify-center font-medium",
          @is_blocking && @thread.status == :open && "bg-error/20 text-error",
          !(@is_blocking && @thread.status == :open) && "bg-primary/20 text-primary",
          @compact && "w-5 h-5 text-xs",
          !@compact && "w-6 h-6 text-xs"
        ]}>
          {@thread.author.email |> String.first() |> String.upcase()}
        </div>

        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <span class={["font-medium", @compact && "text-xs", !@compact && "text-sm"]}>
              {@thread.author.email}
            </span>
            <%!-- Blocking badge - prominent red styling --%>
            <span
              :if={@is_blocking && @thread.status == :open}
              class="badge badge-xs badge-error gap-0.5"
            >
              <.icon name="hero-exclamation-triangle" class="h-2.5 w-2.5" /> Blocking
            </span>
            <span class={[
              "badge badge-xs",
              @thread.status == :open && !@is_blocking && "badge-warning",
              @thread.status == :open && @is_blocking && "badge-ghost",
              @thread.status == :resolved && "badge-success"
            ]}>
              {Phoenix.Naming.humanize(@thread.status)}
            </span>
            <span class="text-xs text-base-content/40">
              {format_relative_time(@thread.inserted_at)}
            </span>
            <span :if={length(@thread.comments) > 1} class="text-xs text-base-content/50">
              · {length(@thread.comments)} comments
            </span>
          </div>

          <p
            :if={@first_comment}
            class={[
              "text-base-content/70 mt-1",
              @compact && "text-xs line-clamp-1",
              !@compact && "text-sm line-clamp-2"
            ]}
          >
            {@first_comment.body}
          </p>
        </div>

        <%!-- Expand indicator --%>
        <.icon name="hero-chevron-right" class={@icon_class} />
      </div>
    </button>
    """
  end

  defp section_card(assigns) do
    diff_status = Map.get(assigns.diff_status_map, assigns.section.id)
    thread_count = Map.get(assigns.thread_counts, {:section, assigns.section.id}, 0)

    # Filter threads for this section
    section_threads =
      assigns.all_threads
      |> Enum.filter(&(&1.anchor_type == :section && &1.anchor_id == assigns.section.id))

    assigns =
      assigns
      |> assign(:diff_status, diff_status)
      |> assign(:thread_count, thread_count)
      |> assign(:section_threads, section_threads)

    ~H"""
    <div class={[
      "rounded-lg border bg-base-100 overflow-hidden transition-all",
      diff_border_class(@diff_status) || "border-base-content/10",
      @diff_status && "shadow-sm"
    ]}>
      <%!-- Section header --%>
      <div
        class={[
          "flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-base-200/30 transition-colors",
          @diff_status && diff_header_bg(@diff_status)
        ]}
        phx-click="toggle_section"
        phx-value-section-id={@section.id}
      >
        <.icon
          name={if @collapsed, do: "hero-chevron-right", else: "hero-chevron-down"}
          class="h-4 w-4 text-base-content/50"
        />

        <div class="flex-1 min-w-0">
          <h3 class="font-semibold text-base">{@section.name}</h3>
          <p
            :if={@section.description && @collapsed}
            class="text-xs text-base-content/50 truncate mt-0.5"
          >
            {@section.description}
          </p>
        </div>

        <div class="flex items-center gap-2">
          <span :if={length(@section.steps) > 0} class="text-xs text-base-content/50">
            {length(@section.steps)} steps
          </span>
          <.diff_badge :if={@diff_status} status={@diff_status} />
          <.comment_indicator count={@thread_count} anchor_type="section" anchor_id={@section.id} />
        </div>
      </div>

      <%!-- Inline threads for section --%>
      <.inline_threads
        :if={length(@section_threads) > 0}
        threads={@section_threads}
        selected_thread={@selected_thread}
      />

      <%!-- Section content --%>
      <div :if={!@collapsed} class="border-t border-base-content/5">
        <p
          :if={@section.description}
          class="text-sm text-base-content/60 px-4 py-3 bg-base-200/20"
        >
          {@section.description}
        </p>

        <div class="p-4 space-y-3">
          <%= for step <- @section.steps do %>
            <.step_card
              step={step}
              diff_status_map={@diff_status_map}
              thread_counts={@thread_counts}
              all_threads={@all_threads}
              selected_thread={@selected_thread}
            />
          <% end %>

          <div
            :if={Enum.empty?(@section.steps)}
            class="text-center py-6 text-base-content/40 text-sm"
          >
            <.icon name="hero-document" class="h-6 w-6 mx-auto mb-2 opacity-50" />
            No steps in this section
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp step_card(assigns) do
    diff_status = Map.get(assigns.diff_status_map, assigns.step.id)
    thread_count = Map.get(assigns.thread_counts, {:step, assigns.step.id}, 0)

    # Filter threads for this step
    step_threads =
      assigns.all_threads
      |> Enum.filter(&(&1.anchor_type == :step && &1.anchor_id == assigns.step.id))

    assigns =
      assigns
      |> assign(:diff_status, diff_status)
      |> assign(:thread_count, thread_count)
      |> assign(:step_threads, step_threads)

    ~H"""
    <div class={[
      "rounded-lg bg-base-200 border-l-4 overflow-hidden",
      diff_border_class(@diff_status) || "border-base-300"
    ]}>
      <div class="p-4">
        <div class="flex items-center gap-3">
          <span class="badge badge-ghost badge-sm">{@step.position + 1}</span>
          <span class="font-medium">{@step.title || @step.name}</span>

          <div class="flex-1" />

          <.diff_badge :if={@diff_status} status={@diff_status} />

          <.comment_indicator count={@thread_count} anchor_type="step" anchor_id={@step.id} />
        </div>

        <%!-- Blocks --%>
        <div :if={length(@step.blocks) > 0} class="mt-3 space-y-2">
          <%= for block <- @step.blocks do %>
            <.block_card
              block={block}
              diff_status_map={@diff_status_map}
              thread_counts={@thread_counts}
              all_threads={@all_threads}
              selected_thread={@selected_thread}
            />
          <% end %>
        </div>
      </div>

      <%!-- Inline threads for step --%>
      <.inline_threads
        :if={length(@step_threads) > 0}
        threads={@step_threads}
        selected_thread={@selected_thread}
      />
    </div>
    """
  end

  defp block_card(assigns) do
    diff_status = Map.get(assigns.diff_status_map, assigns.block.id)
    thread_count = Map.get(assigns.thread_counts, {:block, assigns.block.id}, 0)

    # Filter threads for this block
    block_threads =
      assigns.all_threads
      |> Enum.filter(&(&1.anchor_type == :block && &1.anchor_id == assigns.block.id))

    assigns =
      assigns
      |> assign(:diff_status, diff_status)
      |> assign(:thread_count, thread_count)
      |> assign(:block_threads, block_threads)

    ~H"""
    <div class={[
      "rounded bg-base-100 border-l-2 overflow-hidden",
      diff_border_class(@diff_status) || "border-base-300"
    ]}>
      <div class="p-3 flex items-start gap-3">
        <span class="badge badge-outline badge-xs mt-0.5">
          {Phoenix.Naming.humanize(@block.block_type)}
        </span>

        <div class="flex-1 text-sm">
          <span :if={@block.label} class="font-medium">{@block.label}</span>
          <span :if={@block.name && !@block.label} class="text-base-content/70">{@block.name}</span>
          <.block_content_preview block={@block} />
        </div>

        <.diff_badge :if={@diff_status} status={@diff_status} size="xs" />

        <.comment_indicator
          count={@thread_count}
          anchor_type="block"
          anchor_id={@block.id}
          size="xs"
        />
      </div>

      <%!-- Inline threads for block --%>
      <.inline_threads
        :if={length(@block_threads) > 0}
        threads={@block_threads}
        selected_thread={@selected_thread}
        compact={true}
      />
    </div>
    """
  end

  defp block_content_preview(assigns) do
    ~H"""
    <div class="text-base-content/60 text-xs mt-1 truncate max-w-md">
      <%= case @block.block_type do %>
        <% :text -> %>
          {Map.get(@block.content, "markdown", "") |> String.slice(0, 100)}
        <% :telemetry_check -> %>
          Check: {Map.get(@block.content, "item", "?")}
        <% :telemetry_value -> %>
          Display: {Map.get(@block.content, "item", "?")}
        <% :command -> %>
          Command: {Map.get(@block.content, "command_name", "?")}
        <% _ -> %>
          <%!-- No preview for other types --%>
      <% end %>
    </div>
    """
  end

  defp diff_badge(assigns) do
    assigns = assign_new(assigns, :size, fn -> "sm" end)

    {text, class} =
      case assigns.status do
        :added -> {"Added", "badge-success"}
        :removed -> {"Removed", "badge-error"}
        :modified -> {"Modified", "badge-warning"}
        :moved -> {"Moved", "badge-info"}
        _ -> {nil, nil}
      end

    assigns = assign(assigns, text: text, class: class)

    ~H"""
    <span :if={@text} class={"badge badge-#{@size} #{@class}"}>{@text}</span>
    """
  end

  defp comment_indicator(assigns) do
    assigns = assign_new(assigns, :size, fn -> "sm" end)

    ~H"""
    <button
      :if={@count > 0}
      phx-click="start_new_thread"
      phx-value-anchor-type={@anchor_type}
      phx-value-anchor-id={@anchor_id}
      class={"btn btn-ghost btn-#{@size} gap-1"}
    >
      <.icon name="hero-chat-bubble-left" class="h-4 w-4" />
      <span>{@count}</span>
    </button>
    <button
      :if={@count == 0}
      phx-click="start_new_thread"
      phx-value-anchor-type={@anchor_type}
      phx-value-anchor-id={@anchor_id}
      class={"btn btn-ghost btn-#{@size} opacity-30 hover:opacity-100"}
    >
      <.icon name="hero-chat-bubble-left" class="h-4 w-4" />
    </button>
    """
  end

  defp thread_panel(assigns) do
    ~H"""
    <div class="w-96 border-l border-primary/20 bg-surface-raised flex flex-col h-full fixed right-0 top-16 shadow-xl">
      <%!-- Header --%>
      <div class="flex items-center gap-2 px-4 py-3 border-b border-primary/10 bg-base-200/30">
        <div class="p-1.5 rounded bg-primary/10">
          <.icon
            name={if @selected_thread, do: "hero-chat-bubble-left-right", else: "hero-plus-circle"}
            class="h-4 w-4 text-primary"
          />
        </div>
        <h3 class="font-semibold flex-1 text-sm uppercase tracking-wide">
          {if @selected_thread, do: "Thread Discussion", else: "New Comment"}
        </h3>
        <button phx-click="close_thread_panel" class="btn btn-ghost btn-sm btn-circle">
          <.icon name="hero-x-mark" class="h-4 w-4" />
        </button>
      </div>

      <%!-- Content --%>
      <div class="flex-1 overflow-y-auto p-4">
        <%= if @selected_thread do %>
          <.thread_view thread={@selected_thread} />
        <% else %>
          <.new_thread_form anchor={@new_thread_anchor} />
        <% end %>
      </div>
    </div>
    """
  end

  defp thread_view(assigns) do
    is_blocking = not is_nil(assigns.thread.review_id)
    assigns = assign(assigns, :is_blocking, is_blocking)

    ~H"""
    <div class="space-y-4">
      <%!-- Blocking alert banner - only show for open blocking threads --%>
      <div
        :if={@is_blocking && @thread.status == :open}
        class="flex items-center gap-3 p-3 rounded-lg bg-error/10 border border-error/30"
      >
        <.icon name="hero-exclamation-triangle-solid" class="h-5 w-5 text-error shrink-0" />
        <div class="flex-1">
          <p class="text-sm font-medium text-error">Blocking Thread</p>
          <p class="text-xs text-error/80">
            This thread must be resolved before the version can be approved.
          </p>
        </div>
      </div>

      <%!-- Thread status --%>
      <div class={[
        "flex items-center gap-2 p-3 rounded-lg border",
        @is_blocking && @thread.status == :open && "bg-error/5 border-error/20",
        !(@is_blocking && @thread.status == :open) && "bg-base-200/50 border-base-content/5"
      ]}>
        <span class={[
          "badge badge-sm gap-1",
          @thread.status == :open && !@is_blocking && "badge-warning",
          @thread.status == :open && @is_blocking && "badge-error",
          @thread.status == :resolved && "badge-success"
        ]}>
          <.icon
            name={if @thread.status == :open, do: "hero-clock", else: "hero-check-circle"}
            class="h-3 w-3"
          />
          {Phoenix.Naming.humanize(@thread.status)}
        </span>
        <span :if={@is_blocking && @thread.status == :open} class="badge badge-sm badge-error gap-1">
          <.icon name="hero-exclamation-triangle" class="h-3 w-3" /> Blocking
        </span>
        <span
          :if={@is_blocking && @thread.status == :resolved}
          class="badge badge-sm badge-ghost gap-1"
        >
          <.icon name="hero-check" class="h-3 w-3" /> Was blocking
        </span>
        <div class="flex-1" />
        <span class="text-xs text-base-content/50">{length(@thread.comments)} comments</span>
      </div>

      <%!-- Comments --%>
      <div class="space-y-3">
        <%= for comment <- @thread.comments do %>
          <div class="p-3 rounded-lg bg-base-200/50 border border-base-content/5">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center text-xs font-medium text-primary">
                {comment.user.email |> String.first() |> String.upcase()}
              </div>
              <span class="font-medium text-sm flex-1">{comment.user.email}</span>
              <span class="text-xs text-base-content/40">
                {format_relative_time(comment.inserted_at)}
              </span>
            </div>
            <p class="text-sm whitespace-pre-wrap text-base-content/80 pl-8">{comment.body}</p>
          </div>
        <% end %>
      </div>

      <%!-- Add comment form --%>
      <form phx-submit="add_comment" class="mt-4 pt-4 border-t border-base-content/10">
        <textarea
          name="body"
          class="textarea textarea-bordered w-full bg-base-200/30 focus:bg-base-100"
          rows="3"
          placeholder="Add a comment..."
          required
        />
        <div class="flex gap-2 mt-3">
          <button type="submit" class="btn btn-primary btn-sm gap-1">
            <.icon name="hero-paper-airplane" class="h-3 w-3" /> Comment
          </button>
          <%= if @thread.status == :open do %>
            <button
              type="button"
              phx-click="resolve_thread"
              class="btn btn-success btn-outline btn-sm gap-1"
            >
              <.icon name="hero-check" class="h-3 w-3" /> Resolve
            </button>
          <% else %>
            <button
              type="button"
              phx-click="reopen_thread"
              class="btn btn-warning btn-outline btn-sm gap-1"
            >
              <.icon name="hero-arrow-path" class="h-3 w-3" /> Reopen
            </button>
          <% end %>
        </div>
      </form>
    </div>
    """
  end

  defp new_thread_form(assigns) do
    {anchor_type, anchor_id} = assigns.anchor

    assigns =
      assigns
      |> assign(:anchor_type, anchor_type)
      |> assign(:anchor_id, anchor_id)

    ~H"""
    <form phx-submit="create_thread" class="space-y-4">
      <div class="p-3 rounded-lg bg-base-200/50 border border-base-content/5">
        <div class="flex items-center gap-2 text-sm text-base-content/70">
          <.icon name="hero-map-pin" class="h-4 w-4 text-primary" />
          <span>Commenting on</span>
          <span class="badge badge-sm badge-primary">{Phoenix.Naming.humanize(@anchor_type)}</span>
        </div>
      </div>

      <div>
        <label class="hud-label block mb-2">Your Comment</label>
        <textarea
          name="body"
          class="textarea textarea-bordered w-full bg-base-200/30 focus:bg-base-100"
          rows="4"
          placeholder="Share your feedback or ask a question..."
          required
        />
      </div>

      <div class="flex gap-2">
        <button type="submit" class="btn btn-primary btn-sm gap-1">
          <.icon name="hero-chat-bubble-left" class="h-3 w-3" /> Start Thread
        </button>
        <button type="button" phx-click="cancel_new_thread" class="btn btn-ghost btn-sm">
          Cancel
        </button>
      </div>
    </form>
    """
  end

  # ─────────────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────────────

  defp diff_border_class(:added), do: "border-success"
  defp diff_border_class(:removed), do: "border-error"
  defp diff_border_class(:modified), do: "border-warning"
  defp diff_border_class(:moved), do: "border-info"
  defp diff_border_class(_), do: nil

  defp diff_header_bg(:added), do: "bg-success/5"
  defp diff_header_bg(:removed), do: "bg-error/5"
  defp diff_header_bg(:modified), do: "bg-warning/5"
  defp diff_header_bg(:moved), do: "bg-info/5"
  defp diff_header_bg(_), do: nil

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
