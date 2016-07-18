module RedmineHelpdesk
  module Patches

    module IssuesControllerPatch
      def self.included(base) # :nodoc:
        base.send(:include, InstanceMethods)

        base.class_eval do
          unloadable
          before_filter :apply_helpdesk_macro, :only => :update
          after_filter :send_helpdesk_response, :only => :update
          after_filter :send_auto_answer, :only => :create

          alias_method_chain :build_new_issue_from_params, :helpdesk
          helper :helpdesk
        end
      end

      module InstanceMethods
        require 'timeout'

        def send_helpdesk_response
          return unless check_send_helpdesk_response? &&  @issue.current_journal &&  !@issue.current_journal.notes.blank?
          begin
            Timeout::timeout(60) do
              if msg = HelpdeskMailer.issue_response(@issue.customer, @issue.current_journal, params).deliver

                JournalMessage.create(:to_address => msg.to_addrs.first,
                                      :is_incoming => false,
                                      :message_date => Time.now,
                                      :message_id => msg.message_id,
                                      :source => HelpdeskTicket::HELPDESK_EMAIL_SOURCE,
                                      :cc_address => msg.cc.join(', '),
                                      :bcc_address => msg.bcc.join(', '),
                                      :contact => Contact.find_by_emails([msg.to_addrs.first]).first || @issue.customer,
                                      :journal => @issue.current_journal)

                flash[:notice].blank? ? flash[:notice] = l(:notice_email_sent, "<span class='icon icon-email'>" + msg.to_addrs.first  + "</span>") : flash[:notice] << " " + l(:notice_email_sent, "<span class='icon icon-email'>" + msg.to_addrs.first  + "</span>")
              end
            end
          rescue Exception => e
            flash[:error] = l(:label_helpdesk_email_sending_problems) + ": " + e.message if flash[:error].blank?
          end
        end

        def send_auto_answer
          return unless @issue && @issue.customer && User.current.allowed_to?(:send_response, @project)
          case params[:helpdesk_send_as].to_i
            when HelpdeskTicket::SEND_AS_NOTIFICATION
              msg = HelpdeskMailer.auto_answer(@issue.customer, @issue).deliver
            when HelpdeskTicket::SEND_AS_MESSAGE
              if msg = HelpdeskMailer.initial_message(@issue.customer, @issue, params).deliver
                @issue.helpdesk_ticket.message_id = msg.message_id
                @issue.helpdesk_ticket.save
              end
          end
          flash[:notice].blank? ? flash[:notice] = l(:notice_email_sent, "<span class='icon icon-email'>" + msg.to_addrs.first  + "</span>") : flash[:notice] << " " + l(:notice_email_sent, "<span class='icon icon-email'>" + msg.to_addrs.first  + "</span>") if msg
        rescue Exception => e
            flash[:error].blank? ? flash[:error] = e.message : flash[:error] << " " + e.message
        end

        def apply_helpdesk_macro
          return unless check_send_helpdesk_response?
          notes = (params[:notes] || (params[:issue].present? ? params[:issue][:notes] : nil))
          return if notes.blank?
          params[:notes] = HelpdeskMailer.apply_macro(notes, @issue.customer, @issue, User.current)
          params[:issue][:notes] = params[:notes] if params[:issue].present?
        end

        def check_send_helpdesk_response?
          !@conflict &&
              @issue &&
              @issue.valid? &&
              @issue.customer &&
              params[:helpdesk] && !params[:helpdesk][:is_send_mail].blank? &&
              @project.module_enabled?(:contacts_helpdesk) &&
              User.current.allowed_to?(:send_response, @project)
        end

        def build_new_issue_from_params_with_helpdesk
          build_new_issue_from_params_without_helpdesk
          return unless @issue
          if params[:helpdesk_ticket]
            params[:helpdesk_ticket][:is_incoming] = params[:helpdesk_send_as].to_i != HelpdeskTicket::SEND_AS_MESSAGE
          end
        end

      end
    end
  end
end

unless IssuesController.included_modules.include?(RedmineHelpdesk::Patches::IssuesControllerPatch)
  IssuesController.send(:include, RedmineHelpdesk::Patches::IssuesControllerPatch)
end
