module RedmineHtmlMailHandler
  module MailHandlerPatch

    private

    attr_accessor :attributes_regexps

    # inspired by 'extract_keyword!' method
    def add_keywords_regexps(attr, keyword)
      keys = [attr.to_s.humanize]
      if attr.is_a?(Symbol)
        if user && user.language.present?
          keys << l("field_#{attr}", default: '', locale: user.language)
        end
        if Setting.default_language.present?
          keys << l("field_#{attr}", default: '', locale: Setting.default_language)
        end
      end
      keys.reject! { |k| k.blank? }
      keys.collect! { |k| Regexp.escape(k) }
      @attributes_regexps ||= []
      keyword = Regexp.escape(keyword.to_s)
      # http://rubular.com/r/3Qtpatl12d
      @attributes_regexps << /(<{1}[^<\/>]+>{1}\s*){,1}\s*(#{keys.join('|')})\s*(<{1}\/{1}[^<>]+>{1}\s*)*\s*(<{1}[^<>]+>{1}\s*)*\s*(:)\s*(<{1}\/{1}[^<>]+>{1}\s*)*\s*(<{1}[^<>]+>{1}\s*)*\s*(#{keyword})\s*(<{1}\/{1}[^<>]+>{1}\s*){,1}/i
    end

    # ERROR: wrong number of arguments (given 1, expected 0)
    # /home/sts_beta/redmine/plugins/redmine_html_mail_handler/lib/redmine_html_mail_handler/mail_handler_patch.rb:27:in `cleaned_up_text_body'
    # /home/sts_beta/redmine/plugins/redmine_ckeditor/lib/redmine_ckeditor/mail_handler_patch.rb:14:in `extract_keyword!'
    # /home/sts_beta/redmine/plugins/redmine_html_mail_handler/lib/redmine_html_mail_handler/mail_handler_patch.rb:46:in `extract_keyword!'
    # /home/sts_beta/redmine/app/models/mail_handler.rb:352:in `get_keyword'
    # the 'super' in the 'extract_keyword!' method above calls the 'extract_keyword!' method in ckeditor that, in turn,
    # calls my 'cleaned_up_text_body' method
    # https://github.com/a-ono/redmine_ckeditor/blob/810bd4212ed41be59d6219b759525127f5cd0bfb/lib/redmine_ckeditor/mail_handler_patch.rb#L14
    # unfortunately ckeditor overrides the 'cleaned_up_text_body' signature
    # https://github.com/a-ono/redmine_ckeditor/blob/810bd4212ed41be59d6219b759525127f5cd0bfb/lib/redmine_ckeditor/mail_handler_patch.rb#L5
    # then I have to follow its (bad) behaviour
    def cleaned_up_text_body(format = false)
      # http://stackoverflow.com/a/15098459
      caller =  caller_locations(1,1)[0].label
      if caller == 'receive_issue' || caller == 'receive_issue_reply'
        html_body
      else
        super
      end
    rescue => e
      # log error
      RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:error, "ERROR=#{e.message}")
      RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:error, "BACKTRACE=\n#{e.backtrace.join("\n")}")
      # raise error that can be catched by 'notify_invalid_mail_handler' plugin
      raise RedmineHtmlMailHandler::Error, e.message
    end

    # Stores keywords extracted from text mail body, they will be extracted from html mail body content forward
    def extract_keyword!(text, attr, format=nil)
      # original keyword extraction from text mail body
      keyword = super
      RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "ATTR=#{attr}")
      RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "KEYWORD=#{keyword}")

      # store extracted keyword
      add_keywords_regexps(attr, keyword) unless keyword.blank?

      # return keyword, same as original 'extract_keyword!' method
      keyword
    rescue => e
      # log error
      RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:error, "ERROR=#{e.message}")
      RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:error, "BACKTRACE=\n#{e.backtrace.join("\n")}")
      # raise error that can be catched by 'notify_invalid_mail_handler' plugin
      raise RedmineHtmlMailHandler::Error, e.message
    end

    # Returns false if the +attachment+ of the incoming email is already included inline in its body or
    # returns original method's value
    def accept_attachment?(attachment)
      if attachment.content_type.start_with?('image/') && attachment.content_disposition.start_with?('inline; ')
        false
      else
        super
      end
    rescue => e
      # log error
      RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:error, "ERROR=#{e.message}")
      RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:error, "BACKTRACE=\n#{e.backtrace.join("\n")}")
      # raise error that can be catched by 'notify_invalid_mail_handler' plugin
      raise RedmineHtmlMailHandler::Error, e.message
    end

    def plain_text_body
      return @plain_text_body unless @plain_text_body.nil?

      parts = if (text_parts = email.all_parts.select {|p| p.mime_type == 'text/plain'}).present?
                text_parts
              elsif (html_parts = email.all_parts.select {|p| p.mime_type == 'text/html'}).present?
                html_parts
              else
                [email]
              end

      parts.reject! do |part|
        part.header[:content_disposition].try(:disposition_type) == 'attachment'
      end

      @plain_text_body = parts.map do |p|
        body_charset = Mail::RubyVer.respond_to?(:pick_encoding) ?
                         Mail::RubyVer.pick_encoding(p.charset).to_s : p.charset
        body = Redmine::CodesetUtil.to_utf8(p.body.decoded, body_charset)
        # strip html nodes' content:
        # outlook client inserts a lot of '\n' inside html nodes (?!?)
        # and exchange server removes 'text/plain' parts forcing this method to parse html parts
        # therefore in some cases keywords are not recognized
        p.mime_type == 'text/html' ? strip_nodes(body) : body
      end.join("\r\n")

      # strip html tags and remove doctype directive
      if parts.any? {|p| p.mime_type == 'text/html'}
        @plain_text_body = strip_tags(@plain_text_body.strip)
        @plain_text_body.sub! %r{^<!DOCTYPE .*$}, ''
      end

      @plain_text_body
    end

    def strip_nodes(body)
      doc = Nokogiri::HTML.fragment(body)

      doc.search('.//text()').each do |node|
        node.replace(node.content.strip) unless node.content.blank?
      end

      doc
    end

    def html_body
      # same as plain_text_body method but with higher priority to html parts
      parts = if (html_parts = email.all_parts.select{ |p| p.mime_type == 'text/html' }).present?
                html_parts
              elsif (text_parts = email.all_parts.select{ |p| p.mime_type == 'text/plain' }).present?
                text_parts
              else
                [email]
              end

      parts.reject! do |part|
        part.header[:content_disposition].try(:disposition_type) == 'attachment'
      end

      # retrieve images
      images = retrieve_images(email.attachments)

      # sanitize config
      sanitize_elements = Sanitize::Config::RELAXED[:elements].dup
      sanitize_elements.delete('style')
      sanitize_protocols = Sanitize::Config::RELAXED[:protocols].merge(
        { 'img' => { 'src' => Sanitize::Config::RELAXED[:protocols]['img']['src'].dup << 'cid' } })
      sanitize_config = Sanitize::Config.merge(Sanitize::Config::RELAXED,
                                               elements: sanitize_elements,
                                               protocols: sanitize_protocols,
                                               remove_contents: true)

      # cleanup settings
      selectors = Setting.plugin_redmine_html_mail_handler['unwanted_nodes'].to_s.split(/[\r\n]+/).reject(&:blank?)

      parts.map do |p|
        RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:info, 'EMAIL PART')

        body_charset = Mail::RubyVer.respond_to?(:pick_encoding) ?
                         Mail::RubyVer.pick_encoding(p.charset).to_s : p.charset
        body = Redmine::CodesetUtil.to_utf8(p.body.decoded, body_charset)

        RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY=#{body}")

        if p.mime_type == 'text/html'
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:info, 'HTML')

          # sanitize html
          body = Sanitize.fragment(body, sanitize_config)
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY SANITIZED=#{body}")

          # parse html email body
          body = Nokogiri::HTML.fragment(body)

          # cleanup from attributes' keywords
          body = delete_keywords(body, attributes_regexps) if attributes_regexps.present? && ! attributes_regexps.empty?
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY CLEANED (keywords)=#{body}")

          # cleanup from unwanted nodes
          body = cleanup(body, selectors) unless selectors.empty?
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY CLEANED (signature)=#{body}")

          # strip empty html tags
          body = strip(body)
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY STRIPPED=#{body}")

          # replace images' references (src=cid:xyz) with images' file path (src='/relative/path/filename_of_xyz')
          body = insert_images(body, images) unless images.empty?
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY WITH IMAGES=#{body}")

          body.to_s
        else
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:info, 'PLAIN TEXT')

          # redcloth doesn't wrap in a paragraph if there is space after or before or between two \n
          # WARN: escape sequence doesn't work in single quote
          body = body.gsub(/([ ]*\n[ ]*\n[ ]*)/, "\n\n")
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY WITHOUT BAD BLANKS=#{body}")

          # convert text email to html
          # https://github.com/a-ono/redmine_ckeditor/issues/89
          body = RedCloth.new(body).to_html
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY CONVERTED=#{body}")

          # wrap in a div root node because xpath want it and I don't know if email have got it
          body = "<div>#{body}</div>"
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY WRAPPED=#{body}")

          # parse html email body
          body = Nokogiri::HTML.fragment(body)

          # cleanup from attributes' keywords
          body = delete_keywords(body, attributes_regexps) if attributes_regexps.present? && ! attributes_regexps.empty?
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY CLEANED (keywords)=#{body}")

          # cleanup from unwanted nodes
          body = cleanup(body, selectors) unless selectors.empty?
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY CLEANED (signature)=#{body}")

          # strip empty html tags
          body = strip(body)
          RedmineHtmlMailHandler::HtmlMailHandlerLogger.write(:debug, "BODY STRIPPED=#{body}")

          body.to_s
        end
      end.join
    end

    def retrieve_images(attachments)
      images = {}
      inline_attachments = attachments.select{ |a|
        a.content_type.start_with?('image/') && a.content_disposition.start_with?('inline; ') }
      inline_attachments.each do |attachment|
        # save image in the 'ckeditor' manner
        image = StringIO.new(attachment.body.decoded)
        file = Rich::RichFile.new(simplified_type: 'image')
        file.rich_file = image
        file.rich_file.instance_write(:file_name, attachment.filename)
        file.rich_file.instance_write(:content_type, attachment.mime_type)
        file.save!
        # store image's relative path (insert image will replace 'cid' with path)
        cid = /^<([\S]*)>$/.match(attachment[:content_id].value)[1]
        sub_uri = Rails.configuration.relative_url_root
        images["cid:#{cid}"] = "#{sub_uri}#{file.rich_file.url(:original, timestamp: false)}"
      end
      images
    end

    def cleanup(body, selectors)
      selectors.each do |selector|
        body.search(selector).each do |node|
          node.unlink
        end
      end
      body
    end

    def strip(body)
      body.children.each do |child|
        child.traverse do |node|
          # remove if is an empty node or if is a 'br' and have no content before
          node.unlink if is_empty?(node) || line_break_has_no_previous_sibling?(node)
        end
      end
      body
    end

    # return true if is an empty text node or if is not a text node and all its children are empty
    # skip 'img' and 'br' node that are empty by design
    def is_empty?(node)
      node.name != 'img' && node.name != 'br' &&
        (node.text? && node.text.strip.empty? || !node.text? && node.children.empty?)
    end

    # return true if 'br' has no previous sibling and its ancestors have no previous sibling also
    def line_break_has_no_previous_sibling?(node)
      node.name == 'br' && node.previous_sibling.nil? &&
        node.ancestors.all? { |ancestor| ancestor.previous_sibling.nil? }
    end

    def delete_keywords(body, attributes_regexps)
      body.traverse do |node|
        attributes_regexps.each do |regexp|
          serialized = node.serialize
          node.replace(serialized.gsub(regexp, '')) if serialized.match(regexp)
        end
      end
      body
    end

    def insert_images(body, images)
      body.search('.//img').each do |image|
        # replace 'cid' with path
        image.set_attribute('src', images[image['src']])
      end
      body
    end
  end
end