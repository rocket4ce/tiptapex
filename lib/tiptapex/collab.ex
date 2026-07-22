defmodule Tiptapex.Collab do
  @moduledoc """
  Realtime collaboration helpers.

  Tiptapex collaboration runs Yjs (CRDT) documents over Phoenix Channels:
  the browser bundles the Yjs runtime (via the optional
  `"tiptapex/collaboration"` JS entry point) and the server relays binary
  sync/awareness messages between peers with `Tiptapex.Collab.Channel`.

  Wiring it up:

  1. Mount a channel using the macro on your socket:

         # lib/my_app_web/channels/user_socket.ex
         channel "doc:*", MyAppWeb.DocChannel

         defmodule MyAppWeb.DocChannel do
           use Tiptapex.Collab.Channel

           @impl true
           def authorize("doc:" <> id, _params, socket) do
             # your auth: load the record, check socket.assigns…
             {:ok, socket}
           end
         end

  2. Build the JS hook with the collab plugin:

         import { makeEditorHook, TiptapexViewerHook } from "tiptapex"
         import { CollabPlugin } from "tiptapex/collaboration"

         const hooks = {
           TiptapexEditor: makeEditorHook({ collab: CollabPlugin }),
           TiptapexViewer: TiptapexViewerHook,
         }

  3. Pass `collab` to the component:

         <.tiptapex_editor
           id="body"
           value={@doc}
           collab={%{topic: "doc:" <> @id, user: Tiptapex.Collab.user(%{id: user.id, name: user.name})}}
         />
  """

  @doc """
  Builds the user payload the collaboration caret displays, deriving a
  stable color from the id when none is given.

      iex> %{id: 7, color: "hsl(" <> _} = Tiptapex.Collab.user(%{id: 7})
  """
  @spec user(map()) :: map()
  def user(%{id: id} = attrs) do
    Map.put_new(attrs, :color, deterministic_color(id))
  end

  @doc """
  Maps any term to a stable, evenly-distributed HSL color — so each
  collaborator keeps the same caret color across sessions without storing
  anything.
  """
  @spec deterministic_color(term()) :: String.t()
  def deterministic_color(id) do
    "hsl(#{:erlang.phash2(id, 360)}, 70%, 55%)"
  end
end
