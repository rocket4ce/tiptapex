defmodule Tiptapex.Collab.Channel do
  @moduledoc """
  A Phoenix Channel implementing the Tiptapex collaboration wire protocol.

      defmodule MyAppWeb.DocChannel do
        use Tiptapex.Collab.Channel

        @impl true
        def authorize("doc:" <> slug, _params, socket) do
          case MyApp.Docs.get_by_slug(slug) do
            nil -> {:error, %{reason: "not_found"}}
            doc -> {:ok, Phoenix.Socket.assign(socket, :doc_id, doc.id)}
          end
        end
      end

  Mount it on your socket with a wildcard route matching the topics your
  editors use (`channel "doc:*", MyAppWeb.DocChannel`).

  ## Wire protocol

  Matches `PhoenixCollabProvider` in `assets/js/tiptapex/collaboration.js`:

    * `"client_sync"` (binary) — a Yjs sync message from one peer,
      rebroadcast to the others as `"server_sync"`.
    * `"client_awareness"` (binary) — Yjs awareness (cursors, names),
      rebroadcast as `"server_awareness"`.
    * `"request_state"` — a freshly-joined peer asks the room for the
      current state; rebroadcast so an existing peer answers with a sync
      message.

  The server never interprets the CRDT payloads — it is a relay. Your
  regular "save" flow remains the source of truth for persistence.

  ## Optional persistence hooks

  `load_state/2` and `persist_update/3` (both default to no-ops) let you
  snapshot the opaque Yjs state: return `{:ok, binary}` from `load_state/2`
  to seed late joiners, and store the binaries you receive in
  `persist_update/3`. Merging Yjs updates server-side would require a
  Yjs-compatible runtime, so the recommended strategy is peer-relay plus a
  snapshot written by your save action.
  """

  @doc """
  Authorizes a join. Return `{:ok, socket}`, `{:ok, socket, reply}` (the
  reply map is sent to the client), or `{:error, reply}`.
  """
  @callback authorize(topic :: String.t(), params :: map(), socket :: Phoenix.Socket.t()) ::
              {:ok, Phoenix.Socket.t()}
              | {:ok, Phoenix.Socket.t(), map()}
              | {:error, map()}

  @doc """
  Loads a previously-persisted Yjs state binary to push to a joining peer
  as an initial `"server_sync"`. Default: `{:ok, nil}` (no stored state).
  """
  @callback load_state(topic :: String.t(), socket :: Phoenix.Socket.t()) ::
              {:ok, binary() | nil}

  @doc """
  Called with every binary sync update relayed through the channel.
  Default: `:ok` (no persistence).
  """
  @callback persist_update(topic :: String.t(), update :: binary(), socket :: Phoenix.Socket.t()) ::
              :ok

  @optional_callbacks load_state: 2, persist_update: 3

  defmacro __using__(_opts) do
    quote do
      use Phoenix.Channel

      @behaviour Tiptapex.Collab.Channel

      @impl Phoenix.Channel
      def join(topic, params, socket) do
        Tiptapex.Collab.Channel.__join__(__MODULE__, topic, params, socket)
      end

      @impl Phoenix.Channel
      def handle_info({:tiptapex_push_state, binary}, socket) do
        push(socket, "server_sync", {:binary, binary})
        {:noreply, socket}
      end

      @impl Phoenix.Channel
      def handle_in("client_sync", {:binary, payload}, socket) do
        broadcast_from!(socket, "server_sync", {:binary, payload})
        persist_update(socket.topic, payload, socket)
        {:noreply, socket}
      end

      def handle_in("client_awareness", {:binary, payload}, socket) do
        broadcast_from!(socket, "server_awareness", {:binary, payload})
        {:noreply, socket}
      end

      def handle_in("request_state", _params, socket) do
        broadcast_from!(socket, "request_state", %{})
        {:noreply, socket}
      end

      def handle_in("ping", _params, socket), do: {:reply, {:ok, %{ok: true}}, socket}

      @impl Tiptapex.Collab.Channel
      def load_state(_topic, _socket), do: {:ok, nil}

      @impl Tiptapex.Collab.Channel
      def persist_update(_topic, _update, _socket), do: :ok

      defoverridable join: 3, handle_in: 3, handle_info: 2, load_state: 2, persist_update: 3
    end
  end

  @doc false
  def __join__(module, topic, params, socket) do
    case module.authorize(topic, params, socket) do
      {:ok, socket} -> joined(module, topic, socket, %{})
      {:ok, socket, reply} -> joined(module, topic, socket, reply)
      {:error, reply} -> {:error, reply}
    end
  end

  defp joined(module, topic, socket, reply) do
    case module.load_state(topic, socket) do
      {:ok, binary} when is_binary(binary) -> send(self(), {:tiptapex_push_state, binary})
      {:ok, nil} -> :ok
    end

    {:ok, reply, socket}
  end
end
