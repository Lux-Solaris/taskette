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
    tasks.where { deadline <= Date.today + deadtime }.all
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

def select_tasks_function
  basic = DB[:tasks].where(state: 1).where{ (deadline >= Date.today) | (deadline =~ nil) }
  filter = DB[:config_filters].where(key: 'filter').get(:value)
  sorter = DB[:config_filters].where(key: 'sorter').get(:value)

  filted = filt_tasks(basic, filter)
  sort_tasks(filted, sorter)
end

def select_first_task
  select_tasks_function[0]
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
  # For index.erb
  def select_tasks
    select_tasks_function
  end

  def greetings
    hour = Time.now.hour
    case hour

    when 5..11  then '早安呀～元气满满的一天开始啦! (๑•̀ㅂ•́)ﾉ✧'
    when 12..13 then '中午好! 记得吃饭饭哦～☀️'
    when 14..17 then '下午好! 一起摸摸鱼吧～(ﾉ≧∀≦)ﾉ'
    when 18..19 then '咕噜噜～该吃饭啦！今天也要好好喂饱自己呀～(๑•ᴗ•๑)♡'
    when 20..22 then '晚上好! 星星在对你眨眼睛✨'
    else
      '呜哇～快去睡觉觉! 看板酱盯着你呢！(;′⌒`)'
    end
  end

  # For tasks.erb
  def all_tasks
    all = DB[:tasks].all
    result = sort_tasks(all, 'deadline')
  end
end

# 路由部分
use Rack::MethodOverride

get '/' do
  # 看板
  # 'Hello, Taskette!✨'
  erb :index
end

get '/tasks' do
  # 任务仓库
  @sicon = state_icon
  @stags = state_tags
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

get '/focus' do
  # 专注模式
  if params[:id].nil? || params[:id].empty?
    id = select_first_task[:id]
    redirect to "/focus?id=#{id}"
  else
    id = params[:id].to_i
    @task = DB[:tasks].where(id: id).first
    @readmes = DB[:readmes].where(task_id: id).all
    erb :focus_show
  end
end

# 一些交互 / Interactions

get '/tasks/:id/complete' do
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

  redirect '/config'
end

# 调试用 INFO
get '/info/:info' do
  @info = params[:info]
  erb :info
end
