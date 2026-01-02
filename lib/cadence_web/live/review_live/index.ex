defmodule CadenceWeb.ReviewLive.Index do
  @moduledoc """
  Global reviews inbox page.

  Provides a cross-mission view of all review-related activity for the current user,
  similar to GitHub's pull request inbox. Includes:

  - **Requested Reviews**: Versions awaiting review from this user
  - **Awaiting Re-review**: Versions where user requested changes and author resubmitted
  - **Your Submissions**: Versions authored by this user
  - **Recent Activity**: Past reviews the user participated in
  """

  use CadenceWeb, :live_view

  alias Cadence.Reviews
  alias CadenceWeb.MissionLive.Procedures.Components

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    organization_id = socket.assigns.current_scope.current_organization.id

    # Load all inbox data
    requested = Reviews.list_requested_reviews(user_id, organization_id: organization_id, limit: 20)
    awaiting = Reviews.list_awaiting_rereview(user_id, organization_id: organization_id, limit: 20)
    submissions = Reviews.list_user_submissions(user_id, organization_id: organization_id, limit: 20)
    activity = Reviews.list_recent_activity(user_id, organization_id: organization_id, limit: 20)
    counts = Reviews.get_inbox_counts(user_id, organization_id: organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Reviews")
     |> assign(:requested_reviews, requested)
     |> assign(:awaiting_rereview, awaiting)
     |> assign(:submissions, submissions)
     |> assign(:recent_activity, activity)
     |> assign(:counts, counts)
     |> assign(:active_section, :requested)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    section = parse_section(params["section"])
    {:noreply, assign(socket, :active_section, section)}
  end

  defp parse_section("awaiting"), do: :awaiting
  defp parse_section("submissions"), do: :submissions
  defp parse_section("activity"), do: :activity
  defp parse_section(_), do: :requested

  # ==========================================================================
  # Render
  # ==========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Reviews
      <:subtitle>
        Your review inbox across all missions
      </:subtitle>
    </.header>

    <div class="mt-6">
      <%!-- Section Tabs --%>
      <div class="tabs tabs-boxed bg-base-200 p-1 mb-6">
        <.link
          patch={~p"/reviews"}
          class={["tab", @active_section == :requested && "tab-active"]}
        >
          Requested
          <span :if={@counts.pending_requests > 0} class="badge badge-sm badge-primary ml-2">
            {@counts.pending_requests}
          </span>
        </.link>
        <.link
          patch={~p"/reviews?section=awaiting"}
          class={["tab", @active_section == :awaiting && "tab-active"]}
        >
          Awaiting Re-review
          <span :if={@counts.awaiting_rereview > 0} class="badge badge-sm badge-warning ml-2">
            {@counts.awaiting_rereview}
          </span>
        </.link>
        <.link
          patch={~p"/reviews?section=submissions"}
          class={["tab", @active_section == :submissions && "tab-active"]}
        >
          Your Submissions
          <span :if={@counts.active_submissions > 0} class="badge badge-sm badge-info ml-2">
            {@counts.active_submissions}
          </span>
        </.link>
        <.link
          patch={~p"/reviews?section=activity"}
          class={["tab", @active_section == :activity && "tab-active"]}
        >
          Recent Activity
        </.link>
      </div>

      <%!-- Section Content --%>
      <%= case @active_section do %>
        <% :requested -> %>
          <.requested_reviews_section items={@requested_reviews} />
        <% :awaiting -> %>
          <.awaiting_rereview_section items={@awaiting_rereview} />
        <% :submissions -> %>
          <.submissions_section items={@submissions} />
        <% :activity -> %>
          <.activity_section items={@recent_activity} />
      <% end %>
    </div>
    """
  end

  # ==========================================================================
  # Section Components
  # ==========================================================================

  attr :items, :list, required: true

  defp requested_reviews_section(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold">Requested Reviews</h2>
        <span class="text-sm text-base-content/60">{length(@items)} pending</span>
      </div>

      <%= if Enum.empty?(@items) do %>
        <.empty_state
          icon="hero-inbox"
          title="No pending reviews"
          description="You're all caught up! No one has requested a review from you."
        />
      <% else %>
        <div class="space-y-3">
          <.review_request_card :for={item <- @items} item={item} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :items, :list, required: true

  defp awaiting_rereview_section(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold">Awaiting Re-review</h2>
        <span class="text-sm text-base-content/60">{length(@items)} awaiting</span>
      </div>

      <%= if Enum.empty?(@items) do %>
        <.empty_state
          icon="hero-arrow-path"
          title="No re-reviews needed"
          description="Authors haven't responded to your change requests yet."
        />
      <% else %>
        <div class="space-y-3">
          <.rereview_card :for={item <- @items} item={item} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :items, :list, required: true

  defp submissions_section(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold">Your Submissions</h2>
        <span class="text-sm text-base-content/60">{length(@items)} versions</span>
      </div>

      <%= if Enum.empty?(@items) do %>
        <.empty_state
          icon="hero-document-text"
          title="No submissions"
          description="You haven't submitted any procedure versions for review."
        />
      <% else %>
        <div class="space-y-3">
          <.submission_card :for={item <- @items} item={item} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :items, :list, required: true

  defp activity_section(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold">Recent Activity</h2>
        <span class="text-sm text-base-content/60">{length(@items)} events</span>
      </div>

      <%= if Enum.empty?(@items) do %>
        <.empty_state
          icon="hero-clock"
          title="No recent activity"
          description="Your review activity will appear here."
        />
      <% else %>
        <div class="space-y-3">
          <.activity_card :for={item <- @items} item={item} />
        </div>
      <% end %>
    </div>
    """
  end

  # ==========================================================================
  # Card Components
  # ==========================================================================

  attr :item, :map, required: true

  defp review_request_card(assigns) do
    ~H"""
    <div class="card bg-base-200 hover:bg-base-200/80 transition-colors">
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <span class="font-semibold truncate">{@item.version.procedure.name}</span>
              <span class="text-sm text-base-content/60">v{@item.version.version_number}</span>
              <Components.version_status_badge status={@item.version.status} />
            </div>
            <p class="text-sm text-base-content/60 mb-2">
              Requested by <span class="font-medium">{@item.request.requester.email}</span>
              {if @item.request.message, do: " · \"#{@item.request.message}\"", else: ""}
            </p>
            <div class="flex items-center gap-4 text-xs text-base-content/50">
              <span class="flex items-center gap-1">
                <.icon name="hero-clock" class="h-3.5 w-3.5" />
                Waiting {format_wait_time(@item.wait_time)}
              </span>
              <span class="flex items-center gap-1">
                <.icon name="hero-rocket-launch" class="h-3.5 w-3.5" />
                {mission_name(@item.version.procedure)}
              </span>
            </div>
          </div>
          <.link
            navigate={procedure_path(@item.version)}
            class="btn btn-primary btn-sm shrink-0"
          >
            Review
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp rereview_card(assigns) do
    ~H"""
    <div class="card bg-base-200 hover:bg-base-200/80 transition-colors border-l-4 border-warning">
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <span class="font-semibold truncate">{@item.version.procedure.name}</span>
              <span class="text-sm text-base-content/60">v{@item.version.version_number}</span>
              <span class="badge badge-sm badge-warning">Resubmitted</span>
            </div>
            <p class="text-sm text-base-content/60 mb-2">
              You requested changes · Author has addressed them
            </p>
            <div class="flex items-center gap-4 text-xs text-base-content/50">
              <span :if={@item.resubmitted_at} class="flex items-center gap-1">
                <.icon name="hero-arrow-path" class="h-3.5 w-3.5" />
                Resubmitted {format_relative_time(@item.resubmitted_at)}
              </span>
              <span class="flex items-center gap-1">
                <.icon name="hero-rocket-launch" class="h-3.5 w-3.5" />
                {mission_name(@item.version.procedure)}
              </span>
            </div>
          </div>
          <.link
            navigate={procedure_path(@item.version)}
            class="btn btn-warning btn-sm shrink-0"
          >
            Re-review
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp submission_card(assigns) do
    ~H"""
    <div class="card bg-base-200 hover:bg-base-200/80 transition-colors">
      <div class="card-body p-4">
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <span class="font-semibold truncate">{@item.version.procedure.name}</span>
              <span class="text-sm text-base-content/60">v{@item.version.version_number}</span>
              <Components.version_status_badge status={@item.status} />
            </div>
            <div class="flex items-center gap-4 text-sm text-base-content/60 mb-2">
              <span :if={@item.review_summary}>
                <span class="text-success">{@item.review_summary.approved_count}</span> approved
                <span :if={@item.review_summary.changes_requested_count > 0}>
                  · <span class="text-warning">{@item.review_summary.changes_requested_count}</span> requesting changes
                </span>
              </span>
            </div>
            <div class="flex items-center gap-4 text-xs text-base-content/50">
              <span class="flex items-center gap-1">
                <.icon name="hero-rocket-launch" class="h-3.5 w-3.5" />
                {mission_name(@item.version.procedure)}
              </span>
            </div>
          </div>
          <.link
            navigate={procedure_path(@item.version)}
            class="btn btn-ghost btn-sm shrink-0"
          >
            View
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp activity_card(assigns) do
    ~H"""
    <div class="card bg-base-200/50">
      <div class="card-body p-4">
        <div class="flex items-start gap-3">
          <%!-- Activity icon --%>
          <div class={[
            "w-8 h-8 rounded-full flex items-center justify-center shrink-0",
            activity_icon_class(@item.type, @item.review.decision)
          ]}>
            <.icon name={activity_icon(@item.type, @item.review.decision)} class="h-4 w-4" />
          </div>

          <div class="flex-1 min-w-0">
            <p class="text-sm">
              <span class="font-medium">{@item.review.user.email}</span>
              <span class="text-base-content/70">
                {activity_verb(@item.type, @item.review.decision)}
              </span>
              <.link
                navigate={procedure_path(@item.version)}
                class="font-medium hover:text-primary"
              >
                {@item.version.procedure.name} v{@item.version.version_number}
              </.link>
            </p>
            <p :if={@item.review.body} class="text-sm text-base-content/60 mt-1 line-clamp-2">
              "{@item.review.body}"
            </p>
            <p class="text-xs text-base-content/50 mt-1">
              {format_relative_time(@item.timestamp)}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ==========================================================================
  # Empty State
  # ==========================================================================

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body items-center text-center py-12">
        <.icon name={@icon} class="h-12 w-12 text-base-content/30" />
        <h3 class="font-semibold mt-4">{@title}</h3>
        <p class="text-base-content/60 max-w-sm">{@description}</p>
      </div>
    </div>
    """
  end

  # ==========================================================================
  # Helpers
  # ==========================================================================

  defp procedure_path(version) do
    procedure = version.procedure
    mission_id = procedure.mission_id
    # Link to the new Review Overview page
    ~p"/missions/#{mission_id}/procedures-v2/#{procedure.id}/versions/#{version.id}/review"
  end

  defp mission_name(procedure) do
    # The procedure should have mission preloaded, but fallback if not
    if procedure.mission do
      procedure.mission.name
    else
      "Mission"
    end
  end

  defp format_wait_time(seconds) when seconds < 60, do: "just now"
  defp format_wait_time(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"
  defp format_wait_time(seconds) when seconds < 86_400, do: "#{div(seconds, 3600)}h"
  defp format_wait_time(seconds), do: "#{div(seconds, 86_400)}d"

  defp format_relative_time(nil), do: ""

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp activity_icon("review", :approve), do: "hero-check-circle"
  defp activity_icon("review", :request_changes), do: "hero-exclamation-circle"
  defp activity_icon("received_review", :approve), do: "hero-check-circle"
  defp activity_icon("received_review", :request_changes), do: "hero-exclamation-circle"
  defp activity_icon(_, _), do: "hero-chat-bubble-left"

  defp activity_icon_class("review", :approve), do: "bg-success/20 text-success"
  defp activity_icon_class("review", :request_changes), do: "bg-warning/20 text-warning"
  defp activity_icon_class("received_review", :approve), do: "bg-success/20 text-success"
  defp activity_icon_class("received_review", :request_changes), do: "bg-warning/20 text-warning"
  defp activity_icon_class(_, _), do: "bg-base-300 text-base-content/60"

  defp activity_verb("review", :approve), do: "approved"
  defp activity_verb("review", :request_changes), do: "requested changes on"
  defp activity_verb("received_review", :approve), do: "approved your"
  defp activity_verb("received_review", :request_changes), do: "requested changes on your"
  defp activity_verb(_, _), do: "reviewed"
end
