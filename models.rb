require 'rubygems'
require 'dm-core'
require 'dm-timestamps'
require 'dm-aggregates'
require 'open-uri'

DataMapper.setup(:default, ENV['DATABASE_URL'] || 'mysql://root:root@localhost/chirp')
class User
  include DataMapper::Resource

  property :id,         Serial
  property :email,      String, :length => 255
  property :nickname,   String, :length => 255
  property :identifier, String, :length => 255
  property :photo_url,  String, :length => 255

  has n, :chirps
  has n, :direct_messages, :class_name => "Chirp"
  has n, :relationships
  has n, :followers, :through => :relationships, :class_name => "User", :child_key => [:user_id]
  has n, :follows, :through => :relationships, :class_name => "User", :remote_name => :user, :child_key => [:follower_id]                       

  def self.find(identifier)
    u = first(:identifier => identifier)
    u = new(:identifier => identifier) if u.nil?
    return u
  end    

  def displayed_chirps
    chirps = []
    chirps += self.chirps.all(:recipient_id => nil, :limit => 10, :order => [:created_at.desc]) # don't show direct messsages
    self.follows.each do |follows| chirps += follows.chirps.all(:recipient_id => nil, :limit => 10, :order => [:created_at.desc]) end if @myself == @user
    chirps.sort! { |x,y| y.created_at <=> x.created_at }
    chirps[0..10]    
  end

end

class Relationship
  include DataMapper::Resource

  property :user_id, Integer, :key => true
  property :follower_id, Integer, :key => true
  belongs_to :user, :child_key => [:user_id]
  belongs_to :follower, :class_name => "User", :child_key => [:follower_id]
end

class Chirp
  include DataMapper::Resource

  property :id, Serial
  property :text, String, :length => 140
  property :created_at,  DateTime  
  belongs_to :recipient, :class_name => "User", :child_key => [:recipient_id]
  belongs_to :user  

  before :save do
    case 
    when starts_with?('dm ') 
      process_dm
    when starts_with?('follow ') 
      process_follow
    else 
      process
    end
  end

  # general scrubbing of chirp
  def process
    # process url
    urls = self.text.scan(URL_REGEXP)
    urls.each { |url|
      tiny_url = open("http://tinyurl.com/api-create.php?url=#{url[0]}") {|s| s.read}    
      self.text.sub!(url[0], "<a href='#{tiny_url}'>#{tiny_url}</a>")
    }        
    # process @
    ats = self.text.scan(AT_REGEXP)
    ats.each { |at| self.text.sub!(at, "<a href='/#{at[2,at.length]}'>#{at}</a>") }            
  end

  # process direct messages 
  def process_dm
    self.recipient = User.first(:email => self.text.split[1])  
    self.text = self.text.split[2..self.text.split.size].join(' ') # remove the first 2 words
    process
  end

  # process follow commands
  def process_follow 
    Relationship.create(:user => User.first(:email => self.text.split[1]), :follower => self.user)   
    throw :halt # don't save
  end

  def starts_with?(prefix)
    prefix = prefix.to_s
    self.text[0, prefix.length] == prefix
  end  
end

URL_REGEXP = Regexp.new('\b ((https?|telnet|gopher|file|wais|ftp) : [\w/#~:.?+=&%@!\-] +?) (?=[.:?\-] * (?: [^\w/#~:.?+=&%@!\-]| $ ))', Regexp::EXTENDED)
AT_REGEXP = Regexp.new('\s@[\w.@_-]+', Regexp::EXTENDED)