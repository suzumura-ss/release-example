#!/usr/bin/env ruby
require 'restclient'
require 'json'
require 'io/console'


# see https://developer.github.com/v3/repos/releases/
class GithubRelease
protected
  def api_uri
    "https://api.github.com/repos/#{@owner}/#{@repo}/releases"
  end

  def basic_request(method, uri = nil, payload: nil, content_type: :json, &block)
    raise StandardError, ':method is required' unless method
    arg = {
      method: method,
      url: uri || api_uri,
      headers: { accept: :json },
      user: @user,
      password: @password
    }
    if payload
      arg.merge!(payload: payload)
      arg[:headers].merge!(content_type: content_type)
    end
    JSON.parse(RestClient::Request.new(arg).execute(&block))
  end

  def api_get(uri: nil, &block)
    basic_request(:get, uri, &block)
  end

  def api_post(uri: nil, payload: nil, &block)
    raise StandardError, ':payload is required' unless payload
    basic_request(:post, uri, payload: payload.to_json, &block)
  end

  def api_post_binary(uri: nil, fd: nil, content_type: nil, &block)
    raise StandardError, ':uri is required' unless uri
    raise StandardError, ':fd is required' unless fd
    raise StandardError, ':content_type is required' unless content_type
    basic_request(:post, uri, payload: fd, content_type: content_type, &block)
  end

public
  # Initialize
  # IN user       account name for github
  # IN password   account password
  # IN owner      repository owner / use :user when :ower is nil
  # IN repo       repository name
  def initialize(user: nil, password: nil, owner: nil, repo: nil)
    raise RuntimeError, ':user is required' unless user
    raise RuntimeError, ':password is required' unless password
    raise RuntimeError, ':repo is required' unless repo
    @user = user
    @password = password
    @owner = owner || @user
    @repo = repo
  end

  # List releases for a repository
  #   see https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
  def releases
    api_get
  end

  # Create a release
  #   see https://developer.github.com/v3/repos/releases/#create-a-release
  # IN tag_name         The name of the tag.
  # IN target_commitish Specifies the commitish value. commit-SHA or tag-name('master')
  # IN name             The name of the release.
  # IN body             Text describing the contents of the tag.
  # IN draft            true to create a draft (unpublished) release.
  # IN prerelease       true to identify the release as a prerelease.
  def create_release(tag_name: nil, target_commitish: 'master', name: nil, body: nil, draft: false, prerelease: true)
    @upload_uri = nil
    raise RuntimeError, ':tag_name is required' unless tag_name
    raise RuntimeError, ':target_commitish is required' unless target_commitish
    raise RuntimeError, ':name is required' unless name
    raise RuntimeError, ':body is required' unless body
    payload = {tag_name: tag_name, target_commitish: target_commitish, name: name, body: body, draft: draft, prerelease: prerelease}
    res = api_post(payload: payload)
    @upload_uri = res['upload_url'].gsub(/\{.+\}\z/, '')
    res
  end

  # Upload a release asset
  #    see https://developer.github.com/v3/repos/releases/#upload-a-release-asset
  # IN upload_uri       upload_uri
  # IN filename         target filename
  # IN content_type     content type
  # IN name             asset name / default is basename of filename
  def upload_asset(upload_uri: @upload_uri, filename: nil, content_type: nil, name: nil)
    raise RuntimeError, ':filename is required' unless filename
    raise RuntimeError, ':content_type is required' unless content_type
    raise RuntimeError, ':upload_uri is required' unless upload_uri
    name ||= File.basename(filename)
    uri = URI.parse(upload_uri)
    uri.query  = "name=#{URI.escape(name)}"
    File.open(filename, 'rb'){|fd|
      api_post_binary(uri: uri.to_s, fd: fd, content_type: content_type)
    }
  end
end


def input_string(prompt, hide: false, crlf: false, default: nil)
  $stdout.sync = true
  loop do
    if default
      print "#{prompt} (#{default}) : "
    else
      print "#{prompt} : "
    end
    r = nil
    if hide
      r = $stdin.noecho(&:gets).to_s.strip
      puts
    else
      r = $stdin.gets.strip
    end
    r = default if r.nil? or r.empty?
    if crlf
      r.gsub!(/\\n|\\r/, "\n")
      r.gsub!(/\\\\/, "\\")
    end
    return r if r and !r.empty?
  end
end


if $0 == __FILE__
  path = URI.parse(`git remote -v`.split(/\n/).select{|l| l=~/^origin/ }[0].split[1]).path
  owner = input_string("owner", default: File.basename(File.dirname(path)))
  repo  = input_string("repo", default: File.basename(path, ".git"))
  user  = input_string("user", default: owner)
  pass  = input_string("password", hide: true)
  tag_name = input_string("tag name")
  name  = input_string("name", default: tag_name)
  body  = input_string("body", default: "Release #{name}", crlf: true)
  prerelease = true
  filename = input_string("filename")
  content_type = input_string("content type", default: 'application/zip')
  gr = GithubRelease.new(user: user, password: pass, owner: owner, repo: repo)
  gr.create_release(tag_name: tag_name, name: name, body: body, prerelease: prerelease)
  gr.upload_asset(filename: filename, content_type: content_type)
end
