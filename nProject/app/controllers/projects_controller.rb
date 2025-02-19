# Redmine - project management software
# Copyright (C) 2006-2013  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class ProjectsController < ApplicationController
  menu_item :overview
  menu_item :roadmap, :only => :roadmap
  menu_item :settings, :only => :settings


  before_filter :find_project, :except => [ :index, :list, :new, :create, :copy ]
  before_filter :authorize, :except => [ :index, :list, :new, :create, :copy, :archive, :unarchive, :destroy, :show]
  before_filter :authorize_global, :only => [:new, :create]
  before_filter :require_admin, :only => [ :copy, :archive, :unarchive, :destroy ]
  accept_rss_auth :index
  accept_api_auth :index, :show, :create, :update, :destroy

  after_filter :only => [:create, :edit, :update, :archive, :unarchive, :destroy] do |controller|
    if controller.request.post?
      controller.send :expire_action, :controller => 'welcome', :action => 'robots'
    end
  end

  helper :sort
  include SortHelper
  helper :custom_fields
  include CustomFieldsHelper
  helper :issues
  helper :queries
  include QueriesHelper
  helper :repositories
  include RepositoriesHelper
  include ProjectsHelper
  helper :members
   
  #gantt chart 
  helper :gantt

  helper :projects
 
  include Redmine::Export::PDF

  # Lists visible projects
  def index
    respond_to do |format|
      format.html {
        scope = Project
        unless params[:closed]
          scope = scope.active
        end
        #@projects = scope.visible.order('lft').all
	@projects = User.current.memberships.collect(&:project).compact.select(&:active?).uniq
      }
      format.api  {
        @offset, @limit = api_offset_and_limit
        @project_count = Project.visible.count
        @projects = Project.visible.offset(@offset).limit(@limit).order('lft').all
      }
      format.atom {
        projects = Project.visible.order('created_on DESC').limit(Setting.feeds_limit.to_i).all
        render_feed(projects, :title => "#{Setting.app_title}: #{l(:label_project_latest)}")
      }
    end
  end

 

  def new
    @issue_custom_fields = IssueCustomField.sorted.all
    @trackers = Tracker.sorted.all
    @project = Project.new
    @project.safe_attributes = params[:project]
    
  end

  def create
    @issue_custom_fields = IssueCustomField.sorted.all
    @trackers = Tracker.sorted.all
    @project = Project.new
    @project.safe_attributes = params[:project]

    if validate_parent_id && @project.save
      @project.set_allowed_parent!(params[:project]['parent_id']) if params[:project].has_key?('parent_id')
      # Add current user as a project member if current user is not admin
      unless User.current.admin?
        r = Role.givable.find_by_id(Setting.new_project_user_role_id.to_i) || Role.givable.first
        m = Member.new(:user => User.current, :roles => [r])
        @project.members << m
      end
      respond_to do |format|
        format.html {
          flash[:notice] = l(:notice_successful_create)
          if params[:continue]
            attrs = {:parent_id => @project.parent_id}.reject {|k,v| v.nil?}
            redirect_to new_project_path(attrs)
          else
            redirect_to settings_project_path(@project)
          end
        }
        format.api  { render :action => 'show', :status => :created, :location => url_for(:controller => 'projects', :action => 'show', :id => @project.id) }
      end
    else
      respond_to do |format|
        format.html { render :action => 'new' }
        format.api  { render_validation_errors(@project) }
      end
    end
  end

  def copy
    @issue_custom_fields = IssueCustomField.sorted.all
    @trackers = Tracker.sorted.all
    @source_project = Project.find(params[:id])
    if request.get?
      @project = Project.copy_from(@source_project)
      @project.identifier = Project.next_identifier if Setting.sequential_project_identifiers?
    else
      Mailer.with_deliveries(params[:notifications] == '1') do
        @project = Project.new
        @project.safe_attributes = params[:project]
        if validate_parent_id && @project.copy(@source_project, :only => params[:only])
          @project.set_allowed_parent!(params[:project]['parent_id']) if params[:project].has_key?('parent_id')
          flash[:notice] = l(:notice_successful_create)
          redirect_to settings_project_path(@project)
        elsif !@project.new_record?
          # Project was created
          # But some objects were not copied due to validation failures
          # (eg. issues from disabled trackers)
          # TODO: inform about that
          redirect_to settings_project_path(@project)
        end
      end
    end
  rescue ActiveRecord::RecordNotFound
    # source_project not found
    render_404
  end

  # Show @project
  def show
    # try to redirect to the requested menu item
    if params[:jump] && redirect_to_project_menu_item(@project, params[:jump])
      return
    end

    
        # issues assigned to current user 

        @issuesAssignedToMe = @project.issues.where assigned_to_id: User.current.id
        @myIssues = @issuesAssignedToMe.where tracker_id: 5
        @myIssues = @myIssues.where(status_id: [1,2])
        @myIssues = @myIssues.reverse
    
        # tasks assigned to current user

        @tasksAssignedToMe = @project.issues.where assigned_to_id: User.current.id
        @myTasks = @tasksAssignedToMe.where tracker_id: 4
        @myTasks = @myTasks.where(status_id: [1,2])
        @myTasks = @myTasks.reverse
        
        #@tasks = TodoList.all
        # files attaced to users
        @allFiles = Attachment.all.reverse  
         

       @numberOfIssues =  @project.issues.count
       @numberOfOpenIssues =  @project.issues.where(status_id: [1,2])
       @openIssues = @numberOfOpenIssues.count
       numberOfNewIssues = @project.issues.where(status_id: 1)
       @newIssues = numberOfNewIssues.count
       @numberOfProgressIssues =  @project.issues.where(status_id: 2)
       @progressIssues = @numberOfProgressIssues.count

       # project summary page data
       @nIssues = @project.issues.where(status_id: 1, tracker_id: 5)
       @pIssues = @project.issues.where(status_id: 2, tracker_id: 5)
       @cIssues = @project.issues.where(status_id: 5, tracker_id: 5)
       @nTasks  = @project.issues.where(status_id: 1, tracker_id: 4)
       @pTasks  = @project.issues.where(status_id: 2, tracker_id: 4)
       @cTasks  = @project.issues.where(status_id: 5, tracker_id: 4)
       #@numberOfResolvedIssues =  @project.issues.where(status_id: 3)
       #@resolvedIssues = @numberOfResolvedIssues.count

       
       
       arrPissue = []
       arrNissue = []
       arrCissue = []
       arrNtask  = []
       arrPtask  = []
       arrCtask  = []

      @nIssues.each do |k|
        if k.assigned_to != nil
        arrNissue << k.assigned_to 
        end
     end
       @nIssueCounts = arrNissue.group_by{|i| i}.map{|k,v| [k, v.count] }

       @pIssues.each do |k|
         if k.assigned_to != nil
        arrPissue << k.assigned_to
       end
     end
       @pIssueCounts = arrPissue.group_by{|i| i}.map{|k,v| [k, v.count] }

       @cIssues.each do |k|
        if k.assigned_to != nil
        arrCissue << k.assigned_to
       end
     end
       @cIssueCounts = arrCissue.group_by{|i| i}.map{|k,v| [k, v.count] }

       @nTasks.each do |k|
        if k.assigned_to != nil
        arrNtask << k.assigned_to
       end
     end
       @nTaskCounts = arrNtask.group_by{|i| i}.map{|k,v| [k, v.count] }

       @pTasks.each do |k|
         if k.assigned_to != nil
        arrPtask << k.assigned_to
       end
     end
       @pTaskCounts = arrPtask.group_by{|i| i}.map{|k,v| [k, v.count] }

       @cTasks.each do |k|
         if k.assigned_to != nil
        arrCtask << k.assigned_to
       end
     end
       @cTaskCounts = arrCtask.group_by{|i| i}.map{|k,v| [k, v.count] }

       Rails.logger.info "Start Debugging"
         
         
         #@pIssueCounts.each {|k, v|
        #  puts "[#{k} = #{v}]"
        # }
       Rails.logger.info "Stop Debugging"

       @numberOfClosedIssues =  @project.issues.where(status_id: 5)
       @closedIssues = @numberOfClosedIssues.count


       @allFiles = @project.attachments.reverse

    @users_by_role = @project.users_by_role
    @subprojects = @project.children.visible.all
    @news = @project.news.limit(5).includes(:author, :project).reorder("#{News.table_name}.created_on DESC").all
    @trackers = @project.rolled_up_trackers

    cond = @project.project_condition(Setting.display_subprojects_issues?)

    @open_issues_by_tracker = Issue.visible.open.where(cond).count(:group => :tracker)
    @total_issues_by_tracker = Issue.visible.where(cond).count(:group => :tracker)
    
     # @callers = Caller.all
    @year ||= Date.today.year #returns 2013
  
    @month ||= Date.today.month #returns 12
    @calendarLocal = Redmine::Helpers::Calendar.new(Date.civil(@year,@month), current_language, :week)
    print @calendarLocal
    retrieve_query
    @query.group_by = nil
    if @query.valid?
      events = []
      events += @query.issues(:include => [:tracker, :assigned_to, :priority],
                              :conditions => ["((start_date BETWEEN ? AND ?) OR (due_date BETWEEN ? AND ?))", @calendarLocal.startdt, @calendarLocal.enddt, @calendarLocal.startdt, @calendarLocal.enddt]
                              )
      events += @query.versions(:conditions => ["effective_date BETWEEN ? AND ?", @calendarLocal.startdt, @calendarLocal.enddt])#

   @calendarLocal.events = events
  end

    if User.current.allowed_to?(:view_time_entries, @project)
      @total_hours = TimeEntry.visible.where(cond).sum(:hours).to_f
    end

    @key = User.current.rss_key

    respond_to do |format|
      format.html
      format.api
    end



  end

  def settings
    @issue_custom_fields = IssueCustomField.sorted.all
    @issue_category ||= IssueCategory.new
    @member ||= @project.members.new
    @trackers = Tracker.sorted.all
    @wiki ||= @project.wiki
  end

  def edit
  end

  def update
    @project.safe_attributes = params[:project]
    if validate_parent_id && @project.save
      @project.set_allowed_parent!(params[:project]['parent_id']) if params[:project].has_key?('parent_id')
      respond_to do |format|
        format.html {
          flash[:notice] = l(:notice_successful_update)
          redirect_to settings_project_path(@project)
        }
        format.api  { render_api_ok }
      end
    else
      respond_to do |format|
        format.html {
          settings
          render :action => 'settings'
        }
        format.api  { render_validation_errors(@project) }
      end
    end
  end

  def modules
    @project.enabled_module_names = params[:enabled_module_names]
    flash[:notice] = l(:notice_successful_update)
    redirect_to settings_project_path(@project, :tab => 'modules')
  end

  def archive
    if request.post?
      unless @project.archive
        flash[:error] = l(:error_can_not_archive_project)
      end
    end
    redirect_to admin_projects_path(:status => params[:status])
  end

  def unarchive
    @project.unarchive if request.post? && !@project.active?
    redirect_to admin_projects_path(:status => params[:status])
  end

  def close
    @project.close
    redirect_to project_path(@project)
  end

  def reopen
    @project.reopen
    redirect_to project_path(@project)
  end

  # Delete @project
  def destroy
    @project_to_destroy = @project
    if api_request? || params[:confirm]
      @project_to_destroy.destroy
      respond_to do |format|
        format.html { redirect_to admin_projects_path }
        format.api  { render_api_ok }
      end
    end
    # hide project in layout
    @project = nil
  end

  private

  # Validates parent_id param according to user's permissions
  # TODO: move it to Project model in a validation that depends on User.current
  def validate_parent_id
    return true if User.current.admin?
    parent_id = params[:project] && params[:project][:parent_id]
    if parent_id || @project.new_record?
      parent = parent_id.blank? ? nil : Project.find_by_id(parent_id.to_i)
      unless @project.allowed_parents.include?(parent)
        @project.errors.add :parent_id, :invalid
        return false
      end
    end
    true
  end
end
