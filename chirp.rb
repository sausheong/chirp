require 'rubygems'
require 'sinatra'
require 'digest/md5'
require 'rack-flash'
require 'json' 
require 'net/http'
require 'net/https'
require 'models'

set :sessions, true
use Rack::Flash

['/', '/home'].each do |path|
  get path do
    if session[:userid].nil? then erb :login 
    else redirect "/#{User.get(session[:userid]).email}"
    end
  end
end

get '/logout' do
  session[:userid] = nil
  redirect '/'
end

get '/login' do
  openid_user = get_user(params[:token])
  user = User.find(openid_user[:identifier])
  user.update_attributes({:nickname => openid_user[:nickname], :email => openid_user[:email], :photo_url => "http://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(openid_user[:email])}"}) if user.new_record?
  session[:userid] = user.id # keep what is stored small
  redirect "/#{user.email}"
end

post '/chirp' do
  user = User.get(session[:userid])
  Chirp.create(:text => params[:chirp], :user => user)
  redirect "/#{user.email}"
end

['/follows', '/followers'].each do |path|
  get path do
    @myself = User.get(session[:userid])
    @dm_count = dm_count
    erb :follows
  end
end

get '/:email' do
  @myself = User.get(session[:userid])
  @user = @myself.email == params[:email] ? @myself : User.first(:email => params[:email])
  @dm_count = dm_count   
  erb :home
end

get '/follow/:email' do
  Relationship.create(:user => User.first(:email => params[:email]), :follower => User.get(session[:userid]))
  redirect '/home'
end

delete '/follows/:user_id/:follows_id' do
  Relationship.first(:follower_id => params[:user_id], :user_id => params[:follows_id]).destroy
  redirect '/follows'
end

get '/direct_messages/:dir' do
  @myself = User.get(session[:userid])
  case params[:dir]
  when 'received' then @chirps = Chirp.all(:recipient_id => @myself.id)
  when 'sent'     then @chirps = Chirp.all(:user_id => @myself.id, :recipient_id.not => nil)
  end
  @dm_count = dm_count
  erb :direct_messages
end

error do
  flash[:error] = env['sinatra.error'].to_s
  redirect '/home'
end

# miscellaneous processing helpers
def dm_count
  Chirp.count(:recipient_id => session[:userid]) + Chirp.count(:user_id => session[:userid], :recipient_id.not => nil)
end

def get_user(token)
  u = URI.parse('https://rpxnow.com/api/v2/auth_info')
  req = Net::HTTP::Post.new(u.path)
  req.set_form_data({'token' => token, 'apiKey' => '30e2f26bb637982d6b236dd7f095d2b5ba897b3f', 'format' => 'json', 'extended' => 'true'})
  http = Net::HTTP.new(u.host,u.port)
  http.use_ssl = true if u.scheme == 'https'
  json = JSON.parse(http.request(req).body)
  
  if json['stat'] == 'ok'
    identifier = json['profile']['identifier']
    nickname = json['profile']['preferredUsername']
    nickname = json['profile']['displayName'] if nickname.nil?
    email = json['profile']['email']
    {:identifier => identifier, :nickname => nickname, :email => email}
  else
    raise LoginFailedError, 'Cannot log in. Try another account!' 
  end
end

# template helpers
helpers do
  def time_ago_in_words(timestamp)
    minutes = (((Time.now - timestamp).abs)/60).round
    return nil if minutes < 0

    case minutes
    when 0               then 'less than a minute ago'
    when 0..4            then 'less than 5 minutes ago'
    when 5..14           then 'less than 15 minutes ago'
    when 15..29          then 'less than 30 minutes ago'
    when 30..59          then 'more than 30 minutes ago'
    when 60..119         then 'more than 1 hour ago'
    when 120..239        then 'more than 2 hours ago'
    when 240..479        then 'more than 4 hours ago'
    else                 timestamp.strftime('%I:%M %p %d-%b-%Y')
    end
  end
end