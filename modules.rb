# frozen_string_literal: true

require 'sequel'

DB = Sequel.connect('sqlite://base.db')
DB.run('PRAGMA foreign_keys = ON;')

STATE_TODO = 1
STATE_DONE = 0

STATE_TAGS = {
  STATE_TODO => 'TODO',
  STATE_DONE => 'DONE'
}.freeze

STATE_ICON = {
  STATE_TODO => '⬜',
  STATE_DONE => '✅'
}.freeze

DB.create_table?(:tasks) do
  primary_key :id
  String  :title, null: false # 任务内容
  Integer :state, null: false # 默认: 0 DONE, 1 TODO
  Date    :deadline           # 空则表示 无 ddl
  Integer :priority           # 范围: 5 ~ 1
  String  :tag                # 任务标签
end

DB.create_table?(:timestamps) do
  Integer  :task_id
  String   :descriptor
  DateTime :value, null: false

  primary_key [:task_id, :descriptor]
  foreign_key [:task_id], :tasks, null: false, on_delete: :cascade
end

DB.create_table?(:readmes) do
  primary_key :id
  foreign_key :task_id, :tasks, null: false, on_delete: :cascade
  String      :content, text: true
  DateTime    :time
end

DB.create_table?(:config) do
  String :key, primary_key: true
  String :value, null: false
end

def ensure_default_config
  config = DB[:config]
  config_pairs = {
    'filter' => 'all',
    'day' => '7',
    'tag' => '',
    'sorter' => 'priority'
  }
  config_pairs.each_pair { |k, v| config.insert(key: k, value: v) unless config.where(key: k).any? }
end

ensure_default_config
MAX_DATE = Date.new(9999, 12, 31)

module TaskMan
  def self.create(title: '', state: STATE_TODO,
                  deadline: '', priority: '', tag: '')
    deadline = deadline == '' ? nil : Date.parse(deadline)
    priority = priority == '' ? nil : priority.to_i
    tag = nil if tag == ''

    DB[:tasks].insert(title: title, state: state,
                      deadline: deadline, priority: priority, tag: tag)
  end

  def self.update(id:, title:, deadline:, priority:, tag:)
    DB.transaction do
      original = DB[:tasks].where(id: id).first
      deadline = deadline == '' ? nil : Date.parse(deadline)
      priority = priority == '' ? nil : priority.to_i
      DB[:tasks].where(id: id).update(title: title) if original[:title] != title
      DB[:tasks].where(id: id).update(deadline: deadline) if original[:deadline] != deadline
      DB[:tasks].where(id: id).update(priority: priority) if original[:priority] != priority
      DB[:tasks].where(id: id).update(tag: tag) if original[:tag] != tag
    end
  end

  def self.complete(id)
    DB[:tasks].where(id: id).update(state: STATE_DONE)
    TimestampMan.mark(task_id: id, descriptor: 'DONE')
  end

  def self.toggle(id)
    DB.transaction do
      state = DB[:tasks].where(id: id).get(:state)
      DB[:tasks].where(id: id).update(state: state == STATE_TODO ? STATE_DONE : STATE_TODO)
      if state == STATE_TODO
        TimestampMan.mark(task_id: id, descriptor: 'DONE')
      else
        TimestampMan.unmark(task_id: id, descriptor: 'DONE')
      end
    end
  end

  def self.delete(id)
    DB[:tasks].where(id: id).delete
  end

  def self.find(id)
    DB[:tasks].where(id: id).first
  end

  def self.list
    basic = DB[:tasks].where(state: STATE_TODO)
    config = DB[:config].to_hash(:key, :value)
    filter = config['filter']
    sorter = config['sorter']

    filted = filt_tasks(basic, filter)
    sort_tasks(filted, sorter)
  end

  def self.all
    raw = DB[:tasks].left_join(:timestamps, task_id: :id, descriptor: 'DONE')
      .select(Sequel[:tasks].*, Sequel[:timestamps][:value].as(:done_time))
      .all
    sort_tasks(raw, 'deadline')
  end

  def self.all_tags
    DB[:tasks].select_map(:tag).uniq
  end

  private

  def self.filt_tasks(tasks, filter)
    case filter
    when 'ddl'
      deadtime = DB[:config].where(key: 'day').get(:value).to_i
      tasks.where { deadline >= Date.today }
        .where { deadline <= Date.today + deadtime }.all
    when 'tag'
      tag = DB[:config].where(key: 'tag').get(:value)
      tasks.where(tag: tag).all
    when 'all' then tasks.all
    else []
    end
  end

  def self.sort_tasks(tasks, sorter)
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

module TimestampMan
  def self.fetch(task_id:, descriptor:)
    DB[:timestamps].where(task_id: task_id, descriptor: descriptor).get(:value)
  end

  def self.mark(task_id:, descriptor:)
    time = DateTime.now
    DB.transaction do
      result = DB[:timestamps].where(task_id: task_id, descriptor: descriptor).update(value: time)
      if result == 0
        DB[:timestamps].insert(task_id: task_id, descriptor: descriptor, value: time)
      end
    end
  end

  def self.unmark(task_id:, descriptor:)
    DB[:timestamps].where(task_id: task_id, descriptor: descriptor).delete
  end
end

module ReadmeMan
  def self.add?(task_id:, content:)
    return if empty_text?(content)

    add(task_id: task_id, content: content)
  end

  def self.add(task_id:, content:)
    task_id = task_id.to_i unless task_id.is_a?(Integer)

    DB[:readmes].insert(
      task_id: task_id,
      content: content,
      time: DateTime.now
    )
  end

  def self.delete(id)
    task_id = DB[:readmes].where(id: id).get(:task_id)
    DB[:readmes].where(id: id).delete

    task_id
  end

  def self.list_match(task_id:)
    DB[:readmes].where(task_id: task_id).all
  end

  private

  def self.empty_text?(content)
    content.delete("\n\r ") == ''
  end
end

module ConfigMan
  def self.config_pairs_hashed
    DB[:config].all.map { |h| [h[:key].to_sym, h[:value]] }.to_h
  end

  def self.filter
    DB[:config].where(key: 'filter').get(:value)
  end

  def self.sorter
    DB[:config].where(key: 'sorter').get(:value)
  end

  def self.day
    DB[:config].where(key: 'day').get(:value)
  end

  def self.tag
    DB[:config].where(key: 'tag').get(:value)
  end

  def self.filter=(new_filter)
    DB[:config].where(key: 'filter').update(value: new_filter)
  end

  def self.sorter=(new_sorter)
    DB[:config].where(key: 'sorter').update(value: new_sorter)
  end

  def self.day=(new_day)
    DB[:config].where(key: 'day').update(value: new_day)
  end

  def self.tag=(new_tag)
    DB[:config].where(key: 'tag').update(value: new_tag)
  end
end
