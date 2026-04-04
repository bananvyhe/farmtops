require "erb"
require "nokogiri"

module News
  module Translation
    class HtmlBodyRenderer
      TEXT_BLOCK_SELECTOR = "p, li, blockquote, figcaption, pre, h1, h2, h3, h4, h5, h6"
      EMBED_SELECTOR = "iframe, video, source, object, embed, blockquote.twitter-tweet, blockquote.instagram-media"

      def initialize(source_html:)
        @source_html = source_html.to_s
        @translated_paragraphs = []
        @paragraph_index = 0
      end

      def call(translated_body_text)
        @translated_paragraphs = split_paragraphs(translated_body_text)
        return build_plain_html if source_html.nil? || source_html.empty?

        fragment = Nokogiri::HTML.fragment(source_html)
        rendered_nodes = fragment.children.filter_map { |child| render_node(child) }
        return build_plain_html if rendered_nodes.empty?

        output = Nokogiri::HTML::DocumentFragment.parse("")
        rendered_nodes.each { |node| output.add_child(node) }
        output.to_html
      end

      private

      attr_reader :source_html, :translated_paragraphs

      def render_node(node)
        return node.dup if node.text?
        return node.dup if media_only_block?(node)

        if text_block_node?(node)
          translated_paragraph = next_translated_paragraph
          return node.dup if translated_paragraph.nil? || translated_paragraph.empty?

          copy = node.dup
          copy.inner_html = paragraph_to_html(translated_paragraph)
          return copy
        end

        return node.dup if embed_node?(node)

        copy = node.dup
        copy.children.remove
        node.children.each do |child|
          rendered_child = render_node(child)
          copy.add_child(rendered_child) if rendered_child
        end
        copy
      end

      def embed_node?(node)
        node.matches?(EMBED_SELECTOR)
      end

      def text_block_node?(node)
        node.matches?(TEXT_BLOCK_SELECTOR) || (node.name == "div" && node.element_children.empty? && !node.text.to_s.strip.empty?)
      end

      def media_only_block?(node)
        return false unless node.element?
        return true if node.matches?("figure, iframe, video, source")

        return false unless node.matches?("p, li, blockquote, div")

        media_children = node.css("img, figure, iframe, video, source")
        media_children.any? && node.text.to_s.strip.blank?
      end

      def next_translated_paragraph
        paragraph = translated_paragraphs[@paragraph_index]
        @paragraph_index += 1 if paragraph && !paragraph.empty?
        paragraph
      end

      def split_paragraphs(body_text)
        body_text.to_s.strip.split(/\n{2,}/).map(&:strip).reject(&:empty?)
      end

      def paragraph_to_html(paragraph)
        ERB::Util.html_escape(paragraph).gsub(/\n/, "<br>")
      end

      def build_plain_html
        paragraphs = translated_paragraphs
        return "" if paragraphs.empty?

        paragraphs.map { |paragraph| "<p>#{paragraph_to_html(paragraph)}</p>" }.join
      end
    end
  end
end
