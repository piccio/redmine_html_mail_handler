namespace :redmine_html_mail_handler do
  desc "fix image src in (html formatted) issues' description and issues' notes (comments) after commit #"
  task fix_images_src: :environment do
    issues = Issue.all
    issues.map do |issue|
      doc = Nokogiri::HTML.fragment(issue.description)
      doc.search('.//img[@src]').each do |image|
        p "Issue=#{issue.inspect}"
        p "SRC before=#{image['src']}"
        src = image['src'].gsub(/[?]\d+\z/, '')
        image.set_attribute('src', src)
        p "SRC after=#{image['src']}"
      end
      raise 'Not Updated' unless issue.update_attribute(:description, doc.to_s)
    end

    journals = Journal.where(journalized_type: Issue)
    journals.map do |journal|
      doc = Nokogiri::HTML.fragment(journal.notes)
      doc.search('.//img[@src]').each do |image|
        p "Journal=#{journal.inspect}"
        p "SRC before=#{image['src']}"
        src = image['src'].gsub(/[?]\d+\z/, '')
        image.set_attribute('src', src)
        p "SRC after=#{image['src']}"
      end
      raise 'Not Updated' unless journal.update_attribute(:notes, doc.to_s)
    end
  end
end
