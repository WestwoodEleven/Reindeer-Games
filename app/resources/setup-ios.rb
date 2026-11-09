# Adds the Firebase config file and push-notification entitlement to the
# generated Xcode project. Run from app/ios/App.
require 'xcodeproj'
project = Xcodeproj::Project.open('App.xcodeproj')
target = project.targets.find { |t| t.name == 'App' }
group = project.main_group.find_subpath('App', false)
unless group.files.any? { |f| f.path == 'GoogleService-Info.plist' }
  ref = group.new_reference('GoogleService-Info.plist')
  target.add_resources([ref])
end
target.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/App.entitlements'
end
project.save
puts 'Xcode project updated'
