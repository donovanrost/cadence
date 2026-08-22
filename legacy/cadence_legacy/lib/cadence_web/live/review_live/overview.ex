defmodule CadenceWeb.ReviewLive.Overview do
  @moduledoc """
  Review Overview page - the central hub for managing a procedure version review.

  This page provides:
  - Review status and merge readiness checklist
  - Reviewer assignments and their statuses
  - Activity timeline
  - Approve/Request Changes actions
  - Thread summary with links to inline comments

  This is the "Conversation" tab equivalent from GitHub PRs.
  The "Changes" tab shows the read-only diff with inline commenting.
  """

  use CadenceWeb, :live_view

  alias Cadence.Organizations
  alias Cadence.Procedures
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

  defp apply_action(socket, :overview, %{
         "procedure_id" => procedure_id,
         "version_id" => version_id
       }) do
    mission = socket.assigns.mission

    case load_version_for_mission(mission, procedure_id, version_id) do
      {:ok, procedure, version} ->
        load_review_data(socket, procedure, version)

      {:error, message} ->
        socket
        |> put_flash(:error, message)
        |> push_navigate(to: ~p"/missions/#{mission}/procedures")
    end
  end

  defp load_version_for_mission(mission, procedure_id, version_id) do
    with {:ok, procedure} <- get_procedure_for_mission(mission, procedure_id),
         {:ok, version} <- get_version_for_procedure(procedure, version_id) do
      {:ok, procedure, version}
    end
  end

  defp get_procedure_for_mission(mission, procedure_id) do
    case Procedures.get_procedure(procedure_id) do
      nil -> {:error, "Procedure not found"}
      procedure when procedure.mission_id == mission.id -> {:ok, procedure}
      _procedure -> {:error, "Procedure does not belong to this mission"}
    end
  end

  defp get_version_for_procedure(procedure, version_id) do
    case Procedures.get_version(version_id) do
      nil -> {:error, "Version not found"}
      version when version.procedure_id == procedure.id -> {:ok, version}
      _version -> {:error, "Version does not belong to this procedure"}
    end
  end

  defp load_review_data(socket, procedure, version) do
    # Load review status
    review_status = Procedures.get_review_status(version)

    # Load review requests (assigned reviewers)
    review_requests = Procedures.list_review_requests(version.id)

    # Load all reviews
    reviews = Procedures.list_reviews(version.id)

    # Load threads for summary
    threads = Procedures.list_threads(version.id)
    open_threads = Enum.filter(threads, &(&1.status == :open))
    blocking_threads = Enum.filter(open_threads, &(&1.review_id != nil))

    # Load activity events
    activity = build_activity_timeline(version, reviews, threads)

    # Get current user's review status
    current_user_id = socket.assigns.current_scope.user.id
    user_review = Enum.find(reviews, &(&1.user_id == current_user_id && !&1.superseded))
    user_request = Enum.find(review_requests, &(&1.reviewer_id == current_user_id))

    # Check if user is the author
    is_author =
      version.created_by_id == current_user_id || version.submitted_by_id == current_user_id

    # Build merge checklist
    merge_checklist = build_merge_checklist(review_status, blocking_threads)

    # Load available reviewers (org members not already assigned)
    assigned_reviewer_ids =
      Enum.map(review_requests, & &1.reviewer_id) ++
        Enum.map(reviews, & &1.user_id)

    available_reviewers =
      procedure.organization_id
      |> Organizations.list_organization_memberships_with_users()
      |> Enum.map(& &1.user)
      |> Enum.reject(&(&1.id in assigned_reviewer_ids || &1.id == version.created_by_id))

    socket
    |> assign(:page_title, "Review: #{procedure.name} v#{version.version_number}")
    |> assign(:procedure, procedure)
    |> assign(:version, version)
    |> assign(:review_status, review_status)
    |> assign(:review_requests, review_requests)
    |> assign(:reviews, reviews)
    |> assign(:threads, threads)
    |> assign(:open_threads, open_threads)
    |> assign(:blocking_threads, blocking_threads)
    |> assign(:activity, activity)
    |> assign(:user_review, user_review)
    |> assign(:user_request, user_request)
    |> assign(:is_author, is_author)
    |> assign(:merge_checklist, merge_checklist)
    |> assign(:available_reviewers, available_reviewers)
    |> assign(:show_add_reviewer, false)
    |> assign(:show_review_form, false)
    |> assign(:review_decision, nil)
  end

  defp build_activity_timeline(version, reviews, threads) do
    # Submission event
    submission_events =
      if version.submitted_at do
        [
          %{
            type: :submitted,
            timestamp: version.submitted_at,
            user: get_user(version.submitted_by_id),
            details: nil
          }
        ]
      else
        []
      end

    # Review events
    review_events =
      Enum.map(reviews, fn review ->
        %{
          type: :review,
          timestamp: review.inserted_at,
          user: review.user,
          details: %{decision: review.decision, body: review.body}
        }
      end)

    # Thread events (creation and resolution)
    thread_events =
      threads
      |> Enum.flat_map(fn thread ->
        events = [
          %{
            type: :thread_created,
            timestamp: thread.inserted_at,
            user: thread.author,
            details: %{anchor_type: thread.anchor_type}
          }
        ]

        if thread.status == :resolved && thread.resolved_at do
          events ++
            [
              %{
                type: :thread_resolved,
                timestamp: thread.resolved_at,
                user: get_user(thread.resolved_by_id),
                details: nil
              }
            ]
        else
          events
        end
      end)

    # Combine and sort by timestamp (newest first)
    (submission_events ++ review_events ++ thread_events)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(20)
  end

  defp get_user(nil), do: nil

  defp get_user(user_id) do
    case Cadence.Accounts.get_user(user_id) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  defp build_merge_checklist(review_status, blocking_threads) do
    [
      %{
        label: "Required approvals",
        description: "#{review_status.approved_count} of #{review_status.required}",
        passed: review_status.approved_count >= review_status.required
      },
      %{
        label: "No blocking reviews",
        description:
          if(review_status.changes_requested_count > 0,
            do: "#{review_status.changes_requested_count} requesting changes",
            else: "No change requests"
          ),
        passed: review_status.changes_requested_count == 0
      },
      %{
        label: "All blocking threads resolved",
        description:
          case blocking_threads do
            [] -> "All resolved"
            threads -> "#{Enum.count(threads)} unresolved"
          end,
        passed: blocking_threads == []
      }
    ]
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("show_review_form", %{"decision" => decision}, socket) do
    {:noreply,
     socket
     |> assign(:show_review_form, true)
     |> assign(:review_decision, String.to_existing_atom(decision))}
  end

  def handle_event("cancel_review", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_review_form, false)
     |> assign(:review_decision, nil)}
  end

  def handle_event("submit_review", %{"review" => params}, socket) do
    version = socket.assigns.version
    user_id = socket.assigns.current_scope.user.id
    decision = socket.assigns.review_decision
    body = params["body"]

    opts = if body && body != "", do: [body: body], else: []

    case Procedures.add_review(version, user_id, decision, opts) do
      {:ok, %{version: updated_version}} ->
        {:noreply,
         socket
         |> load_review_data(socket.assigns.procedure, updated_version)
         |> assign(:show_review_form, false)
         |> assign(:review_decision, nil)
         |> put_flash(:info, review_success_message(decision))}

      {:error, :cannot_review_own_work} ->
        {:noreply, put_flash(socket, :error, "You cannot review your own work")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to submit review: #{inspect(reason)}")}
    end
  end

  def handle_event("quick_approve", _params, socket) do
    version = socket.assigns.version
    user_id = socket.assigns.current_scope.user.id

    case Procedures.add_review(version, user_id, :approve) do
      {:ok, %{version: updated_version}} ->
        {:noreply,
         socket
         |> load_review_data(socket.assigns.procedure, updated_version)
         |> put_flash(:info, "Review submitted: Approved")}

      {:error, :cannot_review_own_work} ->
        {:noreply, put_flash(socket, :error, "You cannot review your own work")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to approve: #{inspect(reason)}")}
    end
  end

  def handle_event("withdraw_submission", _params, socket) do
    version = socket.assigns.version
    user_id = socket.assigns.current_scope.user.id

    case Procedures.withdraw_submission(version, user_id) do
      {:ok, updated_version} ->
        {:noreply,
         socket
         |> load_review_data(socket.assigns.procedure, updated_version)
         |> put_flash(:info, "Submission withdrawn")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to withdraw: #{inspect(reason)}")}
    end
  end

  def handle_event("publish_version", _params, socket) do
    version = socket.assigns.version
    procedure = socket.assigns.procedure
    user_id = socket.assigns.current_scope.user.id

    case Procedures.publish_version(procedure, version, user_id) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Version #{version.version_number} is now the current version")
         |> push_navigate(to: ~p"/missions/#{socket.assigns.mission}/procedures/#{procedure}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to publish: #{inspect(reason)}")}
    end
  end

  def handle_event("toggle_add_reviewer", _params, socket) do
    {:noreply, assign(socket, :show_add_reviewer, !socket.assigns.show_add_reviewer)}
  end

  def handle_event("add_reviewer", %{"reviewer_id" => reviewer_id}, socket) do
    version = socket.assigns.version
    requester_id = socket.assigns.current_scope.user.id

    case Procedures.request_review(version, requester_id, reviewer_id) do
      {:ok, _request} ->
        {:noreply,
         socket
         |> load_review_data(socket.assigns.procedure, version)
         |> assign(:show_add_reviewer, false)
         |> put_flash(:info, "Review requested")}

      {:error, :already_requested} ->
        {:noreply, put_flash(socket, :error, "Reviewer already assigned")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to request review")}
    end
  end

  defp review_success_message(:approve), do: "Review submitted: Approved"
  defp review_success_message(:request_changes), do: "Review submitted: Changes requested"

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:bare}>
      <div class="max-w-6xl mx-auto px-4 py-4">
        <%!-- Header --%>
        <div class="mb-4">
          <%!-- Breadcrumb --%>
          <nav class="flex items-center gap-2 text-sm mb-2">
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

          <%!-- Title and Status Row --%>
          <div class="flex items-start justify-between gap-2">
            <div>
              <div class="flex items-center gap-2">
                <h1 class="text-xl font-bold">{@procedure.name}</h1>
                <.version_status_badge status={@version.status} />
              </div>
              <p class="text-xs text-base-content/60">Version {@version.version_number}</p>
            </div>

            <%!-- Author Actions --%>
            <div :if={@is_author && @version.status == :in_review}>
              <button type="button" phx-click="withdraw_submission" class="btn btn-ghost btn-sm">
                Withdraw
              </button>
            </div>
          </div>

          <%!-- Tab Navigation --%>
          <div class="flex items-center gap-1 border-b border-base-content/10 mt-3">
            <.link
              patch={
                ~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{@version.id}/review"
              }
              class="tab tab-bordered tab-active"
            >
              Overview
            </.link>
            <.link
              navigate={
                ~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{@version.id}/review/changes"
              }
              class="tab tab-bordered"
            >
              Changes
              <span :if={length(@open_threads) > 0} class="badge badge-xs badge-warning ml-1">
                {length(@open_threads)}
              </span>
            </.link>
          </div>
        </div>

        <%!-- Main Content --%>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Left Column: Main Content --%>
          <div class="lg:col-span-2 space-y-6">
            <%!-- Change Summary --%>
            <.change_summary_card :if={@version.change_summary} summary={@version.change_summary} />

            <%!-- Your Review Panel --%>
            <.your_review_panel
              :if={!@is_author && @version.status in [:in_review, :changes_requested]}
              user_review={@user_review}
              show_form={@show_review_form}
              decision={@review_decision}
            />

            <%!-- Threads Summary --%>
            <.threads_summary
              threads={@threads}
              open_threads={@open_threads}
              blocking_threads={@blocking_threads}
              mission={@mission}
              procedure={@procedure}
              version={@version}
            />

            <%!-- Activity Timeline --%>
            <.activity_timeline activity={@activity} />
          </div>

          <%!-- Right Column: Sidebar --%>
          <div class="space-y-6">
            <%!-- Merge Checklist --%>
            <.merge_checklist
              checklist={@merge_checklist}
              can_merge={@review_status.can_be_approved}
              version_status={@version.status}
              is_author={@is_author}
            />

            <%!-- Reviewers --%>
            <.reviewers_panel
              review_requests={@review_requests}
              reviews={@reviews}
              review_status={@review_status}
              available_reviewers={@available_reviewers}
              show_add_reviewer={@show_add_reviewer}
              version_status={@version.status}
            />

            <%!-- Author --%>
            <.author_panel version={@version} />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Components
  # ============================================================================

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

  attr :summary, :string, required: true

  defp change_summary_card(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <div class="flex items-start gap-3">
          <.icon name="hero-document-text" class="h-5 w-5 text-primary shrink-0 mt-0.5" />
          <div>
            <h3 class="font-semibold text-sm mb-1">Change Summary</h3>
            <p class="text-sm text-base-content/80">{@summary}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :user_review, :map, default: nil
  attr :show_form, :boolean, default: false
  attr :decision, :atom, default: nil

  defp your_review_panel(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-content/10">
      <div class="card-body p-4">
        <h3 class="font-semibold flex items-center gap-2 mb-4">
          <.icon name="hero-pencil-square" class="h-5 w-5" /> Your Review
        </h3>

        <%= if @user_review do %>
          <div class="flex items-center gap-3 p-3 rounded-lg bg-base-100">
            <div class={[
              "w-8 h-8 rounded-full flex items-center justify-center",
              @user_review.decision == :approve && "bg-success/20 text-success",
              @user_review.decision == :request_changes && "bg-warning/20 text-warning"
            ]}>
              <.icon
                name={
                  if @user_review.decision == :approve,
                    do: "hero-check",
                    else: "hero-chat-bubble-left-ellipsis"
                }
                class="h-4 w-4"
              />
            </div>
            <div>
              <span class="font-medium">
                {if @user_review.decision == :approve,
                  do: "You approved",
                  else: "You requested changes"}
              </span>
              <span class="text-sm text-base-content/60 block">
                {format_relative_time(@user_review.inserted_at)}
              </span>
            </div>
          </div>
        <% else %>
          <%= if @show_form do %>
            <.review_form decision={@decision} />
          <% else %>
            <p class="text-sm text-base-content/60 mb-4">
              You haven't submitted a review yet. Review the changes and submit your feedback.
            </p>
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                phx-click="quick_approve"
                class="btn btn-success btn-sm gap-1"
              >
                <.icon name="hero-check" class="h-4 w-4" /> Approve
              </button>
              <button
                type="button"
                phx-click="show_review_form"
                phx-value-decision="request_changes"
                class="btn btn-warning btn-outline btn-sm gap-1"
              >
                <.icon name="hero-chat-bubble-left-ellipsis" class="h-4 w-4" /> Request Changes
              </button>
              <button
                type="button"
                phx-click="show_review_form"
                phx-value-decision="approve"
                class="btn btn-ghost btn-sm gap-1"
              >
                <.icon name="hero-chat-bubble-left" class="h-4 w-4" /> Approve with Comment
              </button>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :decision, :atom, required: true

  defp review_form(assigns) do
    form = to_form(%{}, as: :review)
    assigns = assign(assigns, :form, form)

    ~H"""
    <.form for={@form} phx-submit="submit_review" class="space-y-4">
      <div class="flex items-center gap-2 mb-2">
        <div class={[
          "w-6 h-6 rounded-full flex items-center justify-center",
          @decision == :approve && "bg-success/20 text-success",
          @decision == :request_changes && "bg-warning/20 text-warning"
        ]}>
          <.icon
            name={if @decision == :approve, do: "hero-check", else: "hero-chat-bubble-left-ellipsis"}
            class="h-3 w-3"
          />
        </div>
        <span class="font-medium text-sm">
          {if @decision == :approve, do: "Approving", else: "Requesting changes"}
        </span>
      </div>

      <textarea
        name="review[body]"
        class="textarea textarea-bordered w-full bg-base-100"
        rows="4"
        placeholder={
          if @decision == :approve,
            do: "Add a comment (optional)...",
            else: "Describe what changes are needed..."
        }
        required={@decision == :request_changes}
      />

      <div class="flex justify-end gap-2">
        <button type="button" phx-click="cancel_review" class="btn btn-ghost btn-sm">
          Cancel
        </button>
        <button
          type="submit"
          class={[
            "btn btn-sm gap-1",
            @decision == :approve && "btn-success",
            @decision == :request_changes && "btn-warning"
          ]}
        >
          <.icon name="hero-paper-airplane" class="h-4 w-4" /> Submit Review
        </button>
      </div>
    </.form>
    """
  end

  attr :threads, :list, required: true
  attr :open_threads, :list, required: true
  attr :blocking_threads, :list, required: true
  attr :mission, :map, required: true
  attr :procedure, :map, required: true
  attr :version, :map, required: true

  defp threads_summary(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <h3 class="font-semibold flex items-center gap-2 mb-4">
          <.icon name="hero-chat-bubble-left-right" class="h-5 w-5" /> Discussion Threads
        </h3>

        <%= if Enum.empty?(@threads) do %>
          <p class="text-sm text-base-content/60 text-center py-4">
            No comments yet. View the changes to add inline comments.
          </p>
        <% else %>
          <div class="grid grid-cols-3 gap-4 mb-4">
            <div class="text-center p-3 rounded-lg bg-base-100">
              <div class="text-2xl font-bold">{length(@threads)}</div>
              <div class="text-xs text-base-content/60">Total</div>
            </div>
            <div class="text-center p-3 rounded-lg bg-warning/10">
              <div class="text-2xl font-bold text-warning">{length(@open_threads)}</div>
              <div class="text-xs text-base-content/60">Open</div>
            </div>
            <div class="text-center p-3 rounded-lg bg-error/10">
              <div class="text-2xl font-bold text-error">{length(@blocking_threads)}</div>
              <div class="text-xs text-base-content/60">Blocking</div>
            </div>
          </div>

          <%= if length(@blocking_threads) > 0 do %>
            <div class="space-y-2">
              <h4 class="text-sm font-medium text-error flex items-center gap-1">
                <.icon name="hero-exclamation-triangle" class="h-4 w-4" /> Blocking Threads
              </h4>
              <%= for thread <- Enum.take(@blocking_threads, 3) do %>
                <.thread_preview thread={thread} />
              <% end %>
              <%= if length(@blocking_threads) > 3 do %>
                <p class="text-xs text-base-content/50 text-center">
                  +{length(@blocking_threads) - 3} more blocking threads
                </p>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :thread, :map, required: true

  defp thread_preview(assigns) do
    first_comment = get_first_comment(assigns.thread)
    assigns = assign(assigns, :first_comment, first_comment)

    ~H"""
    <div class="p-3 rounded-lg bg-base-100 border-l-2 border-error">
      <div class="flex items-center gap-2 mb-1">
        <span class="text-sm font-medium">{@thread.author.email}</span>
        <span class="badge badge-xs">{Phoenix.Naming.humanize(@thread.anchor_type)}</span>
      </div>
      <p :if={@first_comment} class="text-sm text-base-content/70 line-clamp-2">
        {@first_comment}
      </p>
    </div>
    """
  end

  defp get_first_comment(thread) do
    cond do
      is_list(thread.comments) && length(thread.comments) > 0 ->
        List.first(thread.comments).body

      thread.review && thread.review.body ->
        thread.review.body

      true ->
        nil
    end
  end

  attr :activity, :list, required: true

  defp activity_timeline(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <h3 class="font-semibold flex items-center gap-2 mb-4">
          <.icon name="hero-clock" class="h-5 w-5" /> Activity
        </h3>

        <%= if Enum.empty?(@activity) do %>
          <p class="text-sm text-base-content/60 text-center py-4">
            No activity yet.
          </p>
        <% else %>
          <div class="space-y-4">
            <%= for event <- @activity do %>
              <.activity_event event={event} />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true

  defp activity_event(assigns) do
    {icon, icon_class, text} = activity_event_display(assigns.event)

    assigns =
      assigns
      |> assign(:icon, icon)
      |> assign(:icon_class, icon_class)
      |> assign(:text, text)

    ~H"""
    <div class="flex items-start gap-3">
      <div class={["w-8 h-8 rounded-full flex items-center justify-center shrink-0", @icon_class]}>
        <.icon name={@icon} class="h-4 w-4" />
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm">
          <span :if={@event.user} class="font-medium">{@event.user.email}</span>
          <span class="text-base-content/70">{@text}</span>
        </p>
        <p :if={@event.details[:body]} class="text-sm text-base-content/60 mt-1 line-clamp-2">
          "{@event.details[:body]}"
        </p>
        <p class="text-xs text-base-content/50 mt-1">
          {format_relative_time(@event.timestamp)}
        </p>
      </div>
    </div>
    """
  end

  defp activity_event_display(%{type: :submitted}) do
    {"hero-paper-airplane", "bg-info/20 text-info", "submitted for review"}
  end

  defp activity_event_display(%{type: :review, details: %{decision: :approve}}) do
    {"hero-check-circle", "bg-success/20 text-success", "approved"}
  end

  defp activity_event_display(%{type: :review, details: %{decision: :request_changes}}) do
    {"hero-exclamation-circle", "bg-warning/20 text-warning", "requested changes"}
  end

  defp activity_event_display(%{type: :thread_created}) do
    {"hero-chat-bubble-left", "bg-base-300 text-base-content/60", "started a thread"}
  end

  defp activity_event_display(%{type: :thread_resolved}) do
    {"hero-check", "bg-success/20 text-success", "resolved a thread"}
  end

  defp activity_event_display(_) do
    {"hero-clock", "bg-base-300 text-base-content/60", "updated"}
  end

  attr :checklist, :list, required: true
  attr :can_merge, :boolean, required: true
  attr :version_status, :atom, required: true
  attr :is_author, :boolean, required: true

  defp merge_checklist(assigns) do
    all_passed = Enum.all?(assigns.checklist, & &1.passed)
    assigns = assign(assigns, :all_passed, all_passed)

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <h3 class="font-semibold flex items-center gap-2 mb-4">
          <.icon name="hero-clipboard-document-check" class="h-5 w-5" /> Merge Checklist
        </h3>

        <div class="space-y-3">
          <%= for item <- @checklist do %>
            <div class="flex items-start gap-3">
              <div class={[
                "w-5 h-5 rounded-full flex items-center justify-center shrink-0 mt-0.5",
                item.passed && "bg-success/20 text-success",
                !item.passed && "bg-base-300 text-base-content/40"
              ]}>
                <.icon
                  name={if item.passed, do: "hero-check", else: "hero-minus"}
                  class="h-3 w-3"
                />
              </div>
              <div>
                <span class={["text-sm font-medium", !item.passed && "text-base-content/60"]}>
                  {item.label}
                </span>
                <span class="text-xs text-base-content/50 block">{item.description}</span>
              </div>
            </div>
          <% end %>
        </div>

        <%= if @version_status == :approved do %>
          <div class="mt-4 pt-4 border-t border-base-content/10">
            <button
              :if={@is_author}
              type="button"
              phx-click="publish_version"
              class="btn btn-primary w-full gap-1"
            >
              <.icon name="hero-rocket-launch" class="h-4 w-4" /> Publish Version
            </button>
            <p :if={!@is_author} class="text-sm text-success text-center">
              Ready to publish
            </p>
          </div>
        <% else %>
          <div class="mt-4 pt-4 border-t border-base-content/10">
            <%= if @all_passed do %>
              <p class="text-sm text-success text-center flex items-center justify-center gap-1">
                <.icon name="hero-check-circle" class="h-4 w-4" /> Ready to merge
              </p>
            <% else %>
              <p class="text-sm text-base-content/50 text-center">
                Complete all items to merge
              </p>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :review_requests, :list, required: true
  attr :reviews, :list, required: true
  attr :review_status, :map, required: true
  attr :available_reviewers, :list, required: true
  attr :show_add_reviewer, :boolean, required: true
  attr :version_status, :atom, required: true

  defp reviewers_panel(assigns) do
    # Build a map of reviewers with their status
    reviewers =
      Enum.map(assigns.review_requests, fn request ->
        review =
          Enum.find(assigns.reviews, &(&1.user_id == request.reviewer_id && !&1.superseded))

        %{
          user: request.reviewer,
          status:
            cond do
              review && review.decision == :approve -> :approved
              review && review.decision == :request_changes -> :changes_requested
              true -> :pending
            end,
          review: review
        }
      end)

    # Add any reviewers who reviewed without a request
    additional_reviewers =
      assigns.reviews
      |> Enum.filter(fn r ->
        !r.superseded &&
          !Enum.any?(assigns.review_requests, &(&1.reviewer_id == r.user_id))
      end)
      |> Enum.map(fn review ->
        %{
          user: review.user,
          status: if(review.decision == :approve, do: :approved, else: :changes_requested),
          review: review
        }
      end)

    can_add = assigns.version_status in [:in_review, :changes_requested]

    assigns =
      assigns
      |> assign(:reviewers, reviewers ++ additional_reviewers)
      |> assign(:can_add, can_add)

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-semibold flex items-center gap-2">
            <.icon name="hero-users" class="h-5 w-5" /> Reviewers
          </h3>
          <span class="text-xs text-base-content/60">
            {@review_status.approved_count}/{@review_status.required} required
          </span>
        </div>

        <%= if Enum.empty?(@reviewers) do %>
          <p class="text-sm text-base-content/60 text-center py-2">
            No reviewers assigned
          </p>
        <% else %>
          <div class="space-y-2">
            <%= for reviewer <- @reviewers do %>
              <div class="flex items-center gap-3 p-2 rounded-lg bg-base-100">
                <div class="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center text-sm font-medium text-primary">
                  {reviewer.user.email |> String.first() |> String.upcase()}
                </div>
                <div class="flex-1 min-w-0">
                  <span class="text-sm font-medium truncate block">{reviewer.user.email}</span>
                </div>
                <.reviewer_status_icon status={reviewer.status} />
              </div>
            <% end %>
          </div>
        <% end %>

        <%!-- Add Reviewer UI --%>
        <%= if @can_add do %>
          <div class="mt-3 pt-3 border-t border-base-content/10">
            <%= if @show_add_reviewer do %>
              <div class="space-y-2">
                <%= if Enum.empty?(@available_reviewers) do %>
                  <p class="text-sm text-base-content/60 text-center py-2">
                    No more team members available
                  </p>
                <% else %>
                  <div class="space-y-1 max-h-48 overflow-y-auto">
                    <%= for user <- @available_reviewers do %>
                      <button
                        type="button"
                        phx-click="add_reviewer"
                        phx-value-reviewer_id={user.id}
                        class="flex items-center gap-3 p-2 rounded-lg bg-base-100 hover:bg-base-300 transition-colors w-full text-left"
                      >
                        <div class="w-8 h-8 rounded-full bg-base-content/10 flex items-center justify-center text-sm font-medium">
                          {user.email |> String.first() |> String.upcase()}
                        </div>
                        <span class="text-sm truncate">{user.email}</span>
                      </button>
                    <% end %>
                  </div>
                <% end %>
                <button
                  type="button"
                  phx-click="toggle_add_reviewer"
                  class="btn btn-ghost btn-xs w-full"
                >
                  Cancel
                </button>
              </div>
            <% else %>
              <button
                type="button"
                phx-click="toggle_add_reviewer"
                class="btn btn-ghost btn-sm w-full gap-1"
              >
                <.icon name="hero-plus" class="h-4 w-4" /> Add reviewer
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp reviewer_status_icon(assigns) do
    {icon, class} =
      case assigns.status do
        :approved -> {"hero-check-circle-solid", "text-success"}
        :changes_requested -> {"hero-exclamation-circle-solid", "text-warning"}
        :pending -> {"hero-clock", "text-base-content/40"}
      end

    assigns = assign(assigns, icon: icon, class: class)

    ~H"""
    <.icon name={@icon} class={"h-5 w-5 #{@class}"} />
    """
  end

  attr :version, :map, required: true

  defp author_panel(assigns) do
    author = get_user(assigns.version.created_by_id)
    submitter = get_user(assigns.version.submitted_by_id)
    assigns = assign(assigns, author: author, submitter: submitter)

    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <h3 class="font-semibold flex items-center gap-2 mb-4">
          <.icon name="hero-user" class="h-5 w-5" /> Author
        </h3>

        <div :if={@author} class="flex items-center gap-3">
          <div class="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center text-sm font-medium text-primary">
            {@author.email |> String.first() |> String.upcase()}
          </div>
          <div>
            <span class="text-sm font-medium">{@author.email}</span>
            <span class="text-xs text-base-content/50 block">Created version</span>
          </div>
        </div>

        <div
          :if={@submitter && @author && @submitter.id != @author.id}
          class="flex items-center gap-3 mt-3 pt-3 border-t border-base-content/10"
        >
          <div class="w-8 h-8 rounded-full bg-info/20 flex items-center justify-center text-sm font-medium text-info">
            {@submitter.email |> String.first() |> String.upcase()}
          </div>
          <div>
            <span class="text-sm font-medium">{@submitter.email}</span>
            <span class="text-xs text-base-content/50 block">Submitted for review</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp format_relative_time(nil), do: ""

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
