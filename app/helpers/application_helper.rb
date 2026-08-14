module ApplicationHelper
  def render_markdown(text)
    renderer = Redcarpet::Markdown.new(
      Redcarpet::Render::HTML.new(escape_html: true),
      autolink: true, fenced_code_blocks: true, tables: true
    )
    renderer.render(text).html_safe
  end
end
