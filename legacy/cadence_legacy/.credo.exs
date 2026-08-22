%{
  configs: [
    %{
      name: "default",
      requires: [
        "lib/cadence/credo/checks/virtual_timer.ex"
      ],
      checks: %{
        extra: [
          {Cadence.Credo.Checks.VirtualTimer,
           excluded_paths: [
             "lib/cadence/time/",
             "lib/cadence/time.ex",
             "lib/mix/"
           ],
           test_excluded_paths: [
             "test/support/",
             "test/integration/"
           ],
           test_exit_status: 0,
           test_priority: :low,
           clock_included_paths: ["lib/cadence/"],
           forbidden_calls: [
             {Process, :send_after, 3},
             {Process, :send_after, 4},
             {Process, :cancel_timer, 1},
             {:timer, :sleep, 1},
             {:timer, :send_after, 2},
             {:timer, :send_after, 3},
             {:timer, :send_after, 4},
             {:timer, :send_interval, 2},
             {:timer, :send_interval, 3},
             {:timer, :send_interval, 4},
             {:timer, :apply_after, 4},
             {:timer, :apply_interval, 4},
             {:erlang, :send_after, 3},
             {:erlang, :send_after, 4},
             {:erlang, :start_timer, 3},
             {:erlang, :start_timer, 4}
           ]}
        ]
      }
    }
  ]
}
