# frozen_string_literal: true

require 'sinatra'
require 'sequel'

# 数据库创建
DB = Sequel.connect('sqlite://base.db')

DB.create_table?(:tasks) do
  primary_key :id
  String  :title, null: false # 任务内容
  Integer :state, null: false # 默认: 0 DONE, 1 TODO
  Date    :deadline           # 空则表示 无 ddl
  Integer :priority           # 范围: 1 ~ 5
  String  :tag                # 任务标签
end

DB.create_table?(:readmes) do
  primary_key :id
  foreign_key :task_id, :tasks, null: false
  String      :content, text: true
  DateTime    :time
end

# 查询 n 天内待办
def get_tasks(ddl_n = 10)
  limit_date = Date.today + ddl_n
  DB[:tasks]
    .where(state: 1)
    .where { (deadline >= Date.today) & (deadline <= limit_date) }
    .order(:deadline, :priority)
end

def insert_one_task(title = '', state: 1,
                    deadline: nil, priority: nil, tag: nil)
  DB[:tasks].insert(title: title, state: state,
                    deadline: deadline, priority: priority, tag: tag)
end

state_tags = {
  1 => 'TODO',
  0 => 'DONE'
}
state_icon = {
  1 => '⬜',
  0 => '✅'
}
# 路由部分
get '/' do
  # 'Hello, Taskette!✨'
  @tasks = get_tasks
  @sicon = state_icon
  @stags = state_tags
  erb :index
end
