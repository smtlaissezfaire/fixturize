require 'date'

Gem::Specification.new do |s|
  s.name        = 'fixturize'
  s.version     = '0.1.17'
  s.date        = Date.today.to_s
  s.summary     = "fixturize your mongo tests inline"
  s.description = "fixturize your mongo(mapper) tests inline by caching blocks of created objects"
  s.authors     = ["Scott Taylor", "Andrew Pariser"]
  s.email       = ['scott@railsnewbie.com', 'pariser@gmail.com']
  s.files       = Dir.glob("lib/**/**.rb")
  s.homepage    =
    'http://github.com/smtlaissezfaire/fixturize'
  s.license       = 'MIT'
  s.add_dependency 'method_source'
end
