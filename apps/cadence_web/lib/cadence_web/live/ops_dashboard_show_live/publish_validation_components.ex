defmodule CadenceWeb.OpsDashboardShowLive.PublishValidationComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.VersionActionNavigation

  attr :publish_readiness, :map, default: nil
  attr :selected_publish_issue_id, :string, default: nil
  attr :dashboard_document, :any, required: true
  attr :dashboard_current_path, :string, required: true

  def publish_validation(assigns) do
    assigns =
      assign(assigns, :publish_validation, assigns.publish_readiness)
      |> assign_selected_publish_issue()

    ~H"""
    <section
      :if={@publish_validation}
      id="dashboard-publish-validation"
      data-publish-validation-status={@publish_validation.status}
      data-publish-validation-selected-issue={@selected_publish_issue_id || ""}
      data-publish-validation-selected-issue-state={@selected_publish_issue_state}
      class="space-y-2 border border-base-300/70 bg-base-100/40 p-2"
    >
      <div class="flex items-center justify-between gap-3">
        <h3 class="hud-label">Publish Check</h3>
        <div class="flex items-center gap-2">
          <button
            id="refresh-publish-readiness"
            type="button"
            phx-click="refresh_publish_readiness"
            class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus"
          >
            <.icon name="hero-arrow-path" class="h-3 w-3" /> Re-check
          </button>
          <span class={["badge badge-xs", @publish_validation.badge_class]}>
            {@publish_validation.label}
          </span>
        </div>
      </div>
      <p class="text-xs text-base-content/70">{@publish_validation.message}</p>
      <div
        id="dashboard-publish-validation-result"
        class="border border-base-300/70 bg-base-100/40 px-2 py-1.5 text-xs"
        data-publish-validation-result-state={@publish_validation.result.state}
        data-publish-validation-result-label={@publish_validation.result.label}
      >
        <p class="hud-label">{@publish_validation.result.label}</p>
        <p class="text-base-content/70">{@publish_validation.result.message}</p>
      </div>
      <.publish_validation_freshness freshness={publish_readiness_freshness(@publish_validation)} />
      <p
        :if={@selected_publish_issue_state == "resolved"}
        class="rounded border border-success/40 bg-success/10 px-2 py-1 text-xs text-success"
        data-publish-validation-selected-issue-resolved
      >
        Selected publish issue is no longer present in this check.
      </p>
      <ol :if={@publish_validation.issues != []} class="space-y-1">
        <li
          :for={issue <- @publish_validation.issues}
          id={"dashboard-publish-validation-issue-#{issue.id}"}
          data-publish-validation-issue-id={issue.id}
          data-publish-validation-issue-selected={
            if issue.id == @selected_publish_issue_id, do: "true", else: "false"
          }
          data-publish-validation-severity={issue.severity_text}
          data-publish-validation-code={issue.code}
          class={[
            "rounded border px-2 py-1 text-xs",
            if(issue.id == @selected_publish_issue_id,
              do: "border-warning/70 bg-warning/10",
              else: "border-base-300/70"
            )
          ]}
        >
          <div class="flex items-center gap-2">
            <span class={["badge badge-xs", issue.badge_class]}>
              {issue.severity_text}
            </span>
            <span class="font-mono text-base-content/80">{issue.code}</span>
            <.link
              patch={
                VersionActionNavigation.publish_validation_issue_href(
                  @dashboard_current_path,
                  issue.id
                )
              }
              class="ml-auto text-[11px] font-semibold text-primary hover:text-primary-focus"
              data-publish-validation-issue-focus-link={issue.id}
            >
              Focus
            </.link>
          </div>
          <p class="mt-1 text-base-content/80" data-publish-validation-message={issue.code}>
            {issue.message}
          </p>
          <dl
            :if={issue[:summary_rows]}
            class="mt-1 grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1 rounded border border-base-300/60 bg-base-100/50 px-2 py-1 text-base-content/70"
            data-publish-validation-summary={issue.code}
          >
            <%= for row <- issue.summary_rows do %>
              <dt class="hud-label">{row.label}</dt>
              <dd
                class="break-all font-mono"
                data-publish-validation-summary-row={row.key}
              >
                {row.value}
              </dd>
            <% end %>
          </dl>
          <.publish_validation_action
            :if={issue.action}
            action={issue.action}
            issue_code={issue.code}
            selected_publish_issue_id={issue.id}
            dashboard_document={@dashboard_document}
          />
          <dl
            :if={issue.detail_rows != []}
            class="mt-1 grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1 text-base-content/60"
          >
            <%= for row <- issue.detail_rows do %>
              <dt class="hud-label">{row.label}</dt>
              <dd class="break-all font-mono" data-publish-validation-detail={row.label}>
                {row.value}
              </dd>
            <% end %>
          </dl>
        </li>
      </ol>
    </section>
    """
  end

  defp assign_selected_publish_issue(%{assigns: %{publish_validation: nil}} = assigns) do
    assigns
    |> assign(:selected_publish_issue_state, "none")
  end

  defp assign_selected_publish_issue(assigns) do
    selected_id = assigns.selected_publish_issue_id

    state =
      cond do
        is_nil(selected_id) or selected_id == "" ->
          "none"

        Enum.any?(assigns.publish_validation.issues, &(&1.id == selected_id)) ->
          "selected"

        true ->
          "resolved"
      end

    assign(assigns, :selected_publish_issue_state, state)
  end

  defp publish_readiness_freshness(%{freshness: freshness}), do: freshness
  defp publish_readiness_freshness(_publish_readiness), do: nil

  attr :freshness, :map, default: nil

  defp publish_validation_freshness(assigns) do
    ~H"""
    <div
      :if={@freshness}
      id="dashboard-publish-validation-freshness"
      class="grid grid-cols-2 gap-2 border border-base-300/70 bg-base-100/40 px-2 py-1.5 text-xs"
      data-publish-validation-freshness-state={@freshness.state}
      data-publish-validation-freshness-reason={@freshness[:reason] || ""}
      data-publish-validation-evaluated-at={@freshness.evaluated_at}
      data-publish-validation-draft-version={@freshness.draft_version}
      data-publish-validation-summary-draft-version={@freshness.summary_draft_version}
      data-publish-validation-latest-version={@freshness.latest_version}
      data-publish-validation-published-version={@freshness.published_version}
    >
      <div>
        <p class="hud-label">evaluated</p>
        <p class="font-mono text-base-content/70">{@freshness.evaluated_at}</p>
      </div>
      <div>
        <p class="hud-label">draft state</p>
        <p class="font-mono text-base-content/70">{@freshness.state_label}</p>
      </div>
      <div :if={@freshness[:reason_label]}>
        <p class="hud-label">reason</p>
        <p class="font-mono text-base-content/70">{@freshness.reason_label}</p>
      </div>
      <p
        :if={@freshness[:message]}
        class="col-span-2 text-base-content/70"
        data-publish-validation-freshness-message
      >
        {@freshness.message}
      </p>
    </div>
    """
  end

  attr :action, :map, required: true
  attr :issue_code, :string, required: true
  attr :selected_publish_issue_id, :string, default: nil
  attr :dashboard_document, :any, required: true

  defp publish_validation_action(assigns) do
    assigns =
      assign(
        assigns,
        :href,
        VersionActionNavigation.publish_validation_action_href(
          assigns.action,
          assigns.dashboard_document,
          assigns.selected_publish_issue_id
        )
      )

    ~H"""
    <div
      class="mt-2 border-l-2 border-info/70 pl-2"
      data-publish-validation-action={@issue_code}
      data-publish-validation-action-target={@action.target}
    >
      <div class="hud-label">{@action.label}</div>
      <p class="mt-0.5 text-base-content/70">
        {@action.message}
      </p>
      <.link
        :if={@href && @action.target == "data_sources"}
        navigate={@href}
        class="mt-1 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus"
        data-publish-validation-action-link={@issue_code}
        data-publish-validation-action-href={@href}
      >
        <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" />
        Open Data Sources
      </.link>
      <.link
        :if={@href && @action.target == "dashboard_editor"}
        patch={@href}
        class="mt-1 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus"
        data-publish-validation-action-link={@issue_code}
        data-publish-validation-action-href={@href}
      >
        <.icon name="hero-pencil-square" class="h-3 w-3" />
        Open Widget Editor
      </.link>
    </div>
    """
  end
end
