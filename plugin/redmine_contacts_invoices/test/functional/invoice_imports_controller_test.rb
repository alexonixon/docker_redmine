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

class InvoiceImportsControllerTest < ActionController::TestCase
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
           :custom_fields,
           :custom_values,
           :custom_fields_projects,
           :custom_fields_trackers,
           :time_entries,
           :journals,
           :journal_details,
           :queries

    ActiveRecord::Fixtures.create_fixtures(Redmine::Plugin.find(:redmine_contacts).directory + '/test/fixtures/',
                            [:contacts,
                             :contacts_projects,
                             :contacts_issues,
                             :deals,
                             :notes,
                             :roles,
                             :enabled_modules,
                             :tags,
                             :taggings,
                             :contacts_queries])

    ActiveRecord::Fixtures.create_fixtures(Redmine::Plugin.find(:redmine_contacts_invoices).directory + '/test/fixtures/',
                          [:invoices,
                           :invoice_lines])

  # TODO: Test for delete tags in update action

  def setup
    RedmineInvoices::TestCase.prepare

    @controller = InvoiceImportsController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new

    User.current = nil
  end

  test 'should open invoice import form' do
    @request.session[:user_id] = 1
    get :new, :project_id => 1
    assert_response :success
    assert_select 'form.new_invoice_import'
  end

  test 'should successfully import from CSV' do
    @request.session[:user_id] = 1
    assert_difference('Invoice.count', 1, 'Should add 1 invoice the database') do
      post :create, {
        :project_id => 1,
        :invoice_import => {
          :file => Rack::Test::UploadedFile.new(fixture_files_path + "invoices_correct.csv", 'text/comma-separated-values'),
          :quotes_type => '"'
          }
      }
      assert_redirected_to project_invoices_path(:project_id => 1)
    end
    assert_equal 'Draft', Invoice.last.status
  end

end
