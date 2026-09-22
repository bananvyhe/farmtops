require "erb"
require "nokogiri"

module News
  module Translation
    class HtmlBodyRenderer
      # The article title is translated separately and rendered outside the
      # body. An h1 inside the body must not consume a body translation block.
      TEXT_BLOCK_SELECTOR = "p, li, blockquote, figcaption, pre, h2, h3, h4, h5, h6"
      EMBED_SELECTOR = "iframe, video, source, object, embed, blockquote.twitter-tweet, blockquote.instagram-media"
      INLINE_FORMATTING_TAGS = %w[strong b em i u s].freeze
      INLINE_CONTAINER_TAGS = %w[div span].freeze
      BLOCK_TAGS = %w[p li blockquote figcaption pre h1 h2 h3 h4 h5 h6 div ul ol figure].freeze

      def initialize(source_html:)
        @source_html = source_html.to_s
        @translated_paragraphs = []
        @paragraph_index = 0
      end

      def call(translated_body_text)
        @translated_paragraphs = split_paragraphs(translated_body_text)
        return build_plain_html if source_html.nil? || source_html.empty?

        fragment = Nokogiri::HTML.fragment(source_html)
        # h1 is the article title and is translated/rendered separately. Do
        # not let an old stored body_html reintroduce it into the body layout.
        fragment.css("h1").each(&:remove)
        rendered_nodes = render_children(fragment.children)
        return build_plain_html if rendered_nodes.empty?

        output = Nokogiri::HTML::DocumentFragment.parse("")
        rendered_nodes.each { |node| output.add_child(node) }
        output.to_html
      end

      private

      attr_reader :source_html, :translated_paragraphs

      def render_node(node)
        return node.dup if node.text?
        return node.dup(1) if media_only_block?(node)
        # Embeds are content blocks, not translatable paragraphs. In
        # particular, blockquote.twitter-tweet also matches TEXT_BLOCK_SELECTOR;
        # handling it first prevents the tweet from consuming the translation
        # intended for the next heading or paragraph.
        return node.dup(1) if embed_node?(node)

        if inline_block_wrapper?(node)
          return render_children(node.children)
        end

        if text_block_node?(node)
          translated_paragraph = next_translated_paragraph
          return node.dup if translated_paragraph.nil? || translated_paragraph.empty?

          copy = node.dup
          replace_block_text(copy, translated_paragraph)
          return copy
        end

        copy = node.dup
        copy.children.remove
        render_children(node.children).each { |child| copy.add_child(child) }
        copy
      end

      def render_children(children)
        children.to_a.flat_map do |child|
          rendered = render_node(child)
          rendered.is_a?(Array) ? rendered.flatten : rendered
        end.compact
      end

      def inline_block_wrapper?(node)
        INLINE_FORMATTING_TAGS.include?(node.name) &&
          node.css(BLOCK_TAGS.join(", ")).any?
      end

      def embed_node?(node)
        node.matches?(EMBED_SELECTOR)
      end

      def text_block_node?(node)
        return true if node.matches?(TEXT_BLOCK_SELECTOR)
        return false unless node.element?
        return false if node.text.to_s.strip.empty?

        # Some publishers mark headings as a div/strong/span instead of an
        # actual h2-h6. Treat an inline-only container as one block; otherwise
        # its text is left in the source and the first translation is assigned
        # to the following paragraph.
        inline_text_container?(node)
      end

      def inline_text_container?(node)
        return false unless (INLINE_CONTAINER_TAGS + INLINE_FORMATTING_TAGS).include?(node.name)

        node.css(BLOCK_TAGS.join(", ")).empty?
      end

      def replace_block_text(copy, translated_paragraph)
        text_nodes = copy.xpath(".//text()").reject { |text| text.text.to_s.strip.empty? }

        # Preserve the author's inline emphasis for the common case of a
        # heading wrapped in <strong>/<span>. For mixed inline content (for
        # example text + a link), replacing the whole block is safer than
        # leaving source-language fragments behind.
        if text_nodes.length == 1 && copy.element_children.all? { |child| inline_only_node?(child) }
          text_nodes.first.content = translated_paragraph
          copy.xpath(".//text()").each do |text|
            text.remove if text != text_nodes.first && !text.text.to_s.strip.empty?
          end
        else
          copy.inner_html = paragraph_to_html(translated_paragraph)
        end
      end

      def inline_only_node?(node)
        return true if node.text?
        return false unless node.element?
        return false if node.matches?(BLOCK_TAGS.join(", "))

        node.element_children.all? { |child| inline_only_node?(child) }
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
