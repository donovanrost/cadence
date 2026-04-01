defmodule CadenceWeb.MissionLive.Procedures.Components do
  @moduledoc """
  Shared components for the Procedures UI.

  Provides reusable procedure card, status badges, and tag components
  used across the procedures list and detail views.
  """

  use Phoenix.Component
  use CadenceWeb, :verified_routes

  import CadenceWeb.CoreComponents

  # ==========================================================================
  # Status Badge
  # ==========================================================================

  @doc """
  Renders a status badge for a procedure version.

  The badge shows the current workflow status with appropriate coloring:
  - draft: neutral/ghost
  - in_review: info/blue
  - changes_requested: warning/yellow
  - approved: success/green
  - closed: neutral/gray
  - deprecated: error/red

  ## Examples

      <.version_status_badge status={:draft} />
      <.version_status_badge status={:approved} />
  """
  attr :status, :atom, required: true
  attr :class, :string, default: nil

  def version_status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm font-medium",
      status_color(@status),
      @class
    ]}>
      {status_label(@status)}
    </span>
    """
  end

  defp status_color(:draft), do: "badge-ghost"
  defp status_color(:in_review), do: "badge-info"
  defp status_color(:changes_requested), do: "badge-warning"
  defp status_color(:approved), do: "badge-success"
  defp status_color(:closed), do: "badge-ghost text-base-content/50"
  defp status_color(:deprecated), do: "badge-error"
  defp status_color(_), do: "badge-ghost"

  defp status_label(:draft), do: "Draft"
  defp status_label(:in_review), do: "In Review"
  defp status_label(:changes_requested), do: "Changes Requested"
  defp status_label(:approved), do: "Approved"
  defp status_label(:closed), do: "Closed"
  defp status_label(:deprecated), do: "Deprecated"
  defp status_label(_), do: "Unknown"

  # ==========================================================================
  # Approval Progress Badge
  # ==========================================================================

  # Renders a compact approval progress badge showing approvals received out of total reviews.
  # Green when all reviews are approvals, outline otherwise.
  attr :approved, :integer, required: true
  attr :total, :integer, required: true

  defp approval_progress_badge(assigns) do
    ~H"""
    <span
      :if={@total > 0}
      class={[
        "badge badge-sm gap-1",
        @approved > 0 && @approved == @total && "badge-success",
        @approved > 0 && @approved < @total && "badge-outline badge-info",
        @approved == 0 && "badge-outline"
      ]}
      title={"#{@approved} of #{@total} approvals"}
    >
      <.icon name="hero-check" class="h-3 w-3" />
      {@approved}/{@total}
    </span>
    """
  end

  # ==========================================================================
  # Tag Badge
  # ==========================================================================

  @doc """
  Renders a clickable tag badge.

  When clicked, emits a phx-click event to filter by this tag.

  ## Examples

      <.tag_badge tag="thermal" />
      <.tag_badge tag="recovery" selected={true} />
  """
  attr :tag, :string, required: true
  attr :selected, :boolean, default: false
  attr :on_click, :string, default: "toggle_tag"

  def tag_badge(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@on_click}
      phx-value-tag={@tag}
      class={[
        "badge cursor-pointer transition-all hover:scale-105",
        @selected && "badge-primary",
        !@selected && "badge-outline hover:badge-primary hover:badge-outline"
      ]}
    >
      {@tag}
    </button>
    """
  end

  # ==========================================================================
  # Procedure Card
  # ==========================================================================

  @doc """
  Renders a procedure card for the list view.

  Displays:
  - Procedure name and description
  - Tags as badges
  - Current version status
  - Running execution count (if any)
  - Edit and Execute action buttons

  ## Examples

      <.procedure_card
        procedure={@procedure}
        mission={@mission}
        execution_count={2}
        on_tag_click="toggle_tag"
      />
  """
  attr :procedure, :map, required: true
  attr :mission, :map, required: true
  attr :execution_count, :integer, default: 0
  attr :current_version_status, :atom, default: nil
  attr :approval_progress, :map, default: nil
  attr :selected_tags, :list, default: []
  attr :on_tag_click, :string, default: "toggle_tag"

  def procedure_card(assigns) do
    ~H"""
    <div class="card bg-base-200 hover:bg-base-200/80 transition-colors shadow-sm">
      <div class="card-body p-4 gap-3">
        <%!-- Header: Name + Status + Execution Count --%>
        <div class="flex items-start justify-between gap-3">
          <div class="flex-1 min-w-0">
            <.link
              navigate={~p"/missions/#{@mission}/procedures/#{@procedure.id}"}
              class="text-base font-semibold hover:text-primary transition-colors line-clamp-1"
            >
              {@procedure.name}
            </.link>
          </div>

          <div class="flex items-center gap-2 shrink-0">
            <%!-- Running executions badge --%>
            <span
              :if={@execution_count > 0}
              class="badge badge-sm badge-success gap-1"
              title={"#{@execution_count} running"}
            >
              <.icon name="hero-play-solid" class="h-3 w-3" />
              {@execution_count}
            </span>

            <%!-- Approval progress badge --%>
            <.approval_progress_badge
              :if={@approval_progress}
              approved={@approval_progress.approved}
              total={@approval_progress.total_reviews}
            />

            <%!-- Version status --%>
            <.version_status_badge :if={@current_version_status} status={@current_version_status} />
          </div>
        </div>

        <%!-- Description --%>
        <p
          :if={@procedure.description && @procedure.description != ""}
          class="text-sm text-base-content/70 line-clamp-2"
        >
          {@procedure.description}
        </p>
        <p
          :if={!@procedure.description || @procedure.description == ""}
          class="text-sm text-base-content/40 italic"
        >
          No description
        </p>

        <%!-- Tags --%>
        <div :if={@procedure.tags && length(@procedure.tags) > 0} class="flex flex-wrap gap-1.5">
          <.tag_badge
            :for={tag <- @procedure.tags}
            tag={tag}
            selected={tag in @selected_tags}
            on_click={@on_tag_click}
          />
        </div>

        <%!-- Actions --%>
        <div class="card-actions justify-end mt-1">
          <.link
            :if={@procedure.current_version_id}
            navigate={
              ~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{@procedure.current_version_id}/edit"
            }
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-pencil-square" class="h-4 w-4" /> Edit
          </.link>
          <.link
            navigate={~p"/missions/#{@mission}/procedures/#{@procedure.id}/execute"}
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-play" class="h-4 w-4" /> Execute
          </.link>
        </div>
      </div>
    </div>
    """
  end

  # ==========================================================================
  # Empty State
  # ==========================================================================

  @doc """
  Renders an empty state when no procedures match the current filters.
  """
  attr :search_query, :string, default: ""
  attr :selected_tags, :list, default: []
  attr :on_clear, :string, default: "clear_filters"

  def empty_state(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body items-center text-center py-12">
        <.icon name="hero-document-text" class="h-12 w-12 text-base-content/30" />
        <h3 class="text-lg font-semibold mt-4">No procedures found</h3>
        <p class="text-base-content/60 max-w-sm">
          <%= cond do %>
            <% @search_query != "" and length(@selected_tags) > 0 -> %>
              No procedures match your search and selected tags.
            <% @search_query != "" -> %>
              No procedures match your search query.
            <% length(@selected_tags) > 0 -> %>
              No procedures have all selected tags.
            <% true -> %>
              This mission doesn't have any procedures yet.
          <% end %>
        </p>
        <button
          :if={@search_query != "" or length(@selected_tags) > 0}
          type="button"
          phx-click={@on_clear}
          class="btn btn-ghost btn-sm mt-2"
        >
          Clear filters
        </button>
      </div>
    </div>
    """
  end

  # ==========================================================================
  # Stats Bar
  # ==========================================================================

  @doc """
  Renders a stats bar showing procedure counts and execution status.
  """
  attr :total_count, :integer, required: true
  attr :running_count, :integer, default: 0
  attr :paused_count, :integer, default: 0

  def stats_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-4 text-sm text-base-content/70">
      <span>{@total_count} {if @total_count == 1, do: "procedure", else: "procedures"}</span>
      <span :if={@running_count > 0} class="flex items-center gap-1 text-success">
        <.icon name="hero-play-solid" class="h-3.5 w-3.5" />
        {@running_count} running
      </span>
      <span :if={@paused_count > 0} class="flex items-center gap-1 text-warning">
        <.icon name="hero-pause-solid" class="h-3.5 w-3.5" />
        {@paused_count} paused
      </span>
    </div>
    """
  end
end
