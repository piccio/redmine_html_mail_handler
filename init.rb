require 'redmine_html_mail_handler/mail_handler_patch'
require 'redmine_html_mail_handler/html_mail_handler_logger'
require 'redmine_html_mail_handler/error'

Rails.configuration.to_prepare do
  # plugin does its actions only if ckeditor plugin is present
  if Redmine::Plugin.registered_plugins[:redmine_ckeditor].present?
    unless MailHandler.included_modules.include? RedmineHtmlMailHandler::MailHandlerPatch
      MailHandler.send(:include, RedmineHtmlMailHandler::MailHandlerPatch)
    end
  end
end

Redmine::Plugin.register :redmine_html_mail_handler do
  name 'Redmine Html Mail Handler plugin'
  author 'Roberto Piccini'
  description 'accept HTML email (requires ckeditor plugin)'
  version '0.0.1'
  url 'https://github.com/piccio/redmine_html_mail_handler'
  author_url 'https://github.com/piccio'
  requires_redmine version: '2.6.0'

  settings default: { unwanted_nodes: nil, enable_log: false }, partial: 'settings/html_mail_handler'
end
