defmodule CadenceWeb.HostContextTest do
  use ExUnit.Case, async: true

  test "the command context transports the endpoint label alongside its identity" do
    command = %{
      command_request_id: "request-1",
      command_name: "NOOP",
      status: :queued,
      target: "spacecraft_runtime:spacecraft-1",
      target_name: "Aurora",
      metadata: %{"private" => true}
    }

    context =
      CadenceWeb.HostContext.from_assigns(%{
        ops_context: %{
          pinned_focus: %{kind: :command, id: "request-1"},
          modules: [
            %{
              key: "commands",
              status: :info,
              count: 1,
              freshness: :current,
              observed_at: DateTime.utc_now(),
              data: %{followed_command: command}
            }
          ]
        }
      })

    assert [section] = context.ops_context.modules
    assert section.data.followed_command.target_name == "Aurora"
    assert section.data.followed_command.target == "spacecraft_runtime:spacecraft-1"
    refute Map.has_key?(section.data.followed_command, :metadata)
  end
end
