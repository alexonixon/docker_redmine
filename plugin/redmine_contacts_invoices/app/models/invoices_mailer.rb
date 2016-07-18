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

class InvoicesMailer < ActionMailer::Base
  unloadable
  include Redmine::I18n
  include InvoicesHelper
  helper :invoices

  def invoice(invoice, options={})
    @invoice = invoice
    @project = invoice.project
    recipients = options[:to].blank? ? invoice.contact.try(:primary_email) : options[:to].to_s
    from = options[:from].blank? ? InvoicesSettings.email_from_address : options[:from].to_s
    subject = options[:subject].blank? ? "#{l(:label_invoice)} #{invoice.number} (#{InvoicesSettings[:invoices_company_name, invoice.project].to_s})" : options[:subject].to_s
    @email_body = options[:message].to_s

    headers['X-Invoice-Id'] = invoice.number

    attachments[invoice.filename] = invoice_to_pdf(@invoice)

    mail :to => recipients,
         :from => from,
         :cc => options[:cc].to_s,
         :bcc => options[:bcc].to_s,
         :subject => subject
  end

end
