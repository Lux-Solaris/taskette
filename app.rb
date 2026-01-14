# frozen_string_literal: true

require 'sinatra'
require 'sequel'

# storage part
DB = Sequel.connect('sqlite://base.db')

DB.create_table?(:tasks) do
  primary_key :id
  String  :title, null: false # 任务内容
  Integer :state, null: false # 默认: 0 DONE, 1 TODO
  Date    :deadline           # 空则表示 无ddl
  Integer :priority           # 范围: 1 ~ 5
  String  :tag                # 任务标签
end

DB.create_table?(:readmes) do
  primary_key :id
  foreign_key :task_id, :tasks, null: false
  String      :content, text: true
  DateTime    :time
end

get '/' do
  'Hello, Taskette!✨'
end
