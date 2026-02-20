# frozen_string_literal: true

require 'sequel'

DB = Sequel.connect('sqlite://base.db')
DB.run("PRAGMA foreign_keys = ON;")

DB.create_table?(:tasks) do
  primary_key :id
  String  :title, null: false # 任务内容
  Integer :state, null: false # 默认: 0 DONE, 1 TODO
  Date    :deadline           # 空则表示 无 ddl
  Integer :priority           # 范围: 5 ~ 1
  String  :tag                # 任务标签
end

DB.create_table?(:config_filters) do
  String :key, primary_key: true
  String :value, null: false
end

def ensure_default_filter
  config = DB[:config_filters]
  config.insert(key: 'filter', value: 'all') unless config.where(key: 'filter').any?
  config.insert(key: 'day', value: '7') unless config.where(key: 'day').any?
  config.insert(key: 'tag', value: '') unless config.where(key: 'tag').any?
  config.insert(key: 'sorter', value: 'priority') unless config.where(key: 'sorter').any?
end

ensure_default_filter
MAX_DATE = Date.new(9999, 12, 31)

module TaskMan
  def self.create(title: '', state: 1,
                  deadline: '', priority: '', tag: '', **_rest)
    deadline = deadline == '' ? nil : Date.parse(deadline)
    priority = priority == '' ? nil : priority.to_i
    tag = nil if tag == ''

    DB[:tasks].insert(title: title, state: state,
                      deadline: deadline, priority: priority, tag: tag)
  end

  def self.complete(id)
    DB[:tasks].where(id: id).update(state: 0)
  end

  def self.delete(id)
    DB[:tasks].where(id: id).delete
  end

  def self.list
    basic = DB[:tasks].where(state: 1)
    filter = DB[:config_filters].where(key: 'filter').get(:value)
    sorter = DB[:config_filters].where(key: 'sorter').get(:value)

    filted = filt_tasks(basic, filter)
    sort_tasks(filted, sorter)
  end

  def self.all
    all = DB[:tasks].all
    result = sort_tasks(all, 'deadline')
  end

  private

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
end

DB.create_table?(:readmes) do
  primary_key :id
  foreign_key :task_id, :tasks, null: false, on_delete: :cascade
  String      :content, text: true
  DateTime    :time
end

module ReadmeMan
  def self.add(task_id:, content:)
    task_id = task_id.to_i unless task_id.is_a?(Integer)

    DB[:readmes].insert(
      task_id: task_id,
      content: content
    )
  end
end
