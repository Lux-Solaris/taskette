# frozen_string_literal: true

require 'sinatra'
require_relative 'modules'


# 帮助函数
helpers do
  def safe_truncate(text, max = 50, omission = '...')
    return text if text.length <= max

    "#{text[0, max - omission.length]}#{omission}"
  end

  def task_overdue?(task)
    return false if task[:deadline].nil?
    task[:deadline] < Date.today
  end
end

# 路由部分
use Rack::MethodOverride

# ===== 首页和通用资源 =====

get '/' do
  # 'Hello, Taskette!✨'
  @tasks = TaskMan.list
  erb :index
end

get '/focus' do
  first_task = TaskMan.list.first
  id = first_task.nil? ? 0 : first_task[:id]
  redirect to "/tasks/#{id}"
end

# ===== 任务资源 =====

get '/tasks' do
  @sicon = STATE_ICON
  @stags = STATE_TAGS
  @tasks = TaskMan.all
  erb :tasks
end

get '/tasks/:id/edit' do
  id = params[:id].to_i
  @task = TaskMan.find(id)
  @readmes = ReadmeMan.list_match(task_id: id)
  @available_tags = TaskMan.all_tags
  erb :edit
end

get '/tasks/:id' do
  id = params[:id].to_i
  @task = TaskMan.find(id)
  @readmes = ReadmeMan.list_match(task_id: id)
  erb :focus
end

post '/tasks' do
  id = TaskMan.create(title: params[:title],
                      deadline: params[:deadline],
                      priority: params[:priority],
                      tag: params[:tag])

  unless params[:readme] == ''
    ReadmeMan.add(task_id: id,
                  content: params[:readme])
  end
  redirect to '/tasks'
end

post '/tasks/:id/complete' do
  TaskMan.complete(params[:id])
  redirect to '/'
end

post '/tasks/:id/toggle' do
  TaskMan.toggle(params[:id])
  redirect to '/tasks'
end

put '/tasks/:id' do
  id = params[:id].to_i

  TaskMan.update(id: id,
                 title: params[:title],
                 deadline: params[:deadline],
                 priority: params[:priority],
                 tag: params[:tag])

  ReadmeMan.add?(task_id: id, content: params[:new_readme])

  redirect to "/tasks/#{id}"
end

delete '/tasks/:id' do
  TaskMan.delete(params[:id])
  redirect to '/tasks'
end

# ===== README 资源 =====

delete '/readmes/:id' do
  id = params[:id].to_i
  task_id = ReadmeMan.delete(id)

  redirect to "/tasks/#{task_id}/edit"
end

# ===== 配置资源 =====

get '/config' do
  if params[:filter].nil? || params[:filter].empty?
    filter = ConfigMan.filter
    redirect to "/config?filter=#{filter}"
  else
    @config = ConfigMan.config_pairs_hashed
    @available_tags = TaskMan.all_tags
    erb :config
  end
end

post '/config' do
  new_filter = params[:current_filter] || 'all'
  new_sorter = params[:sorter] || 'priority'

  ConfigMan.filter = new_filter
  ConfigMan.sorter = new_sorter

  if new_filter == 'ddl'
    new_day = [params[:day].to_i, 1].max.to_s
    ConfigMan.day = new_day

  elsif new_filter == 'tag'
    new_tag = params[:tag] || ''
    ConfigMan.tag = new_tag
  end

  redirect to '/config'
end

# 调试用 INFO
get '/info/:info' do
  @info = params[:info]
  erb :info
end
