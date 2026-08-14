require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "render_markdown converts pipe tables into HTML tables" do
    markdown = "| Rank | Civ |\n|------|-----|\n| 1 | Rome |\n"

    html = render_markdown(markdown)

    assert_match "<table>", html
    assert_match "<td>Rome</td>", html
  end
end
