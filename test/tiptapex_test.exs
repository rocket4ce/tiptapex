defmodule TiptapexTest do
  use ExUnit.Case, async: true

  test "empty_doc/0 returns a valid empty document" do
    assert %{"type" => "doc", "content" => [%{"type" => "paragraph"}]} = Tiptapex.empty_doc()
  end

  test "to_html/2 delegate" do
    assert Tiptapex.to_html(nil) == {:safe, ""}
  end

  test "to_plain_text/1 delegate" do
    assert Tiptapex.to_plain_text(Tiptapex.empty_doc()) == ""
  end
end
