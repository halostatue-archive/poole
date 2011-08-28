# -*- ruby encoding: utf-8 -*-

require 'nokogiri'
require 'fileutils'
require 'date'
require 'pathname'
require 'uri'

# ExitWP converts WordPress XML export files to Jekyll blog formats. Based
# on exitwp.py (https://github.com/thomasf/exitwp) by Thomas Frössman
# (https://github.com/thomasf).
#
# Tested with a Wordpress 2.8.1 export file and jekyll 0.11.0. pandoc is
# required to be installed if conversion from HTML will be done.
class ExitWP
  VERSION = '1.0.0'

  def initialize(config)
    @config = config

    config.config['stdout'] = $stdout unless config.stdout
    config.config['stderr'] = $stderr unless config.stderr
  end

  attr_reader :config

  def run
    config.stdout.puts "Starting conversion" unless config.quiet
    Dir[File.join(config.wp_exports, "*.xml")].each do |file|
      parse_wordpress_xml(file).each do |channel_data|
        write_jekyll(config, channel_data)
      end
    end
    config.stdout.puts "Done." unless config.quiet
  end

  class WordPressXMLParser
    def initialize(config, file)
      @config = config
      @document = File.open(file) { |f| Nokogiri::XML::Document.parse(f) }
    end

    attr_reader :config

    def parse
      channels = document / './/channel'
      channels.map { |channel| ChannelParser.new(config, channel).parse }
    end

    class NodeParser
      def initialize(config, node)
        @config, @node = node
      end

      attr_reader :config, :node

      def detail_for(tag, default = nil)
        detail = (node / "./#{tag}").first
        detail = detail.text rescue nil if detail

        unless detail
          config.stderr.puts "Error getting #{tag} value. Setting to #{default.inspect}."
          detail = default
        end

        detail
      end
    end

    class ChannelParser < NodeParser
      def parse
        {
          'header'  => HeaderParser.new(config, node).parse,
          'items'   => ItemsParser.new(config, node).parse
        }
      end
    end

    class HeaderParser < NodeParser
      def parse
        {
          'title'       => detail_for('title'),
          'link'        => detail_for('link'),
          'description' => detail_for('description'),
        }
      end
    end

    class ItemsParser < NodeParser
      def parse
        items = node / './/item'
        items.map { |item| ItemParser.new(config, item).parse }
      end
    end

    class CategoryParser < NodeParser
      def parse
        categories = node / './/category[@domain]'
        taxonomies = Hash.new { |h, k| h[k] = [] }

        categories.each do |category|
          domain = category['domain']
          entry = category.text

          next if config.taxonomies['filter'].include? domain
          next if config.taxonomies['entry_filter'][domain] == entry
          taxonomies[domain] << entry
        end

        taxonomies
      end
    end

    class BodyParser < NodeParser
      def parse
        body = detail_for('content:encoded')
        image_sources = find_images(body)
        [ body, image_sources ]
      end

      def find_images(body)
        html = Nokogiri::HTML::Document.parse(body)
        image_sources = (html / './/img/@src').map { |a| a.value }
      rescue
        config.stderr.puts "Could not parse HTML: #{body.inspect}"
        []
      end
      private :find_images
    end

    class ItemParser < NodeParser
      def parse
        taxonomies = CategoryParser.new(config, node).parse
        body, image_sources = BodyParser.new(config, node).parse
        {
          'title'       => detail_for('title'),
          'author'      => detail_for('dc:creator'),
          'date'        => detail_for('wp:post_date'),
          'slug'        => detail_for('wp:post_name'),
          'status'      => detail_for('wp:status'),
          'type'        => detail_for('wp:post_type'),
          'wp_id'       => detail_for('wp:post_id'),
          'taxonomies'  => taxonomies,
          'body'        => body,
          'img_srcs'    => image_sources
        }
      end
    end
  end

  def parse_wordpress_xml(file)
    config.stdout.puts "Parsing: #{file}" unless config.quiet
    WordPressXMLParser.new(config, file).parse
  end
  private :parse_wordpress_xml

  class JekyllWriter
    attr_reader :config, :channel_data
    attr_reader :header, :items
    attr_reader :item_uids, :attachments, :blog_path

    def convert_html(html, target_format = 'markdown')
      case target_format.downcase
      when 'html'
        html
      else
        # NOTE: This assumes UTF-8 all the way through.
      %x(#{config.pandoc} -f html -t #{target_format})
      end
    end
    private :convert_html

    def initialize(config, channel_data)
      @config, @channel_data = config, channel_data

      @header = channel_data['header']
      @items  = channel_data['items']

      @item_uids = Hash.new { |h, k| h[k] = {} }
      @attachments = Hash.new { |h, k| h[k] = {} }

      @blog_path = channel_path
    end

    def write
      items.each do |item|
        skip = false

        config.item_field_filter.each { |field, value|
          skip = item[field] == value
          break if skip
        }

        next if skip

        unless config.quiet
          config.stdout.write "."
          config.stdout.flush
        end

        out = nil
        yaml_header = {
          'title'         => item['title'],
          'date'          => item['date'], 
          'author'        => item['author'], 
          'slug'          => item['slug'], 
          'status'        => item['status'], 
          'wordpress_id'  => item['wp_id'], 
        }

        case item['type']
        when 'post'
          item['uid'] = item_uid(item, true)
          fn = item_path(item, '_posts')
          # out = open_file(fn)
          yaml_header['layout'] = 'post'
        when 'page'
          item['uid'] = item_uid(item)
          fn = item_path(item)
          # out = open_file(fn)
          yaml_header['layout'] = 'page'
        else
          if config.item_type_filter.include? item['type']
            nil
          else
            config.stderr.puts "Unknown item type #{item['type']}."
          end
        end

        if config.download_images
          item['img_srcs'].each do |image|
            nil
            # Download the attachment
            # urlretrieve(urljoin(data['header']['link'],
            # image.decode('utf-8')), attachment_path(image, item['uid']))
          end
        end

        taxonomies = Hash.new { |h, k| h[k] = [] }

        item['taxonomies'].each { |taxonomy, values|
          taxonomies[config.taxonomies[taxonomy] || taxonomy].push(*values)
        }

        File.open(fn, 'w') { |f|
          f.write "---\n"
          f.write yaml_header.to_yaml if yaml_header.size > 0
          f.write taxonomies.to_yaml if taxonomies.size > 0
          f.write "---\n\n"
          f.write convert_html(item['body'], config.target_format)
        }
      end

      config.stdout.puts unless config.quiet
    end

    def channel_path
      infix = config.path_infix || 'jekyll'
      name = header['link'].sub(/^https?/, '').sub(/[^-A-Za-z0-9_.]/, '')
      File.expand_path(File.join(config.build_dir, infix, name))
    end
    private :channel_path

    def full_path(path)
      fp = File.expand_path(File.join(blog_path, path))
      FileUtils.mkdir_p fp unless File.directory?(fp)
      fp
    end
    private :full_path

    def item_uid(item, date_prefix = false, namespace = '')
      if item_uids.include? item['wp_id']
        item_uids[namespace][item['wp_id']]
      else
        uid = ""

        if date_prefix
          date = DateTime.strptime(item['date'], config.date_fmt)
          uid << date.strftime("%Y-%m-%d") << '-'
        end

        title = item['slug']
        title = item['title'] if title.nil? or title.empty?
        if title.nil? or title.empty?
          warn "Could not find a title for an entry."
          title = 'untitled'
        end
        title.gsub!(/\s+/, '_')
        title.gsub!(/^[-A-Za-z0-9_]/, '')
        uid << title
        new_uid = uid

        n = 0
        while item_uids[namespace].include? new_uid
          n += 1
          new_uid = "#{uid}_#{n}"
        end

        item_uids[namespace][item['wp_id']] = new_uid
        new_uid
      end
    end
    private :item_uid

    def item_path(item, path = '')
      fp = full_path(path)
      ip = "#{item['uid']}.#{config.target_format}"
      File.join(fp, ip)
    end
    private :item_path

    def attachment_path(source, path, prefix = 'a')
      filename = attachments[path][source]

      unless filename
        # This needs to do URI parsing:
        # root, ext = os.path.splitext(os.path.basename(urlparse(source)[2]))
        uripath = Pathname.new(URI.parse(source).path)
        ext = uripath.extname
        root = uripath.basename(ext)
        infix = 1

        root = infix.to_s if root.nil? or root.empty?

        current = attachments.values
        maybe = "#{root}#{ext}"
        while current.include? maybe
          maybe = "#{root}-#{infix}#{ext}"
          infix += 1
        end
        filename = attachments[path][source] = maybe
      end

      target_path = File.expand_path(File.join(blog_path, prefix, path))
      target_file = File.expand_path(File.join(target_path, filename))

      FileUtils.mkdir_p target_path
      target_path
    end
    private :attachment_path
  end

  def write_jekyll(config, data)
    config.stdout.puts "Writing #{data['header']['title']}" unless config.quiet
    JekyllWriter.new(config, data).write
  end
  private :write_jekyll
end

# vim: ft=ruby
