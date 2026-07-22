defmodule Tiptapex.Components do
  @moduledoc """
  HEEx function components for the Tiptap editor and viewer.

      import Tiptapex.Components

      <.tiptapex_editor id="body" value={@doc} upload_url={~p"/tiptapex/uploads"} />

      <.tiptapex_viewer id="article" value={@article.body} />

  Both components render a `phx-update="ignore"` root owned by the JS hooks
  shipped in this package (`TiptapexEditor` / `TiptapexViewer`); register the
  hooks in your `app.js` (see the `Tiptapex` module docs).

  ## Sync modes

  The editor supports two ways of getting the document back to the server:

    * `sync={:push_event}` (default) — the hook pushes the configured
      `on_change` event (default `"tiptapex_change"`) with
      `%{"json" => doc, "html" => html, "characters" => n}` on every
      debounced change. Handle it in your LiveView and persist on an
      explicit save action. Do not trust the pushed `"html"` for display —
      re-render the JSON server-side with `Tiptapex.Renderer.to_html/2`.

    * `sync={{:hidden_input, @form[:body]}}` — the component renders a
      hidden input bound to the form field and the hook keeps it in sync
      with the document JSON, dispatching an `input` event so the form's
      `phx-change` fires. Pair the field with `Tiptapex.Schema.Document`
      in your Ecto schema and no custom `handle_event` is needed.
  """

  use Phoenix.Component

  @doc """
  Renders the Tiptap editor.

  ## Examples

      <.tiptapex_editor id="body" value={@body} on_change="editor_update" />

      <.tiptapex_editor
        id="body"
        value={@body}
        upload_url={~p"/admin/uploads"}
        upload_scope={@article.id}
        collab={%{topic: "doc:" <> @article.slug, user: %{id: 1, name: "Ada", color: "#309"}}}
        toolbar={[:marks, :blocks, :lists, :history]}
        extensions={%{table: false, character_count_limit: 10_000}}
      />
  """
  attr :id, :string, required: true, doc: "logical editor id; also namespaces its events"

  attr :value, :map, default: nil, doc: "the Tiptap/ProseMirror JSON document (map or nil)"

  attr :placeholder, :string, default: nil

  attr :upload_url, :string,
    default: nil,
    doc: "endpoint for editor uploads; nil disables uploads entirely"

  attr :upload_scope, :any,
    default: :none,
    doc: """
    opaque value POSTed with each upload (e.g. the record id). Pass nil to
    declare "scope required but record not saved yet" — uploads stay blocked
    until it has a value. Leave as :none for unscoped uploads.
    """

  attr :upload_scope_name, :string, default: "scope", doc: "form field name for the scope"

  attr :collab, :map,
    default: nil,
    doc: """
    enables realtime collaboration: %{topic: "...", socket_path: "/socket",
    user: %{id: ..., name: ..., email: ..., color: ...}}. Requires the host
    to build its hook with the CollabPlugin (see the collaboration guide).
    """

  attr :toolbar, :any,
    default: nil,
    doc: """
    nil for the full default toolbar, false to hide it, a list of group
    atoms (:marks, :blocks, :align, :lists, :typography, :colors, :insert,
    :utilities, :history) for an ordered subset, or a map for full config.
    """

  attr :extensions, :map,
    default: nil,
    doc: """
    per-feature switches forwarded to the JS buildExtensions/1, e.g.
    %{table: false, drag_handle: false, character_count_limit: 10_000}.
    """

  attr :labels, :map, default: nil, doc: "i18n label overrides for toolbar and table menu"

  attr :remount_key, :any,
    default: nil,
    doc: "bump this value to force a full client remount (e.g. after restoring a version)"

  attr :on_change, :string,
    default: nil,
    doc: "event pushed on debounced updates (default \"tiptapex_change\")"

  attr :on_uploaded, :string,
    default: nil,
    doc: "event pushed after a successful upload (default \"tiptapex_uploaded\")"

  attr :sync, :any,
    default: :push_event,
    doc: ":push_event or {:hidden_input, form_field}"

  attr :debounce, :integer, default: nil, doc: "debounce for change events, in ms (default 400)"

  attr :count_template, :string,
    default: nil,
    doc: "footer counter template, e.g. \"{chars} caracteres · {words} palabras\""

  attr :class, :any, default: nil
  attr :rest, :global

  slot :actions, doc: "rendered in the editor footer, next to the character count"

  def tiptapex_editor(assigns) do
    {input_field, push_change_event} =
      case assigns.sync do
        {:hidden_input, %Phoenix.HTML.FormField{} = field} -> {field, assigns.on_change || ""}
        :push_event -> {nil, assigns.on_change}
        other -> raise ArgumentError, "invalid sync mode: #{inspect(other)}"
      end

    assigns =
      assigns
      |> assign(:input_field, input_field)
      |> assign(:push_change_event, push_change_event)
      |> assign(:doc, doc_value(assigns.value, input_field))

    ~H"""
    <div
      id={dom_id(@id, @remount_key)}
      phx-hook="TiptapexEditor"
      phx-update="ignore"
      class={["ttx-editor", @class]}
      data-ttx-doc={Jason.encode!(@doc)}
      data-ttx-set-content-event={"tiptapex:set-content:" <> @id}
      data-ttx-placeholder={@placeholder}
      data-ttx-debounce={@debounce}
      data-ttx-count-template={@count_template}
      data-ttx-upload-url={@upload_url}
      data-ttx-upload-scope-name={@upload_scope != :none && @upload_scope_name}
      data-ttx-upload-scope={@upload_scope != :none && @upload_scope && to_string(@upload_scope)}
      data-ttx-event-change={@push_change_event}
      data-ttx-event-uploaded={@on_uploaded}
      data-ttx-input-id={@input_field && @input_field.id <> "_ttx"}
      data-ttx-collab-topic={@collab && @collab[:topic]}
      data-ttx-collab-socket-path={@collab && @collab[:socket_path]}
      data-ttx-collab-user={@collab && @collab[:user] && Jason.encode!(@collab[:user])}
      data-ttx-toolbar={@toolbar != nil && encode_config(@toolbar)}
      data-ttx-extensions={@extensions && encode_config(@extensions)}
      data-ttx-labels={@labels && encode_config(@labels)}
      {@rest}
    >
      <input
        :if={@input_field}
        type="hidden"
        id={@input_field.id <> "_ttx"}
        name={@input_field.name}
        value={Jason.encode!(@doc)}
      />
      <div :if={@toolbar != false} data-ttx-role="toolbar" class="ttx-toolbar"></div>
      <div data-ttx-role="editor" class="ttx-content"></div>
      <div class="ttx-footer">
        <span data-ttx-role="char-count" class="ttx-char-count"></span>
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a Tiptap document read-only.

  Server-side it renders safe HTML via `Tiptapex.Renderer.to_html/2` — no
  `raw/1`, no trust in client HTML. With `hydrate` (the default) the
  `TiptapexViewer` hook replaces that fallback with a client-side Tiptap
  render, which reproduces interactive niceties (task list checkboxes,
  identical NodeViews) — visually both are the same.
  """
  attr :id, :string, default: nil, doc: "required when hydrate is true"
  attr :value, :map, default: nil, doc: "the Tiptap/ProseMirror JSON document"
  attr :hydrate, :boolean, default: true
  attr :class, :any, default: nil
  attr :renderer, :list, default: [], doc: "options forwarded to Tiptapex.Renderer.to_html/2"
  attr :rest, :global

  def tiptapex_viewer(%{hydrate: true, id: nil}) do
    raise ArgumentError, "tiptapex_viewer requires an :id when hydrate is enabled"
  end

  def tiptapex_viewer(%{hydrate: true} = assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="TiptapexViewer"
      phx-update="ignore"
      class={["ttx-viewer", @class]}
      data-ttx-doc={Jason.encode!(@value || Tiptapex.empty_doc())}
      {@rest}
    >
      <div data-ttx-role="fallback" class="ttx-prose">
        {Tiptapex.Renderer.to_html(@value, @renderer)}
      </div>
      <div data-ttx-role="viewer-target"></div>
    </div>
    """
  end

  def tiptapex_viewer(assigns) do
    ~H"""
    <div id={@id} class={["ttx-viewer ttx-prose", @class]} {@rest}>
      {Tiptapex.Renderer.to_html(@value, @renderer)}
    </div>
    """
  end

  @doc """
  Pushes new content into a mounted editor from the server.

      {:noreply, Tiptapex.Components.set_content(socket, "body", restored_doc)}

  The event is namespaced by the editor's `id`, so multiple editors in one
  LiveView never receive each other's content.
  """
  def set_content(socket, id, doc) when is_binary(id) do
    Phoenix.LiveView.push_event(socket, "tiptapex:set-content:" <> id, %{json: doc})
  end

  defp dom_id(id, nil), do: id
  defp dom_id(id, remount_key), do: "#{id}-#{remount_key}"

  defp doc_value(nil, %Phoenix.HTML.FormField{} = field) do
    case field.value do
      nil -> Tiptapex.empty_doc()
      doc when is_map(doc) -> doc
      json when is_binary(json) -> decode_or_empty(json)
      _ -> Tiptapex.empty_doc()
    end
  end

  defp doc_value(nil, _), do: Tiptapex.empty_doc()
  defp doc_value(value, _) when is_map(value) and map_size(value) == 0, do: Tiptapex.empty_doc()
  defp doc_value(value, _), do: value

  defp decode_or_empty(json) do
    case Jason.decode(json) do
      {:ok, doc} when is_map(doc) -> doc
      _ -> Tiptapex.empty_doc()
    end
  end

  # JS option keys are camelCase; Elixir users write snake_case atoms.
  # Convert keys recursively (values are left untouched, except lists of
  # atoms — toolbar groups — which become strings).
  defp encode_config(config), do: config |> camelize_config() |> Jason.encode!()

  defp camelize_config(%{} = map) do
    Map.new(map, fn {k, v} -> {camelize_key(k), camelize_config(v)} end)
  end

  defp camelize_config(list) when is_list(list), do: Enum.map(list, &camelize_config/1)

  defp camelize_config(atom) when is_atom(atom) and not is_boolean(atom) and atom != nil,
    do: to_string(atom)

  defp camelize_config(other), do: other

  defp camelize_key(key) when is_atom(key), do: key |> Atom.to_string() |> camelize_key()

  defp camelize_key(key) when is_binary(key) do
    case String.split(key, "_") do
      [single] -> single
      [first | rest] -> first <> Enum.map_join(rest, &String.capitalize/1)
    end
  end
end
