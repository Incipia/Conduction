#
# Be sure to run `pod lib lint Conduction.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'Conduction'
  s.version          = '0.0.1'
  s.summary          = 'A framework for separating logic for the user flow throughout an app.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
  A framework that helps assist in separating logic that's used for the user flow throughout an app.
                       DESC

  s.homepage         = 'https://github.com/Incipia/Conduction'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'gklei' => 'gregory@incipia.co' }
  s.source           = { :git => 'https://github.com/Incipia/Conduction.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '10.0'

  s.source_files = 'Conduction/Classes/**/*'
  
  # s.resource_bundles = {
  #   'Conduction' => ['Conduction/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
  s.dependency 'Bindable'
end
