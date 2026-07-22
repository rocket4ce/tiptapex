Logger.configure(level: :warning)

Application.put_env(:tiptapex, Tiptapex.TestEndpoint,
  secret_key_base: String.duplicate("t", 64),
  pubsub_server: Tiptapex.TestPubSub,
  server: false
)

{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: Tiptapex.TestPubSub},
      Tiptapex.TestEndpoint
    ],
    strategy: :one_for_one
  )

ExUnit.start()
