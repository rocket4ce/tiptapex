defmodule Tiptapex.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 1]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Tiptapex.Components

  defp editor(assigns) do
    render_component(&Components.tiptapex_editor/1, assigns)
  end

  defp viewer(assigns) do
    render_component(&Components.tiptapex_viewer/1, assigns)
  end

  defp pushed_events(socket) do
    Enum.reverse(socket.private.live_temp[:push_events] || [])
  end

  defp attr!(html, selector, name) do
    case html |> Floki.parse_fragment!() |> Floki.attribute(selector, name) do
      [value] -> value
      [] -> nil
    end
  end

  describe "tiptapex_editor/1" do
    test "renders the hook root with defaults" do
      html = editor(id: "ed")

      assert attr!(html, "div#ed", "phx-hook") == "TiptapexEditor"
      assert attr!(html, "div#ed", "phx-update") == "ignore"
      assert attr!(html, "div#ed", "data-ttx-set-content-event") == "tiptapex:set-content:ed"
      assert Jason.decode!(attr!(html, "div#ed", "data-ttx-doc")) == Tiptapex.empty_doc()

      # Child roles for the hook.
      assert attr!(html, "[data-ttx-role=toolbar]", "class") == "ttx-toolbar"
      assert attr!(html, "[data-ttx-role=editor]", "class") == "ttx-content"
      refute html =~ "data-ttx-upload-url"
      refute html =~ "data-ttx-collab-topic"
    end

    test "remount_key namespaces the DOM id but not the events" do
      html = editor(id: "ed", remount_key: 3)

      assert attr!(html, "div#ed-3", "data-ttx-set-content-event") == "tiptapex:set-content:ed"
    end

    test "value is JSON-encoded into data-ttx-doc" do
      doc = %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}
      assert Jason.decode!(attr!(editor(id: "e", value: doc), "div#e", "data-ttx-doc")) == doc
    end

    test "upload attributes with scope" do
      html = editor(id: "e", upload_url: "/up", upload_scope: 42, upload_scope_name: "article_id")

      assert attr!(html, "div#e", "data-ttx-upload-url") == "/up"
      assert attr!(html, "div#e", "data-ttx-upload-scope") == "42"
      assert attr!(html, "div#e", "data-ttx-upload-scope-name") == "article_id"
    end

    test "nil upload_scope keeps the scope-name so the hook blocks uploads" do
      html = editor(id: "e", upload_url: "/up", upload_scope: nil)

      assert attr!(html, "div#e", "data-ttx-upload-scope-name") == "scope"
      assert attr!(html, "div#e", "data-ttx-upload-scope") == nil
    end

    test "collab attributes" do
      html =
        editor(
          id: "e",
          collab: %{topic: "doc:7", socket_path: "/ws", user: %{id: 1, name: "Ada"}}
        )

      assert attr!(html, "div#e", "data-ttx-collab-topic") == "doc:7"
      assert attr!(html, "div#e", "data-ttx-collab-socket-path") == "/ws"

      assert Jason.decode!(attr!(html, "div#e", "data-ttx-collab-user")) == %{
               "id" => 1,
               "name" => "Ada"
             }
    end

    test "toolbar false hides the toolbar element" do
      html = editor(id: "e", toolbar: false)

      assert attr!(html, "div#e", "data-ttx-toolbar") == "false"
      refute html =~ "data-ttx-role=\"toolbar\""
    end

    test "toolbar group list is encoded as a JSON array of strings" do
      html = editor(id: "e", toolbar: [:marks, :history])
      assert Jason.decode!(attr!(html, "div#e", "data-ttx-toolbar")) == ["marks", "history"]
    end

    test "extension keys are camelized for the JS side" do
      html = editor(id: "e", extensions: %{character_count_limit: 10, drag_handle: false})

      assert Jason.decode!(attr!(html, "div#e", "data-ttx-extensions")) ==
               %{"characterCountLimit" => 10, "dragHandle" => false}
    end

    test "push_event sync only emits the change event when given" do
      assert attr!(editor(id: "e"), "div#e", "data-ttx-event-change") == nil

      assert attr!(editor(id: "e", on_change: "changed"), "div#e", "data-ttx-event-change") ==
               "changed"
    end

    test "hidden_input sync renders the input and disables push events" do
      doc = %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}
      form = to_form(%{"body" => doc})
      html = editor(id: "e", sync: {:hidden_input, form[:body]})

      assert attr!(html, "div#e", "data-ttx-input-id") == "body_ttx"
      assert attr!(html, "div#e", "data-ttx-event-change") == ""
      assert attr!(html, "input#body_ttx", "type") == "hidden"
      assert attr!(html, "input#body_ttx", "name") == "body"
      assert Jason.decode!(attr!(html, "input#body_ttx", "value")) == doc
    end

    test "hidden_input sync takes the initial doc from the form field" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "hi"}]}
        ]
      }

      form = to_form(%{"body" => doc})
      html = editor(id: "e", sync: {:hidden_input, form[:body]})

      assert Jason.decode!(attr!(html, "div#e", "data-ttx-doc")) == doc
    end

    test "actions slot renders in the footer" do
      html =
        render_component(&Components.tiptapex_editor/1, %{
          id: "e",
          actions: [%{inner_block: fn _, _ -> "SAVE-BUTTON" end, __slot__: :actions}]
        })

      assert html =~ "SAVE-BUTTON"
    end
  end

  describe "tiptapex_viewer/1" do
    @doc_with_text %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hello viewer"}]}
      ]
    }

    test "hydrate mode renders hook, doc payload, and SSR fallback" do
      html = viewer(id: "v", value: @doc_with_text)

      assert attr!(html, "div#v", "phx-hook") == "TiptapexViewer"
      assert attr!(html, "div#v", "phx-update") == "ignore"
      assert Jason.decode!(attr!(html, "div#v", "data-ttx-doc")) == @doc_with_text
      assert attr!(html, "[data-ttx-role=fallback]", "class") == "ttx-prose"
      assert html =~ "<p>Hello viewer</p>"
      assert html =~ "data-ttx-role=\"viewer-target\""
    end

    test "hydrate mode requires an id" do
      assert_raise ArgumentError, ~r/requires an :id/, fn ->
        viewer(value: @doc_with_text)
      end
    end

    test "static mode renders only the safe HTML" do
      html = viewer(value: @doc_with_text, hydrate: false)

      refute html =~ "phx-hook"
      assert html =~ "<p>Hello viewer</p>"
    end

    test "static mode escapes malicious content" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [%{"type" => "text", "text" => "<img src=x onerror=alert(1)>"}]
          }
        ]
      }

      html = viewer(value: doc, hydrate: false)
      refute html =~ "<img"
      assert html =~ "&lt;img"
    end
  end

  describe "page layout" do
    @page_doc %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hello page"}]}
      ]
    }

    test "no page attribute means the document decides" do
      refute editor(id: "e") =~ "data-ttx-page"
    end

    test "a map is normalised into the wire shape" do
      html = editor(id: "e", page: %{size: :legal, margins: %{top: "1in"}})
      page = Jason.decode!(attr!(html, "div#e", "data-ttx-page"))

      assert page["size"] == "legal"
      assert page["orientation"] == "portrait"
      assert page["margins"]["top"] == 25.4
      assert page["numbering"]["format"] == "{page}"
    end

    test "true means defaults, false means explicitly unpaginated" do
      assert Jason.decode!(attr!(editor(id: "e", page: true), "div#e", "data-ttx-page"))["size"] ==
               "letter"

      assert attr!(editor(id: "e", page: false), "div#e", "data-ttx-page") == "false"
    end

    test "the editor exposes a per-id set-page event" do
      assert attr!(editor(id: "ed"), "div#ed", "data-ttx-set-page-event") ==
               "tiptapex:set-page:ed"
    end

    test "set_page/3 pushes the normalised setup, and nil turns it off" do
      socket = %Phoenix.LiveView.Socket{private: %{live_temp: %{}}}

      assert [["tiptapex:set-page:ed", %{page: page}]] =
               socket |> Components.set_page("ed", %{size: :a4}) |> pushed_events()

      assert page["size"] == "a4"

      assert [["tiptapex:set-page:ed", %{page: nil}]] =
               socket |> Components.set_page("ed", nil) |> pushed_events()
    end

    test "the viewer renders the paper geometry into the server-rendered sheet" do
      html = viewer(id: "v", value: @page_doc, page: %{size: :letter})
      style = attr!(html, "[data-ttx-role=fallback]", "style")

      assert attr!(html, "[data-ttx-role=fallback]", "class") == "ttx-prose ttx-sheet"
      assert style =~ "--ttx-page-w: 816.0px;"
      assert style =~ "--ttx-page-mt: 96.0px;"
    end

    test "a document carrying its own page setup styles the sheet with no page attribute" do
      html = viewer(id: "v", value: Tiptapex.Page.put(@page_doc, %{size: :a4}), hydrate: false)

      assert attr!(html, "div#v", "class") =~ "ttx-sheet"
      assert attr!(html, "div#v", "style") =~ "--ttx-page-w: 793.7px;"
    end

    test "page={false} on the viewer keeps the plain prose rendering" do
      html =
        viewer(
          id: "v",
          value: Tiptapex.Page.put(@page_doc, %{size: :a4}),
          hydrate: false,
          page: false
        )

      refute attr!(html, "div#v", "class") =~ "ttx-sheet"
      refute html =~ "--ttx-page-w"
    end
  end
end
