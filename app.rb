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
  config.insert(key: 'sorter', value: 'priority') unless config.where(key: 'sorter').any?
end

ensure_default_filter

# 插入一条任务
def insert_one_task(title = '', state: 1,
                    deadline: nil, priority: nil, tag: nil)
  DB[:tasks].insert(title: title, state: state,
                    deadline: deadline, priority: priority, tag: tag)
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
    tasks.sort_by { |row| [-row[:priority], row[:deadline]] }
  when 'deadline'
    tasks.sort_by { |row| [row[:deadline], -row[:priority]] }
  when 'tag'
    tasks.sort_by { |row| [row[:tag], -row[:priority], row[:deadline]] }
  else
    sort_tasks(tasks, 'priority')
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
    sorter = DB[:config_filters].where(key: 'sorter').get(:value)

    filted = filt_tasks(basic, filter)
    sort_tasks(filted, sorter)
  end

  # 打招呼的标题
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
end

# 路由部分
get '/' do
  # 看板
  # 'Hello, Taskette!✨'
  @sicon = state_icon
  @stags = state_tags
  erb :index
end

get '/tasks' do
  # 任务仓库
end

get '/config' do
  # 设置
end

get '/focus' do
  # 专注模式
end
