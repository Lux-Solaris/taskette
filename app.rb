# frozen_string_literal: true

require 'sinatra'
require 'sequel'

# 数据库创建
DB = Sequel.connect('sqlite://base.db')

# 任务列表
DB.create_table?(:tasks) do
  primary_key :id
  String  :title, null: false # 任务内容
  Integer :state, null: false # 默认: 0 DONE, 1 TODO
  Date    :deadline           # 空则表示 无 ddl
  Integer :priority           # 范围: 1 ~ 5
  String  :tag                # 任务标签
end

# 任务记录
DB.create_table?(:readmes) do
  primary_key :id
  foreign_key :task_id, :tasks, null: false
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
end

ensure_default_filter

# 插入一条任务
def insert_one_task(title = '', state: 1,
                    deadline: nil, priority: nil, tag: nil)
  DB[:tasks].insert(title: title, state: state,
                    deadline: deadline, priority: priority, tag: tag)
end

# 筛选任务
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
  # 查询函数
  def select_tasks
    basic = DB[:tasks].where(state: 1).where { deadline >= Date.today }
    filter = DB[:config_filters].where(key: 'filter').get(:value)

    filt_tasks(basic, filter)
  end
end

# 路由部分
get '/' do
  # 'Hello, Taskette!✨'
  @sicon = state_icon
  @stags = state_tags
  erb :index
end
