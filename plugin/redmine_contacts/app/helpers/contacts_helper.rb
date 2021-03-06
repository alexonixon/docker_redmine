# encoding: utf-8
#
# This file is a part of Redmine CRM (redmine_contacts) plugin,
# customer relationship management plugin for Redmine
#
# Copyright (C) 2011-2014 Kirill Bezrukov
# http://www.redminecrm.com/
#
# redmine_contacts is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_contacts is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_contacts.  If not, see <http://www.gnu.org/licenses/>.

module ContactsHelper

  def contact_tabs(contact)
    contact_tabs = []
    contact_tabs << {:name => 'notes', :partial => 'contacts/notes', :label => l(:label_crm_note_plural)} if User.current.allowed_to?(:view_contacts, @project)
    contact_tabs << {:name => 'contacts', :partial => 'company_contacts', :label => l(:label_contact_plural) + (contact.company_contacts.visible.count > 0 ? " (#{contact.company_contacts.count})" : "")} if contact.is_company?
    contact_tabs << {:name => 'deals', :partial => 'deals/related_deals', :label => l(:label_deal_plural) + (contact.all_visible_deals.size > 0 ? " (#{contact.all_visible_deals.size})" : "") } if User.current.allowed_to?(:view_deals, @project)
    contact_tabs
  end

  def collection_for_visibility_select
    [[l(:label_crm_contacts_visibility_project), Contact::VISIBILITY_PROJECT],
     [l(:label_crm_contacts_visibility_public), Contact::VISIBILITY_PUBLIC],
     [l(:label_crm_contacts_visibility_private), Contact::VISIBILITY_PRIVATE]]
  end

  def authorized_for_permission?(permission, project, global = false)
    User.current.allowed_to?(permission, project, :global => global)
  end

  def render_contact_projects_hierarchy(projects)
    s = ''
    project_tree(projects) do |project, level|
      s << "<ul>"
      name_prefix = (level > 0 ? ('&nbsp;' * 2 * level + '&#187; ') : '')
        url = {:controller => 'contacts_projects',
               :action => 'delete',
               :related_project_id => project.id,
               :project_id => @project.id,
               :contact_id => @contact.id}

      s << "<li id='project_#{project.id}'>" + name_prefix + link_to_project(project)

      s += ' ' + link_to(image_tag('delete.png'),
                                 url,
                                 :remote => true,
                                 :method => :delete,
                                 :style => "vertical-align: middle",
                                 :class => "delete",
                                 :title => l(:button_delete)) if (projects.size > 1 && User.current.allowed_to?(:edit_contacts, project))
      s << "</li>"

      s << "</ul>"
    end
    s.html_safe
  end

  def contact_to_vcard(contact)
    return false unless ContactsSetting.vcard?

    card = Vcard::Vcard::Maker.make2 do |maker|

      maker.add_name do |name|
        name.prefix = ''
        name.given = contact.first_name.to_s
        name.family = contact.last_name.to_s
        name.additional = contact.middle_name.to_s
      end

      maker.add_addr do |addr|
        addr.preferred = true
        addr.street = contact.street1.to_s.gsub("\r\n"," ").gsub("\n"," ")
        addr.locality = contact.city.to_s
        addr.region = contact.region.to_s
        addr.postalcode = contact.postcode.to_s
        addr.country = contact.country.to_s
        addr.location = 'business'
      end

      maker.title = contact.job_title.to_s
      maker.org = contact.company.to_s
      maker.birthday = contact.birthday.to_date unless contact.birthday.blank?
      maker.add_note(contact.background.to_s.gsub("\r\n"," ").gsub("\n", ' '))

      maker.add_url(contact.website.to_s)

      contact.phones.each { |phone| maker.add_tel(phone) }
      contact.emails.each { |email| maker.add_email(email) }
    end
    avatar = contact.attachments.find_by_description('avatar')
    card = card.encode.sub("END:VCARD", "PHOTO;BASE64:" + "\n " + [File.open(avatar.diskfile).read].pack('m').to_s.gsub(/[ \n]/, '').scan(/.{1,76}/).join("\n ") + "\nEND:VCARD") if avatar && avatar.readable?

    card.to_s

  end
  def contacts_to_vcard(contacts)
    return "" unless User.current.allowed_to?(:export_contacts, @project, :global => true)
    contacts.map{|c| contact_to_vcard(c) }.join("\r\n")
  end

  def contacts_to_csv(contacts)
    return "" unless User.current.allowed_to?(:export_contacts, @project, :global => true)
    decimal_separator = l(:general_csv_decimal_separator)
    encoding = 'utf-8'
    export = FCSV.generate(:col_sep => l(:general_csv_separator)) do |csv|
      # csv header fields
      headers = [ "#",
                  l(:field_is_company, :locale => :en),
                  l(:field_contact_first_name, :locale => :en),
                  l(:field_contact_middle_name, :locale => :en),
                  l(:field_contact_last_name, :locale => :en),
                  l(:field_contact_job_title, :locale => :en),
                  l(:field_contact_company, :locale => :en),
                  l(:field_contact_phone, :locale => :en),
                  l(:field_contact_email, :locale => :en),
                  l(:label_crm_address, :locale => :en),
                  l(:label_crm_city, :locale => :en),
                  l(:label_crm_postcode, :locale => :en),
                  l(:label_crm_region, :locale => :en),
                  l(:label_crm_country, :locale => :en),
                  l(:field_contact_skype, :locale => :en),
                  l(:field_contact_website, :locale => :en),
                  l(:field_birthday, :locale => :en),
                  l(:field_contact_tag_names, :locale => :en),
                  l(:label_crm_assigned_to, :locale => :en),
                  l(:field_contact_background, :locale => :en)
                  ]
      # Export project custom fields if project is given
      # otherwise export custom fields marked as "For all projects"
      custom_fields = ContactCustomField.order(:name)
      custom_fields.each {|f| headers << f.name}
      # Description in the last column
      csv << headers.collect {|c| Redmine::CodesetUtil.from_utf8(c.to_s, encoding) }
      # csv lines
      contacts.each do |contact|
        fields = [contact.id,
                  contact.is_company ? 1 : 0,
                  contact.first_name,
                  contact.middle_name,
                  contact.last_name,
                  contact.job_title,
                  contact.company,
                  contact.phone,
                  contact.email,
                  contact.address.to_s.gsub("\r\n"," ").gsub("\n", ' '),
                  contact.city,
                  contact.postcode,
                  contact.region,
                  contact.country,
                  contact.skype_name,
                  contact.website,
                  format_date(contact.birthday),
                  contact.tag_list.to_s,
                  contact.assigned_to ? contact.assigned_to.name : "",
                  contact.background.to_s.gsub("\r\n"," ").gsub("\n", ' ')
                  ]
        contact.custom_field_values.each {|custom_value| fields << RedmineContacts::CSVUtils.csv_custom_value(custom_value) }
        csv << fields.collect {|c| Redmine::CodesetUtil.from_utf8(c.to_s, encoding) }
      end
    end
    export
  end

  def contacts_to_xls(contacts)
    return "" unless User.current.allowed_to?(:export_contacts, @project, :global => true)
    require 'spreadsheet'

    Spreadsheet.client_encoding = 'UTF-8'
    book = Spreadsheet::Workbook.new
    sheet = book.create_worksheet
    headers = [ "#",
            l(:field_is_company),
            l(:field_contact_first_name),
            l(:field_contact_middle_name),
            l(:field_contact_last_name),
            l(:field_contact_job_title),
            l(:field_contact_company),
            l(:field_contact_phone),
            l(:field_contact_email),
            l(:label_crm_address),
            l(:label_crm_city),
            l(:label_crm_postcode),
            l(:label_crm_region),
            l(:label_crm_country),
            l(:field_contact_skype),
            l(:field_contact_website),
            l(:field_birthday),
            l(:field_contact_tag_names),
            l(:field_contact_background)
            ]
    custom_fields = ContactCustomField.order(:name)
    custom_fields.each {|f| headers << f.name}
    idx = 0
    row = sheet.row(idx)
    row.replace headers

    contacts.each do |contact|
      idx += 1
      row = sheet.row(idx)
      fields = [contact.id,
                  contact.is_company ? 1 : 0,
                  contact.first_name,
                  contact.middle_name,
                  contact.last_name,
                  contact.job_title,
                  contact.company,
                  contact.phone,
                  contact.email,
                  contact.address.to_s.gsub("\r\n"," ").gsub("\n", ' '),
                  contact.city,
                  contact.postcode,
                  contact.region,
                  contact.country,
                  contact.skype_name,
                  contact.website,
                  format_date(contact.birthday),
                  contact.tag_list.to_s,
                  contact.background.to_s.gsub("\r\n"," ").gsub("\n", ' ')
                  ]
      contact.custom_field_values.each {|custom_value| fields << RedmineContacts::CSVUtils.csv_custom_value(custom_value) }
      row.replace fields
    end

    xls_stream = StringIO.new('')
    book.write(xls_stream)

    return xls_stream.string
  end

  def mail_macro(contact, message)
    message = message.gsub(/%%NAME%%/, contact.first_name)
    message = message.gsub(/%%FULL_NAME%%/, contact.name)
    message = message.gsub(/%%COMPANY%%/, contact.company) if contact.company
    message = message.gsub(/%%LAST_NAME%%/, contact.last_name) if contact.last_name
    message = message.gsub(/%%MIDDLE_NAME%%/, contact.middle_name) if contact.middle_name
    message = message.gsub(/%%DATE%%/, format_date(Date.today.to_s))

    contact.custom_field_values.each do |value|
      message = message.gsub(/%%#{value.custom_field.name}%%/, value.value.to_s)
    end
    message
  end

  def set_flash_from_bulk_contact_save(contacts, unsaved_contact_ids)
    if unsaved_contact_ids.empty?
      flash[:notice] = l(:notice_successful_update) unless contacts.empty?
    else
      flash[:error] = l(:notice_failed_to_save_contacts,
                        :count => unsaved_contact_ids.size,
                        :total => contacts.size,
                        :ids => '#' + unsaved_contact_ids.join(', #'))
    end
  end

  def render_contact_tabs(tabs)
    if tabs.any?
      render :partial => 'common/contact_tabs', :locals => {:tabs => tabs}
    else
      content_tag 'p', l(:label_no_data), :class => "nodata"
    end
  end


end
