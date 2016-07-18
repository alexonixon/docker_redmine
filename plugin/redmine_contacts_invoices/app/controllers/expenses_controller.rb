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

class ExpensesController < ApplicationController
  unloadable

  before_filter :find_expense_project, :only => [:create, :new]
  before_filter :find_expense, :only => [:edit, :show, :destroy, :update]
  before_filter :bulk_find_expenses, :only => [:bulk_update, :bulk_edit, :bulk_destroy, :context_menu]
  before_filter :authorize, :except => [:index, :edit, :update, :destroy]
  before_filter :find_optional_project, :only => [:index]

  accept_api_auth :index, :show, :create, :update, :destroy

  helper :attachments
  helper :contacts
  helper :invoices
  helper :custom_fields
  helper :timelog
  helper :sort
  helper :context_menus
  include ExpensesHelper
  include InvoicesHelper
  include ContactsHelper
  include SortHelper

  def index
    @current_week_sum = Expense.sum_by_period("current_week", @project)
    @last_week_sum = Expense.sum_by_period("last_week", @project)
    @current_month_sum = Expense.sum_by_period("current_month", @project)
    @last_month_sum = Expense.sum_by_period("last_month", @project)
    @current_year_sum = Expense.sum_by_period("current_year", @project)

    @draft_status_sum, @draft_status_count = Expense.sum_by_status(Expense::DRAFT_EXPENSE, @project)
    @new_status_sum, @new_status_count = Expense.sum_by_status(Expense::NEW_EXPENSE, @project)
    @billed_status_sum, @billed_status_count = Expense.sum_by_status(Expense::BILLED_EXPENSE, @project)
    @paid_status_sum, @paid_status_count = Expense.sum_by_status(Expense::PAID_EXPENSE, @project)
    respond_to do |format|
      format.html do
         params[:status_id] = "o" unless params.has_key?(:status_id)
         @expenses = find_expenses
         render( :partial => expenses_list_style, :layout => false, :locals => {:expenses => @expenses}) if request.xhr?
      end
      format.api { @expenses = find_expenses }
      format.csv { send_data(expenses_to_csv(@expenses = find_expenses), :type => 'text/csv; header=present', :filename => 'expenses.csv') }
      format.pdf {render :pdf => "file_name", :layout => false}
    end
  end

  def edit
    @current_week_sum = Expense.sum_by_period("current_week", nil, @expense.contact_id)
    @last_week_sum = Expense.sum_by_period("last_week", nil, @expense.contact_id)
    @current_month_sum = Expense.sum_by_period("current_month", nil, @expense.contact_id)
    @last_month_sum = Expense.sum_by_period("last_month", nil, @expense.contact_id)
    @current_year_sum = Expense.sum_by_period("current_year", nil, @expense.contact_id)

    @draft_status_sum, @draft_status_count = Expense.sum_by_status(Expense::DRAFT_EXPENSE, nil, @expense.contact_id)
    @new_status_sum, @new_status_count = Expense.sum_by_status(Expense::NEW_EXPENSE, nil, @expense.contact_id)
    @billed_status_sum, @billed_status_count = Expense.sum_by_status(Expense::BILLED_EXPENSE, nil, @expense.contact_id)
    @paid_status_sum, @paid_status_count = Expense.sum_by_status(Expense::PAID_EXPENSE, nil, @expense.contact_id)

  end

  def show
  end

  def new
    @expense = Expense.new
    @expense.expense_date = Date.today
    @expense.currency = ContactsSetting.default_currency
  end

  def create
    @expense = Expense.new(params[:expense])
    # @invoice.contacts = [Contact.find(params[:contacts])]
    @expense.project = @project
    @expense.author = User.current
    if @expense.save
      attachments = Attachment.attach_files(@expense, (params[:attachments] || (params[:expense] && params[:expense][:uploads])))
      render_attachment_warning_if_needed(@expense)

      flash[:notice] = l(:notice_successful_create)

      respond_to do |format|
        format.html { redirect_to :action => "index", :project_id => @project }
        format.api  { render :action => 'show', :status => :created, :location => expense_url(@expense) }
      end
    else
      respond_to do |format|
        format.html { render :action => 'new' }
        format.api  { render_validation_errors(@expense) }
      end
    end

  end

  def update
    (render_403; return false) unless @expense.editable_by?(User.current)
    if @expense.update_attributes(params[:expense])
      attachments = Attachment.attach_files(@expense, (params[:attachments] || (params[:expense] && params[:expense][:uploads])))
      render_attachment_warning_if_needed(@expense)
      flash[:notice] = l(:notice_successful_update)
      respond_to do |format|
        format.html { redirect_to :action => "index", :project_id => @expense.project }
        format.api  { head :ok }
      end
    else
      respond_to do |format|
        format.html { render :action => "edit"}
        format.api  { render_validation_errors(@expense) }
      end
    end
  end

  def destroy
    (render_403; return false) unless @expense.destroyable_by?(User.current)
    if @expense.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = l(:notice_unsuccessful_save)
    end
    respond_to do |format|
      format.html { redirect_to :action => "index", :project_id => @expense.project }
      format.api  { head :ok }
    end

  end

  def context_menu
    @expense = @expenses.first if (@expenses.size == 1)
    @can = {:edit =>  @expenses.collect{|c| c.editable_by?(User.current)}.inject{|memo,d| memo && d},
            :delete => @expenses.collect{|c| c.destroyable_by?(User.current)}.inject{|memo,d| memo && d}
            }

    @back = back_url
    render :layout => false
  end

  def bulk_update
    unsaved_expense_ids = []
    @expenses.each do |expense|
      unless expense.update_attributes(parse_params_for_bulk_expense_attributes(params))
        # Keep unsaved issue ids to display them in flash error
        unsaved_expense_ids << expense.id
      end
    end
    set_flash_from_bulk_contact_save(@expenses, unsaved_expense_ids)
    redirect_back_or_default({:controller => 'expenses', :action => 'index', :project_id => @project})

  end

  def bulk_destroy
    @expenses.each do |expense|
      begin
        expense.reload.destroy
      rescue ::ActiveRecord::RecordNotFound # raised by #reload if issue no longer exists
        # nothing to do, issue was already deleted (eg. by a parent)
      end
    end
    respond_to do |format|
      format.html { redirect_back_or_default(:action => 'index', :project_id => @project) }
      format.api  { head :ok }
    end
  end

  private

  def find_expenses(pages=true)
    from, to = RedmineContacts::DateUtils.retrieve_date_range(params[:period].to_s)
    scope = Expense.scoped({})
    scope = scope.by_project(@project.id) if @project
    scope = scope.scoped(:conditions => ["#{Expense.table_name}.status_id = ?", params[:status_id]]) if (!params[:status_id].blank? && params[:status_id] != "o" && params[:status_id] != "d")
    scope = scope.scoped(:conditions => ["#{Expense.table_name}.status_id <> ?", Expense::PAID_EXPENSE]) if (params[:status_id] == "o") || (params[:status_id] == "d")
    scope = scope.scoped(:conditions => ["#{Expense.table_name}.is_billable = ?", params[:is_billable] == "1"]) unless params[:is_billable].blank?
    scope = scope.scoped(:conditions => ["#{Expense.table_name}.contact_id = ?", params[:contact_id]]) unless params[:contact_id].blank?
    scope = scope.scoped(:conditions => ["#{Expense.table_name}.assigned_to_id = ?", params[:assigned_to_id]]) unless params[:assigned_to_id].blank?
    scope = scope.scoped(:conditions => ["#{Expense.table_name}.expense_date BETWEEN ? AND ?", from, to]) if (from && to)

    sort_init ['status', ['expense_date', 'DESC']]
    sort_update 'status' => 'status_id',
                'expense_date' => 'expense_date',
                'price' => "#{Expense.table_name}.currency, #{Expense.table_name}.price",
                'contact' => ["#{Contact.table_name}.last_name", "#{Contact.table_name}.first_name"],
                'description' => "#{Expense.table_name}.description"

    scope = scope.visible
    scope = scope.includes(:contact)

    @expenses_count = scope.count
    @expenses_sum = scope.sum(:price, :group => :currency)
    scope = scope.scoped(:order => sort_clause) if sort_clause
    if pages
      @limit =  per_page_option
      @expenses_pages = Paginator.new(self, @expenses_count, @limit, params[:page])
      @offset = @expenses_pages.current.offset

      scope = scope.scoped :limit  => @limit, :offset => @offset
      @expenses = scope

      fake_name = @expenses.first.price if @expenses.length > 0 #without this patch paging does not work
    end

    scope
  end

  def parse_params_for_bulk_expense_attributes(params)
    attributes = (params[:expense] || {}).reject {|k,v| v.blank?}
    attributes.keys.each {|k| attributes[k] = '' if attributes[k] == 'none'}
    attributes[:custom_field_values].reject! {|k,v| v.blank?} if attributes[:custom_field_values]
    attributes
  end

  def bulk_find_expenses
    @expenses = Expense.find_all_by_id(params[:id] || params[:ids], :include => :project)
    raise ActiveRecord::RecordNotFound if @expenses.empty?
    if @expenses.detect {|expense| !expense.visible?}
      deny_access
      return
    end
    @projects = @expenses.collect(&:project).compact.uniq
    @project = @projects.first if @projects.size == 1
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_expense_project
    project_id = params[:project_id] || (params[:expense] && params[:expense][:project_id])
    @project = Project.find(project_id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_expense
    @expense = Expense.find(params[:id], :include => [:project, :contact])
    @project ||= @expense.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

end
