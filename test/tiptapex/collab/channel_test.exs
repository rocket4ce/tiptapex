defmodule Tiptapex.Collab.ChannelTest do
  use Tiptapex.ChannelCase, async: false

  alias Tiptapex.{TestChannel, TestUserSocket}

  defp join!(topic, params \\ %{}) do
    {:ok, reply, socket} =
      TestUserSocket
      |> socket()
      |> subscribe_and_join(TestChannel, topic, params)

    {reply, socket}
  end

  test "join calls authorize/3 and returns its reply" do
    {reply, socket} = join!("doc:42")
    assert %{color: "hsl(" <> _} = reply
    assert socket.assigns.doc_id == "42"
  end

  test "join propagates authorize errors" do
    assert {:error, %{reason: "unauthorized"}} =
             TestUserSocket
             |> socket()
             |> subscribe_and_join(TestChannel, "doc:42", %{"fail" => true})
  end

  test "client_sync is rebroadcast as server_sync to other peers only" do
    {_reply, socket} = join!("doc:sync")

    push(socket, "client_sync", {:binary, <<1, 2, 3>>})

    assert_broadcast "server_sync", {:binary, <<1, 2, 3>>}
    # The sender itself must not receive the rebroadcast.
    refute_push "server_sync", {:binary, <<1, 2, 3>>}
  end

  test "client_awareness is rebroadcast as server_awareness" do
    {_reply, socket} = join!("doc:aw")
    push(socket, "client_awareness", {:binary, <<7>>})
    assert_broadcast "server_awareness", {:binary, <<7>>}
  end

  test "request_state is relayed to peers" do
    {_reply, socket} = join!("doc:rs")
    push(socket, "request_state", %{})
    assert_broadcast "request_state", %{}
  end

  test "ping replies ok" do
    {_reply, socket} = join!("doc:ping")
    ref = push(socket, "ping", %{})
    assert_reply ref, :ok, %{ok: true}
  end

  test "persist_update/3 receives every relayed sync update" do
    Process.register(self(), :tiptapex_persist_listener)
    on_exit(fn -> nil end)

    {_reply, socket} = join!("doc:persist")
    push(socket, "client_sync", {:binary, <<5, 5>>})

    assert_receive {:persisted, "doc:persist", <<5, 5>>}
  after
    Process.unregister(:tiptapex_persist_listener)
  end

  test "load_state/2 pushes stored state to the joining peer" do
    {:ok, _reply, _socket} =
      TestUserSocket
      |> socket()
      |> subscribe_and_join(Tiptapex.SeededTestChannel, "seeded:1", %{})

    assert_push "server_sync", {:binary, <<9, 9, 9>>}
  end
end
