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

class ExpensesControllerTest < ActionController::TestCase
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
                           :invoice_lines,
                           :expenses
                           ])

  # TODO: Test for delete tags in update action

  def setup
    RedmineInvoices::TestCase.prepare

    @controller = ExpensesController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new

    User.current = nil
  end

  test "should get index" do
    # log_user('admin', 'admin')
    @request.session[:user_id] = 1
    Setting.default_language = 'en'

    get :index
    assert_response :success
    assert_template :index
    assert_not_nil assigns(:expenses)
    assert_nil assigns(:project)
  end

  test "should get index in project" do
    # log_user('admin', 'admin')
    @request.session[:user_id] = 1
    Setting.default_language = 'en'

    get :index, :project_id => 1
    assert_response :success
    assert_template :index
    assert_not_nil assigns(:expenses)
    assert_not_nil assigns(:project)
  end

  test "should get index deny user in project" do
    @request.session[:user_id] = 4
    get :index, :project_id => 1
    assert_response :forbidden
  end

  test "should get index with filters" do
    @request.session[:user_id] = 1
    get :index, :status_id => 1, :expenses_list_style => "list_excerpt"
    assert_response :success
    assert_template :index
    assert_select 'div#contact_list td.name.expense-name a', '01/31/2012 - Hosting'
    assert_select 'div#contact_list td.name.expense-name a', {:count => 0, :text => '1/002'}
  end

  test "should get index with sorting" do
    @request.session[:user_id] = 1
    get :index, :status_id => 1, :sort => "expense_date", :expenses_list_style => "list_excerpt"
    assert_response :success
    assert_template :index
    assert_not_nil assigns(:expenses)
    assert_select 'div#contact_list td.name.expense-name a', '01/31/2012 - Hosting'
    assert_select 'div#contact_list td.name.expense-name a', {:count => 0, :text => '1/002'}
  end

  test "should get new" do
    @request.session[:user_id] = 2
    get :new, :project_id => 1
    assert_response :success
    assert_template 'new'
    assert_select 'input#expense_price'
    assert_select 'input#expense_description'
  end

  test "should not get new by deny user" do
    @request.session[:user_id] = 4
    get :new, :project_id => 1
    assert_response :forbidden
  end


  test "should post create" do
    field = ExpenseCustomField.create!(:name => 'Test', :is_filter => true, :field_format => 'string')
    @request.session[:user_id] = 1
    assert_difference 'Expense.count' do
      post :create, "expense" => {"price"=>"140.0",
                                  "description"=>"New expense",
                                  "expense_date"=>"2011-12-01",
                                  "contact_id" => 2,
                                  "status_id"=>"1",
                                  :custom_field_values => {"#{field.id}" => "expense one"}},
                    "project_id"=>"ecookbook"
    end
    assert_redirected_to :controller => 'expenses', :action => 'index', :project_id => "ecookbook"

    expense = Expense.find_by_description('New expense')
    assert_not_nil expense
    assert_equal "expense one", expense.custom_field_values.last.value
  end

  test "should not post create by deny user" do
    @request.session[:user_id] = 4
    post :create, :project_id => 1,
        "expense" => {"price"=>"140.0"}
    assert_response :forbidden
  end

  test "should get edit" do
    @request.session[:user_id] = 1
    get :edit, :id => 1
    assert_response :success
    assert_template 'edit'
    assert_not_nil assigns(:expense)
    assert_equal Expense.find(1), assigns(:expense)
    assert_select 'input#expense_price[value=?]', "19.99"
    assert_select 'input#expense_description[value=?]', "Hosting"
  end

  test "should put update" do
    @request.session[:user_id] = 1

    expense = Expense.find(1)
    old_price = expense.price
    new_price = 67.10

    put :update, :id => 1, :expense => {:price => new_price}
    assert_redirected_to :action => 'index', :project_id => 'ecookbook'
    expense.reload
    assert_equal new_price, expense.price.to_f
  end

  test "should post destroy" do
    @request.session[:user_id] = 1
    delete :destroy, :id => 1
    assert_redirected_to :action => 'index', :project_id => 'ecookbook'
    assert_nil Expense.find_by_id(1)
  end

  test "should bulk_destroy" do
    @request.session[:user_id] = 1
    assert_not_nil Expense.find_by_id(1)
    delete :bulk_destroy, :ids => [1]
    assert_redirected_to :action => 'index', :project_id => 'ecookbook'
    assert_nil Expense.find_by_id(1)
  end

  test "should bulk_update" do
    @request.session[:user_id] = 1
    put :bulk_update, :ids => [1, 2], :expense => {:status_id => 2}
    assert_redirected_to :action => 'index', :project_id => 'ecookbook'
    assert Expense.find([1, 2]).all?{|e| e.status_id == 2}
  end

  test "should get context menu" do
    @request.session[:user_id] = 1
    xhr :get, :context_menu, :back_url => "/projects/ecookbok/expenses", :project_id => 'ecookbook', :ids => ['1', '2']
    assert_response :success
    assert_template 'context_menu'
  end

  test "should get index as csv" do
    field = ExpenseCustomField.create!(:name => 'Test custom field', :is_filter => true, :field_format => 'string')
    expense = Expense.find(1)
    expense.custom_field_values = {field.id => "This is custom значение"}
    expense.save

    @request.session[:user_id] = 1
    get :index, :format => 'csv'
    assert_response :success
    assert_not_nil assigns(:expenses)
    assert_equal "text/csv; header=present", @response.content_type
    assert @response.body.starts_with?("#,")
  end

  test 'should have import CSV link for user authorized to' do
    @request.session[:user_id] = 1
    get :index, :project_id => 1
    assert_response :success
    assert_select 'a#import_from_csv'
  end

end

