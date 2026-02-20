# frozen_string_literal: true

require 'sinatra'
require 'sequel'

# 数据库创建
DB = Sequel.connect('sqlite://base.db')
DB.run("PRAGMA foreign_keys = ON;")

# 任务列表
DB.create_table?(:tasks) do
  primary_key :id
  String  :title, null: false # 任务内容
  Integer :state, null: false # 默认: 0 DONE, 1 TODO
  Date    :deadline           # 空则表示 无 ddl
  Integer :priority           # 范围: 5 ~ 1
  String  :tag                # 任务标签
end

# 任务记录
DB.create_table?(:readmes) do
  primary_key :id
  foreign_key :task_id, :tasks, null: false, on_delete: :cascade
  String      :content, text: true
  DateTime    :time
end

# 看板设置 - 筛选条件
DB.create_table?(:config_filters) do
  String :key, primary_key: true
  String :value, null: false
end

# 默认条件初始化
def ensure_default_filter
  config = DB[:config_filters]
  config.insert(key: 'filter', value: 'all') unless config.where(key: 'filter').any?
  config.insert(key: 'day', value: '7') unless config.where(key: 'day').any?
  config.insert(key: 'tag', value: '') unless config.where(key: 'tag').any?
  config.insert(key: 'sorter', value: 'priority') unless config.where(key: 'sorter').any?
end

ensure_default_filter
MAX_DATE = Date.new(9999, 12, 31)

# one_task 系列函数
def insert_one_task(title: '', state: 1,
                    deadline: '', priority: '', tag: '', **_rest)
  deadline = deadline == '' ? nil : Date.parse(deadline)
  priority = priority == '' ? nil : priority.to_i
  tag = nil if tag == ''

  DB[:tasks].insert(title: title, state: state,
                    deadline: deadline, priority: priority, tag: tag)
end

def complete_one_task(id)
  DB[:tasks].where(id: id).update(state: 0)
end

def delete_one_task(id)
  DB[:tasks].where(id: id).delete
end

# 关于 README 的函数
def add_one_readme(task_id:, content:)
  task_id = task_id.to_i unless task_id.is_a?(Integer)

  DB[:readmes].insert(
    task_id: task_id,
    content: content
  )
end

# 任务筛选与排序
def filt_tasks(tasks, filter)
  case filter
  when 'ddl'
    deadtime = DB[:config_filters].where(key: 'day').get(:value).to_i
    tasks.where { deadline >= Date.today }
         .where { deadline <= Date.today + deadtime }.all
  when 'tag'
    tag = DB[:config_filters].where(key: 'tag').get(:value)
    tasks.where(tag: tag).all
  when 'all' then tasks.all
  else []
  end
end

def sort_tasks(tasks, sorter)
  case sorter
  when 'priority'
    tasks.sort_by { |row| [-(row[:priority] || 0), row[:deadline] || MAX_DATE] }
  when 'deadline'
    tasks.sort_by { |row| [row[:deadline] || MAX_DATE, -(row[:priority] || 0)] }
  when 'tag'
    tasks.sort_by { |row| [row[:tag], -(row[:priority] || 0), row[:deadline] || MAX_DATE] }
  else
    sort_tasks(tasks, 'priority')
  end
end

def select_tasks
  basic = DB[:tasks].where(state: 1)
  filter = DB[:config_filters].where(key: 'filter').get(:value)
  sorter = DB[:config_filters].where(key: 'sorter').get(:value)

  filted = filt_tasks(basic, filter)
  sort_tasks(filted, sorter)
end

def select_first_task
  select_tasks[0]
end

def select_all_tasks
  all = DB[:tasks].all
  result = sort_tasks(all, 'deadline')
end

# 相关变量
state_tags = {
  1 => 'TODO',
  0 => 'DONE'
}
state_icon = {
  1 => '⬜',
  0 => '✅'
}

# 帮助函数
helpers do
  def safe_truncate(text, max=50, omission='...')
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

get '/' do
  # 看板
  # 'Hello, Taskette!✨'
  @tasks = select_tasks
  erb :index
end

get '/tasks' do
  # 任务仓库
  @sicon = state_icon
  @stags = state_tags
  @tasks = select_all_tasks
  erb :tasks
end

get '/config' do
  # 设置
  if params[:filter].nil? || params[:filter].empty?
    filter = DB[:config_filters].where(key: 'filter').get(:value)
    redirect to "/config?filter=#{filter}"
  else
    @config = DB[:config_filters].all.map { |h| [h[:key].to_sym, h[:value]] }.to_h
    @available_tags = DB[:tasks].select_map(:tag).uniq
    erb :config
  end
end

get '/tasks/:id/edit' do
  # 编辑模式
  id = params[:id].to_i
  puts id
  @task = DB[:tasks].where(id: id).first
  @readmes = DB[:readmes].where(task_id: id).all
  @available_tags = DB[:tasks].select_map(:tag).uniq
  erb :edit
end

get '/focus' do
  # 专注模式
  if params[:id].nil? || params[:id].empty?
    first_task = select_first_task
    id = first_task.nil? ? 0 : first_task[:id]
    redirect to "/focus?id=#{id}"
  else
    id = params[:id].to_i
    @task = DB[:tasks].where(id: id).first
    @readmes = DB[:readmes].where(task_id: id).all
    erb :focus
  end
end

# 一些交互 / Interactions

post '/tasks/:id/complete' do
  complete_one_task(params[:id])
  redirect to '/'
end

post '/tasks' do
  id = insert_one_task(
    title: params[:title],
    deadline: params[:deadline],
    priority: params[:priority],
    tag: params[:tag]
  )
  unless params[:readme] == ''
    add_one_readme(task_id: id,
                   content: params[:readme])
  end
  redirect to '/tasks'
end

delete '/tasks/:id' do
  delete_one_task(params[:id])
  redirect to '/tasks'
end

post '/config' do
  filter = params[:current_filter] || 'all'
  sorter = params[:sorter] || 'priority'

  DB[:config_filters].where(key: 'filter').update(value: filter)
  DB[:config_filters].where(key: 'sorter').update(value: sorter)

  if filter == 'ddl'
    day = [params[:day].to_i, 1].max.to_s
    DB[:config_filters].where(key: 'day').update(value: day)

  elsif filter == 'tag'
    tag = params[:tag] || ''
    DB[:config_filters].where(key: 'tag').update(value: tag)
  end

  redirect to '/config'
end

put '/tasks/:id' do
  id = params[:id].to_i
  original = DB[:tasks].where(id: id).first
  DB[:tasks].where(id: id).update(title: params[:title]) if original[:title] != params[:title]
  deadline = params[:deadline] == '' ? nil : Date.parse(params[:deadline])
  priority = params[:priority] == '' ? nil : params[:priority].to_i
  DB[:tasks].where(id: id).update(deadline: deadline) if original[:deadline] != deadline
  DB[:tasks].where(id: id).update(priority: priority) if original[:priority] != priority
  DB[:tasks].where(id: id).update(tag: params[:tag]) if original[:tag] != params[:tag]
  DB[:readmes].insert(task_id: id, content: params[:new_readme]) if params[:new_readme].delete("\n\r") != ''

  redirect to "/focus?id=#{id}"
end

delete '/readmes/:id' do
  id = params[:id].to_i
  task_id = DB[:readmes].where(id: id).get(:task_id)
  DB[:readmes].where(id: id).delete

  redirect to "/tasks/#{task_id}/edit"
end

# 调试用 INFO
get '/info/:info' do
  @info = params[:info]
  erb :info
end
