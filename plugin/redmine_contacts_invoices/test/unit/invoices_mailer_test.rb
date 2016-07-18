# encoding: utf-8
#
# This file is a part of Redmine Invoices (redmine_contacts_invoices) plugin,
# invoicing plugin for Redmine
#
# Copyright (C) 2011-2013 Kirill Bezrukov
# http://www.redminecrm.com/
#
# redmine_contacts_invoices is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# redmine_contacts_invoices is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with redmine_contacts_invoices.  If not, see <http://www.gnu.org/licenses/>.

require File.expand_path('../../test_helper', __FILE__)

class InvoicesMailerTest < ActiveSupport::TestCase
  fixtures :projects,
           :users,
           :roles,
           :members,
           :member_roles,
           :issues,
           :issue_statuses,
           :versions,
           :trackers,
           :projects_trackers,
           :issue_categories,
           :enabled_modules,
           :enumerations,
           :attachments,
           :workflows,
           :time_entries

    ActiveRecord::Fixtures.create_fixtures(Redmine::Plugin.find(:redmine_contacts).directory + '/test/fixtures/',
                            [:contacts,
                             :contacts_projects,
                             :roles,
                             :enabled_modules])

    ActiveRecord::Fixtures.create_fixtures(Redmine::Plugin.find(:redmine_contacts_invoices).directory + '/test/fixtures/',
                          [:invoices,
                           :invoice_lines])

  def setup
    ActionMailer::Base.deliveries.clear
    Setting.host_name = 'mydomain.foo'
    Setting.protocol = 'http'
    Setting.plain_text_mail = '0'
  end

  def test_invoice_with_blank_options
    invoice = Invoice.find(1)
    assert InvoicesMailer.invoice(invoice).deliver
    mail = last_email
    assert_equal invoice.contact.primary_email, mail.to.first
    assert_equal Setting.mail_from, mail.from.first
    assert_equal "invoice-1/001.pdf", mail.attachments.first.filename
  end

  def test_invoice_with_current_user_email
    User.current = User.find(4)
    Setting.plugin_redmine_contacts_invoices["invoices_email_current_user"] = 1
    invoice = Invoice.find(1)
    assert InvoicesMailer.invoice(invoice).deliver
    mail = last_email
    assert_equal invoice.contact.primary_email, mail.to.first
    assert_equal User.current.mail, mail.from.first
    assert_equal "invoice-1/001.pdf", mail.attachments.first.filename
  end

  def test_invoice_with_options
    User.current = User.find(4)
    Setting.plugin_redmine_contacts_invoices["invoices_email_current_user"] = 1
    invoice = Invoice.find(1)
    assert InvoicesMailer.invoice(invoice,
                                  :to => "test@mail.to",
                                  :from => "from@mail.test",
                                  :message => "Message body").deliver
    mail = last_email
    assert_equal "test@mail.to", mail.to.first
    assert_equal "from@mail.test", mail.from.first
    assert_equal "invoice-1/001.pdf", mail.attachments.first.filename
    assert_match "Message body", mail.text_part.body.to_s
  end

  private

  def last_email
    mail = ActionMailer::Base.deliveries.last
    assert_not_nil mail
    mail
  end

end
