defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowEvents
  alias Phoenix.LiveView.Socket

  test "open_request delegates to workflow opener" do
    socket =
      socket()
      |> HistoricalWorkflowEvents.open_request(
        open_request: fn socket ->
          assign(socket, :workflow_event, :open_request)
        end
      )

    assert socket.assigns.workflow_event == :open_request
  end

  test "open_comparison_review_request delegates params and opts" do
    opts = [
      open_comparison_review_request: fn socket, params ->
        assign(
          socket,
          :workflow_event,
          {:comparison_review_request, params}
        )
      end
    ]

    socket =
      HistoricalWorkflowEvents.open_comparison_review_request(
        socket(),
        %{"request-event-id" => "event-1"},
        opts
      )

    assert socket.assigns.workflow_event ==
             {:comparison_review_request, %{"request-event-id" => "event-1"}}
  end

  test "record_stage delegates params and opts" do
    opts = [
      record_stage_event: fn socket, params, opts ->
        assign(socket, :workflow_event, {:stage, params, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket = HistoricalWorkflowEvents.record_stage(socket(), %{"stage" => "started"}, opts)

    assert socket.assigns.workflow_event == {:stage, %{"stage" => "started"}, :ok}
  end

  test "record_group_stage delegates params and opts" do
    opts = [
      record_group_stage_event: fn socket, params, opts ->
        assign(socket, :workflow_event, {:group_stage, params, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket = HistoricalWorkflowEvents.record_group_stage(socket(), %{"stage" => "approved"}, opts)

    assert socket.assigns.workflow_event == {:group_stage, %{"stage" => "approved"}, :ok}
  end

  test "record_request delegates params and opts" do
    opts = [
      record_request_event: fn socket, params, opts ->
        assign(socket, :workflow_event, {:request, params, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket = HistoricalWorkflowEvents.record_request(socket(), %{"workflow" => "backfill"}, opts)

    assert socket.assigns.workflow_event == {:request, %{"workflow" => "backfill"}, :ok}
  end

  test "record_correction_request delegates params and opts" do
    opts = [
      record_correction_request_event: fn socket, params, opts ->
        assign(socket, :workflow_event, {:correction, params, Keyword.fetch!(opts, :sentinel)})
      end,
      sentinel: :ok
    ]

    socket =
      HistoricalWorkflowEvents.record_correction_request(
        socket(),
        %{"workflow" => "backfill"},
        opts
      )

    assert socket.assigns.workflow_event == {:correction, %{"workflow" => "backfill"}, :ok}
  end

  test "retry_job delegates ids and opts" do
    opts = [
      retry_job_event: fn socket, job_id, event_id, opts ->
        assign(
          socket,
          :workflow_event,
          {:retry_job, job_id, event_id, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket = HistoricalWorkflowEvents.retry_job(socket(), "job-1", "event-1", opts)

    assert socket.assigns.workflow_event == {:retry_job, "job-1", "event-1", :ok}
  end

  test "inspect_stale_replacement_job delegates ids and opts" do
    opts = [
      inspect_stale_replacement_job_event: fn socket, job_id, event_id, opts ->
        assign(
          socket,
          :workflow_event,
          {:inspect_stale_replacement_job, job_id, event_id, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket =
      HistoricalWorkflowEvents.inspect_stale_replacement_job(socket(), "job-1", "event-1", opts)

    assert socket.assigns.workflow_event ==
             {:inspect_stale_replacement_job, "job-1", "event-1", :ok}
  end

  test "inspect_missing_replacement_job delegates group and replacement run ids and opts" do
    opts = [
      sentinel: :ok,
      inspect_missing_replacement_job_event: fn socket,
                                                request_group_id,
                                                replacement_run_id,
                                                opts ->
        send(
          self(),
          {:inspect_missing_replacement_job, request_group_id, replacement_run_id,
           Keyword.fetch!(opts, :sentinel)}
        )

        socket
      end
    ]

    HistoricalWorkflowEvents.inspect_missing_replacement_job(
      socket(),
      "group-1",
      "run-1-corrected",
      opts
    )

    assert_received {:inspect_missing_replacement_job, "group-1", "run-1-corrected", :ok}
  end

  test "requeue_stale_replacement_job delegates ids and opts" do
    opts = [
      requeue_stale_replacement_job_event: fn socket, job_id, event_id, opts ->
        assign(
          socket,
          :workflow_event,
          {:requeue_stale_replacement_job, job_id, event_id, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket =
      HistoricalWorkflowEvents.requeue_stale_replacement_job(socket(), "job-1", "event-1", opts)

    assert socket.assigns.workflow_event ==
             {:requeue_stale_replacement_job, "job-1", "event-1", :ok}
  end

  test "retry_group_failed_jobs delegates group id, event id, and opts" do
    opts = [
      retry_group_failed_jobs_event: fn socket, request_group_id, event_id, opts ->
        assign(
          socket,
          :workflow_event,
          {:retry_group, request_group_id, event_id, Keyword.fetch!(opts, :sentinel)}
        )
      end,
      sentinel: :ok
    ]

    socket =
      HistoricalWorkflowEvents.retry_group_failed_jobs(socket(), "group-1", "event-1", opts)

    assert socket.assigns.workflow_event == {:retry_group, "group-1", "event-1", :ok}
  end

  defp socket do
    %Socket{assigns: %{__changed__: %{}}}
  end
end
