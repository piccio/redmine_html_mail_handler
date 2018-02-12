module RedmineHtmlMailHandler
  class HtmlMailHandlerLogger < Logger
    def self.write(level, message)
      if Setting.plugin_redmine_html_mail_handler[:enable_log] == 'true'
        logger ||= new("#{Rails.root}/log/html_mail_handler.log")
        logger.send(level, message)
      end
    end
  end
end
