defmodule Tiptapex.TestChannel do
  @moduledoc false
  use Tiptapex.Collab.Channel

  @impl true
  def authorize("doc:" <> id, params, socket) do
    if params["fail"] do
      {:error, %{reason: "unauthorized"}}
    else
      {:ok, Phoenix.Socket.assign(socket, :doc_id, id),
       %{color: Tiptapex.Collab.deterministic_color(id)}}
    end
  end

  @impl true
  def persist_update(topic, update, _socket) do
    if pid = Process.whereis(:tiptapex_persist_listener) do
      send(pid, {:persisted, topic, update})
    end

    :ok
  end
end

defmodule Tiptapex.SeededTestChannel do
  @moduledoc false
  use Tiptapex.Collab.Channel

  @impl true
  def authorize(_topic, _params, socket), do: {:ok, socket}

  @impl true
  def load_state(_topic, _socket), do: {:ok, <<9, 9, 9>>}
end

defmodule Tiptapex.TestUserSocket do
  @moduledoc false
  use Phoenix.Socket

  channel "doc:*", Tiptapex.TestChannel
  channel "seeded:*", Tiptapex.SeededTestChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end

defmodule Tiptapex.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :tiptapex

  socket "/socket", Tiptapex.TestUserSocket, websocket: true
end

defmodule Tiptapex.ChannelCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      @endpoint Tiptapex.TestEndpoint
    end
  end
end
