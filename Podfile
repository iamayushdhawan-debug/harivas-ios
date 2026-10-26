# Podfile – HARIVAS iOS
# Firebase Messaging for all 5 targets

platform :ios, '15.0'
use_frameworks!
inhibit_all_warnings!

# Firebase pod spec source
source 'https://cdn.cocoapods.org/'

def shared_pods
  pod 'Firebase/Core'
  pod 'Firebase/Messaging'
end

target 'HARIVASStore' do
  shared_pods
end

target 'HARIVASRider' do
  shared_pods
end

target 'HARIVASVendor' do
  shared_pods
end

target 'HARIVASStaff' do
  shared_pods
end

target 'HARIVASAdmin' do
  shared_pods
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      config.build_settings['SWIFT_VERSION'] = '5.9'
      # Suppress annoying warnings from third-party code
      config.build_settings['GCC_WARN_INHIBIT_ALL_WARNINGS'] = 'YES'
    end
  end
end
