# Abstract (more or less) extractor class from which custom extractor
# classes should descend. Subclasses of Extractula::Extractor will be
# automatically added to the Extracula module.

class Extractula::Extractor
  def self.inherited subclass
    Extractula.add_extractor subclass
  end

  def self.domain domain
    @extractable_domain = domain
  end

  def self.can_extract? url, html
    if @extractable_domain.is_a? Regexp
      url.host + url.path =~ @extractable_domain
    else
      @extractable_domain ? @extractable_domain == url.domain : false
    end
  end

  def self.media_type type = nil
    @media_type = type if type
    @media_type
  end

  %w{title content summary image_urls video_embed }.each do |field|
    class_eval <<-EOS
      def self.#{field}_path(path = nil, attrib = nil, &block)
        if path
          @#{field}_path = path
          @#{field}_attr = attrib || :text
          @#{field}_block = block
        end
        @#{field}_path
      end

      def self.#{field}_attr(attrib = nil)
        @#{field}_attr = attrib if attrib
        @#{field}_attr
      end
      
      def self.#{field}_block(&block)
        @#{field}_block = block if block
        @#{field}_block
      end

      def #{field}_path
        self.class.#{field}_path
      end

      def #{field}_attr
        self.class.#{field}_attr
      end
      
      def #{field}_block
        self.class.#{field}_block
      end
    EOS
  end

  attr_reader :url, :html

  def initialize url, html
    @url  = url.is_a?(Domainatrix::Url) ? url : Domainatrix.parse(url)
    @html = html.is_a?(Nokogiri::HTML::Document) ? html : Nokogiri::HTML(html)
  end

  def extract
    Extractula::ExtractedContent.new({
      :url          => url.url,
      :media_type   => media_type,
      :title        => title,
      :content      => content,
      :summary      => summary,
      :image_urls   => image_urls,
      :video_embed  => video_embed
    })
  end

  def media_type
    self.class.media_type || 'text'
  end

  def title
    content_at(title_path, title_attr, title_block) || content_at("//title")
  end

  def content
    content_at(content_path, content_attr, content_block) || extract_content
  end

  def summary
    content_at(summary_path, summary_attr, summary_block)
  end

  def image_urls
    if image_urls_path
      image_srcs_from html.search(image_urls_path)
    end
  end

  def video_embed
    if video_embed_path
      embed_code_from html.search(video_embed_path)
    end
  end

  private

  def image_srcs_from nodeset
    nodeset.collect { |img| unrelativize img['src'].strip }
  end

  def embed_code_from nodeset
    nodeset.collect { |embed| embed.to_html }.first
  end
  
  def unrelativize path
    path.start_with?('/') ? "#{@url.scheme}://#{@url.host}#{path}" : path
  end

  def content_at path, attrib = :text, block = nil
    if path
      if node = html.at(path)
        value = attrib == :text ? node.text.strip : node[attrib].strip
        block ? block.call(value) : value
      end
    end
  end

  def extract_content
    content_node ? content_node.inner_html.strip : ""
  end
  
  def candidate_nodes
    @candidate_nodes ||= html.search("//div|//p|//br").collect do |node|
      parent = node.parent
      if node.node_name == 'div'
        text_size = calculate_children_text_size(parent, "div")

        if text_size > 0
          {:text_size => text_size, :parent => parent}
        else
          nil
        end
      elsif node.node_name == "p"
        text_size = calculate_children_text_size(parent, "p")

        if text_size > 0
          {:text_size => text_size, :parent => parent}
        else
          nil
        end
      elsif node.node_name == "br"
        begin
          if node.previous.node_name == "text" && node.next.node_name == "text"
            text_size = 0
            parent.children.each do |child|
              text_size += child.text.strip.size if child.node_name == "text"
            end

            if text_size > 0
              {:text_size => text_size, :parent => parent}
            else
              nil
            end
          else
            nil
          end
        rescue => e
          nil
        end
      else
        nil
      end
    end.compact.uniq    
  end

  def content_node_selector
    Proc.new { |n| n[:text_size] > content_node_text_size_cutoff }
  end
  
  def content_node_text_size_cutoff
    140
  end
  
  def content_node
    @content_node ||= begin
      if node = candidate_nodes.detect(&content_node_selector)
        node[:parent]
      end
    end
  end

  def calculate_children_text_size(parent, node_type)
    text_size = 0
    parent.children.each do |child|
      if child.node_name == node_type
        child.children.each {|c| text_size += c.text.strip.size if c.node_name == "text"}
      end
    end

    text_size
  end
end
