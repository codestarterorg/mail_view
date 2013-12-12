require 'erb'
require 'tilt'

require 'rack/mime'

class MailView
  class NotFound < StandardError; end

  autoload :Mapper, 'mail_view/mapper'

  class << self
    attr_reader :allow_browse_index

    def default_email_template_path
      File.expand_path('../mail_view/email.html.erb', __FILE__)
    end

    def default_index_template_path
      File.expand_path('../mail_view/index.html.erb', __FILE__)
    end

    def browse_index(browseable)
      allow_browse_index = browseable
    end

    def call(env)
      new.call(env)
    end

  end

  @allow_browse_index = true

  def call(env)
    @rack_env = env
    path_info = env["PATH_INFO"]

    if path_info == "" || path_info == "/" and self.class.allow_browse_index
      if self.class.const_defined? 'MAILERS'
        links = self.class.const_get('MAILERS')
      else
        links = self.actions.map do |action|
          [action, "#{env["SCRIPT_NAME"]}/#{action}"]
        end
      end

      ok index_template.render(Object.new, :links => links, :script_name => env['SCRIPT_NAME'])
    elsif actions.include? path_info.split('/')[1]
      action_name = path_info.split('/')[1]
      begin
        ok render_mail(action_name, send(action_name), 'html')
      rescue NotFound
        not_found(true)
      end
    elsif path_info =~ /([\w_]+)(\.\w+)?$/
      name   = $1
      format = $2 || ".html"

      if actions.include?(name)
        begin
          ok render_mail(name, send(name), format)
        rescue NotFound
          not_found(true)
        end
      else
        not_found
      end
    else
      not_found(true)
    end
  end

protected

  def actions
    public_methods(false).map(&:to_s).sort - ['call']
  end

  def email_template
    Tilt.new(email_template_path)
  end

  def email_template_path
    self.class.default_email_template_path
  end

  def index_template
    Tilt.new(index_template_path)
  end

  def index_template_path
    self.class.default_index_template_path
  end

private

  def ok(body)
    [200, {"Content-Type" => "text/html"}, [body]]
  end

  def not_found(pass = false)
    if pass
      [404, {"Content-Type" => "text/html", "X-Cascade" => "pass"}, ['Not Found']]
    else
      [404, {"Content-Type" => "text/html"}, ['Not Found']]
    end
  end

  def render_mail(name, mail, format = nil)
    body_part = mail

    if body_part
      if mail.multipart?
        content_type = Rack::Mime.mime_type(format)
        body_part = if mail.respond_to?(:all_parts)
                      mail.all_parts.find { |part| part.content_type.match(content_type) } || mail.parts.first
                    else
                      mail.parts.find { |part| part.content_type.match(content_type) } || mail.parts.first
                    end
      end

      email_template.render(Object.new, :name => name, :mail => mail, :body_part => body_part)
    else
      "<h1>Not implemented</h1>"
    end
  end

  def params
    @params ||= HashWithIndifferentAccess.new(Rack::Utils.parse_nested_query(@rack_env['QUERY_STRING']))
  end

end
